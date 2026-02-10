# prs Buildkite helpers - shared functions for Buildkite operations
# shellcheck shell=bash

# Extract BK_BUILD_URL from PR JSON statusCheckRollup
# Sets global: BK_BUILD_URL
extract_bk_build_url() {
    local pr_json="$1"
    BK_BUILD_URL=$(echo "$pr_json" | jq -r ".[0].statusCheckRollup[]? | select(.context == \"${CI_CHECK_CONTEXT}\") | .targetUrl // empty" 2>/dev/null | head -1)
}

# Get Buildkite API token from config
bk_get_token() {
    local token
    token=$(grep 'api_token:' ~/.config/bk.yaml 2>/dev/null | head -1 | awk '{print $2}')
    if [[ -z "$token" ]]; then
        echo -e "${RED}Could not find Buildkite API token in ~/.config/bk.yaml${NC}" >&2
        return 1
    fi
    echo "$token"
}

# Two-phase PR lookup for build modes - find PR number cheaply, then fetch heavy fields for one PR
# Sets globals: PR_JSON, PR_NUMBER, PR_TITLE, BK_BUILD_URL
# Returns 1 if not found
get_build_pr_or_fail() {
    local topic="$1"
    local mode="$2"

    require_topic "$mode" "$topic" || return 1

    local pr_number=""

    # Phase 1: Find PR number cheaply
    if [[ "$topic" =~ ^[0-9]+$ ]]; then
        pr_number="$topic"
    else
        # Try outstanding cache first (no API call)
        local outstanding
        outstanding=$(cache_get "outstanding")
        if [[ -n "$outstanding" && "$outstanding" != "[]" ]]; then
            pr_number=$(echo "$outstanding" | jq -r --arg topic "$topic" '
                ($topic | gsub("(?<c>[.+*?^${}()|\\[\\]])"; "\\\(.c)")) as $escaped |
                [.[] | select(
                    (.headRefName | endswith("/" + $topic)) or
                    (.body | test("Topic:\\s*" + $escaped + "\\b"))
                )] | .[0].number // empty' 2>/dev/null)
        fi

        # Fall back to lightweight API lookup (just number, no heavy fields)
        if [[ -z "$pr_number" ]]; then
            local lookup
            lookup=$(find_pr "$topic" "all" "number")
            pr_number=$(echo "$lookup" | jq -r '.[0].number // empty' 2>/dev/null)
        fi
    fi

    if [[ -z "$pr_number" ]]; then
        pr_not_found "$topic"
        return 1
    fi

    # Phase 2: Fetch heavy fields for just this one PR
    local result
    result=$(gh pr view "$pr_number" -R "$REPO" --json number,title,statusCheckRollup 2>/dev/null)

    if [[ -z "$result" ]]; then
        pr_not_found "$topic"
        return 1
    fi

    PR_JSON="[$result]"
    PR_NUMBER=$(echo "$result" | jq -r '.number')
    PR_TITLE=$(echo "$result" | jq -r '.title')
    extract_bk_build_url "$PR_JSON"

    return 0
}

# Get build info for a topic. Sets globals: BK_BUILD_NUMBER, BK_BUILD_JSON, BK_BUILD_URL
# Returns 1 if no build found
# Usage: get_build_for_topic <topic> [pr_number] [pr_title]
get_build_for_topic() {
    local topic="$1"
    local number="$2"
    local title="$3"

    # If PR info not provided, look it up using two-phase fetch
    if [[ -z "$number" ]]; then
        if ! get_build_pr_or_fail "$topic" "build"; then
            return 1
        fi
        number="$PR_NUMBER"
        title="$PR_TITLE"
    fi

    # If BK_BUILD_URL not set, fetch statusCheckRollup for just this PR
    if [[ -z "${BK_BUILD_URL:-}" && -n "$number" ]]; then
        local scr_json
        scr_json=$(gh pr view "$number" -R "$REPO" --json statusCheckRollup 2>/dev/null)
        if [[ -n "$scr_json" ]]; then
            extract_bk_build_url "[$scr_json]"
        fi
    fi

    if [[ -z "$BK_BUILD_URL" ]]; then
        echo -e "${RED}No Buildkite build found for PR #${number}:${NC} ${title}"
        return 1
    fi

    # Extract build number from URL
    BK_BUILD_NUMBER=$(echo "$BK_BUILD_URL" | grep -oP '/builds/\K[0-9]+')

    if [[ -z "$BK_BUILD_NUMBER" ]]; then
        echo -e "${RED}Could not extract build number from URL${NC}"
        return 1
    fi

    # Get build JSON
    BK_BUILD_JSON=$(bk build view "$BK_BUILD_NUMBER" -p "${CI_CHECK_CONTEXT##*/}" -o json 2>&1)

    if [[ -z "$BK_BUILD_JSON" ]] || ! echo "$BK_BUILD_JSON" | jq -e '.jobs' &>/dev/null; then
        echo -e "${RED}Failed to get build details${NC}"
        return 1
    fi

    return 0
}

# Find job by number (1-indexed). Sets globals: BK_JOB_ID, BK_JOB_NAME, BK_JOB_STATE, BK_JOB_EXIT_STATUS
# Requires BK_BUILD_JSON to be set
# Returns 1 if job not found
get_job_by_number() {
    local job_num="$1"
    if ! [[ "$job_num" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error:${NC} Job number must be numeric: $job_num" >&2
        return 1
    fi
    local current_num=0

    BK_JOB_ID=""
    BK_JOB_NAME=""
    BK_JOB_STATE=""
    BK_JOB_EXIT_STATUS=""

    while read -r job; do
        current_num=$((current_num + 1))
        if [[ "$current_num" -eq "$job_num" ]]; then
            BK_JOB_ID=$(echo "$job" | jq -r '.id')
            BK_JOB_NAME=$(strip_emoji "$(echo "$job" | jq -r '.name')")
            [[ -z "$BK_JOB_NAME" ]] && BK_JOB_NAME="(pipeline)"
            BK_JOB_STATE=$(echo "$job" | jq -r '.state')
            BK_JOB_EXIT_STATUS=$(echo "$job" | jq -r '.exit_status // empty')
            return 0
        fi
    done < <(echo "$BK_BUILD_JSON" | jq -c '.jobs[] | select(.type == "script")')

    return 1
}

# Strip :emoji: codes from text
strip_emoji() {
    echo "$1" | sed 's/:[a-z_-]*://g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'
}

# Check if job can be canceled. Prints message and returns 1 if not cancelable.
check_job_cancelable() {
    local job_num="$1"
    local topic="$2"

    case "$BK_JOB_STATE" in
        running|scheduled|assigned)
            return 0
            ;;
        passed)
            echo -e "${GREEN}Job #${job_num} (${BK_JOB_NAME}) already passed${NC}"
            return 1
            ;;
        failed|timed_out)
            echo -e "${RED}Job #${job_num} (${BK_JOB_NAME}) already failed${NC}"
            [[ -n "$BK_JOB_EXIT_STATUS" && "$BK_JOB_EXIT_STATUS" != "null" ]] && echo -e "  Exit code: ${BK_JOB_EXIT_STATUS}"
            echo ""
            echo -e "Use ${CYAN}prs -br $topic $job_num${NC} to retry"
            return 1
            ;;
        canceled)
            echo -e "${YELLOW}Job #${job_num} (${BK_JOB_NAME}) already canceled${NC}"
            echo ""
            echo -e "Use ${CYAN}prs -br $topic $job_num${NC} to retry"
            return 1
            ;;
        waiting|waiting_failed)
            echo -e "${YELLOW}Job #${job_num} (${BK_JOB_NAME}) is waiting (blocked by dependency)${NC}"
            return 1
            ;;
        *)
            echo -e "${YELLOW}Job #${job_num} (${BK_JOB_NAME}) is ${BK_JOB_STATE}, cannot cancel${NC}"
            return 1
            ;;
    esac
}

