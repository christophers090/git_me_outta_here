# prs Buildkite helpers - shared functions for Buildkite operations
# shellcheck shell=bash

# Get build info for a topic. Sets globals: BK_BUILD_NUMBER, BK_BUILD_JSON, BK_BUILD_URL
# Returns 1 if no build found
# Usage: get_build_for_topic <topic> [pr_number] [pr_title]
get_build_for_topic() {
    local topic="$1"
    local number="$2"
    local title="$3"

    # If PR info not provided, look it up
    if [[ -z "$number" ]]; then
        local pr_json
        pr_json=$(cached_find_pr "$topic" "all" "number,title,statusCheckRollup")

        if ! pr_exists "$pr_json"; then
            pr_not_found "$topic"
            return 1
        fi

        number=$(pr_field "$pr_json" "number")
        title=$(pr_field "$pr_json" "title")
        BK_BUILD_URL=$(echo "$pr_json" | jq -r ".[0].statusCheckRollup[]? | select(.context == \"${CI_CHECK_CONTEXT}\") | .targetUrl // empty" 2>/dev/null | head -1)
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