# Check if job can be retried. Prints message and returns 1 if not retriable.
check_job_retriable() {
    local job_num="$1"
    local topic="$2"

    case "$BK_JOB_STATE" in
        failed|timed_out|canceled)
            return 0
            ;;
        passed)
            echo -e "${GREEN}Job #${job_num} (${BK_JOB_NAME}) already passed - no retry needed${NC}"
            return 1
            ;;
        running)
            echo -e "${YELLOW}Job #${job_num} (${BK_JOB_NAME}) is still running${NC}"
            echo ""
            echo -e "Use ${CYAN}prs -bc $topic $job_num${NC} to cancel"
            return 1
            ;;
        scheduled|assigned)
            echo -e "${YELLOW}Job #${job_num} (${BK_JOB_NAME}) is ${BK_JOB_STATE} (hasn't started yet)${NC}"
            echo ""
            echo -e "Use ${CYAN}prs -bc $topic $job_num${NC} to cancel"
            return 1
            ;;
        waiting|waiting_failed)
            echo -e "${YELLOW}Job #${job_num} (${BK_JOB_NAME}) is waiting (blocked by dependency)${NC}"
            return 1
            ;;
        *)
            echo -e "${YELLOW}Job #${job_num} (${BK_JOB_NAME}) is ${BK_JOB_STATE}, cannot retry${NC}"
            return 1
            ;;
    esac
}
