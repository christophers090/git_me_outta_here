# prs shared helpers - sourced by main script
# shellcheck shell=bash

# Print error message to stderr
error_msg() {
    echo -e "${RED}Error:${NC} $1" >&2
}

# Update tab completion cache from PR JSON
# Usage: update_completion_cache "$prs_json"
update_completion_cache() {
    local prs_json="$1"
    local sub_json="${2:-}"
    local cache_file="/tmp/prs_topics_cache_${USER}"
    {
        echo "$prs_json" | jq -r '.[] | ((.body | capture("Topic:\\s*(?<t>\\S+)") | .t) // (.headRefName | split("/") | last))' 2>/dev/null
        if [[ -n "$sub_json" && "$sub_json" != "[]" ]]; then
            echo "$sub_json" | jq -r '.[] | ((.body | capture("Topic:\\s*(?<t>\\S+)") | .t) // (.headRefName | split("/") | last))' 2>/dev/null
        fi
    } | sort -u > "$cache_file"
}

# Find PR by topic - eliminates duplicated lookup code
# Usage: find_pr <topic> [state] [fields]
# state: open|closed|merged|all (default: all)
# fields: comma-separated jq fields (default: number,title,url)
find_pr() {
    local topic="$1"
    local state="${2:-all}"
    local fields="${3:-number,title,url}"

    # If topic is a PR number, look it up directly
    if [[ "$topic" =~ ^[0-9]+$ ]]; then
        local pr_json
        pr_json=$(gh pr view "$topic" -R "$REPO" --json "$fields,state" 2>/dev/null || echo "{}")
        if [[ -n "$pr_json" && "$pr_json" != "{}" ]]; then
            local pr_state
            pr_state=$(echo "$pr_json" | jq -r '.state' 2>/dev/null)
            # Check state filter matches
            local state_match=false
            case "$state" in
                all) state_match=true ;;
                open) [[ "$pr_state" == "OPEN" ]] && state_match=true ;;
                closed) [[ "$pr_state" == "CLOSED" ]] && state_match=true ;;
                merged) [[ "$pr_state" == "MERGED" ]] && state_match=true ;;
            esac
            if [[ "$state_match" == "true" ]]; then
                echo "$pr_json" | jq --argjson fields "$(echo "$fields" | jq -R 'split(",")')" \
                    '[. | to_entries | map(select(.key as $k | $fields | index($k))) | from_entries]'
                return 0
            fi
        fi
    fi

    # Search by author - match branch name first, fall back to body Topic: field
    local author_prs
    author_prs=$(gh pr list -R "$REPO" --author "$GITHUB_USER" --state "$state" -L 200 \
        --json "$fields,headRefName,body" 2>/dev/null || echo "[]")

    local result
    result=$(echo "$author_prs" \
        | jq --arg topic "$topic" '
            ($topic | gsub("(?<c>[.+*?^${}()|\\[\\]])"; "\\\(.c)")) as $escaped |
            ([.[] | select(.headRefName | endswith("/" + $topic))] | .[0:1]) as $by_branch |
            if ($by_branch | length) > 0 then $by_branch
            else [.[] | select(.body | test("Topic:\\s*" + $escaped + "\\b"))] | .[0:1]
            end | map(del(.headRefName, .body))' \
        2>/dev/null || echo "[]")

    echo "$result"
}

# Check if PR JSON array has results
pr_exists() {
    [[ "$(echo "$1" | jq 'length')" -gt 0 ]]
}

# Extract field from PR JSON (first element)
pr_field() {
    echo "$1" | jq -r ".[0].$2 // empty"
}

# Print error for missing PR
pr_not_found() {
    local topic="$1"
    echo -e "${RED}No PR found for topic:${NC} $topic"
}

# Print error for missing open PR
pr_not_found_open() {
    local topic="$1"
    echo -e "${RED}No open PR found for topic:${NC} $topic"
}

# Print error for missing closed PR
pr_not_found_closed() {
    local topic="$1"
    echo -e "${RED}No closed PR found for topic:${NC} $topic"
}

# Find PR or print error and return failure
# Sets PR_JSON global variable on success
# Args: $1=topic, $2=mode, $3=state (default: all), $4=fields (default: number,title,url)
# Returns: 0 if found, 1 if not found (with error message printed)
get_pr_or_fail() {
    local topic="$1"
    local mode="$2"
    local state="${3:-all}"
    local fields="${4:-number,title,url}"

    require_topic "$mode" "$topic" || return 1

    PR_JSON=$(cached_find_pr "$topic" "$state" "$fields")

    if ! pr_exists "$PR_JSON"; then
        case "$state" in
            open) pr_not_found_open "$topic" ;;
            closed) pr_not_found_closed "$topic" ;;
            *) pr_not_found "$topic" ;;
        esac
        return 1
    fi
    return 0
}

# Extract common PR fields to global variables
# Requires PR_JSON to be set (from get_pr_or_fail)
# Sets: PR_NUMBER, PR_TITLE, PR_URL
pr_basics() {
    PR_NUMBER=$(pr_field "$PR_JSON" "number")
    PR_TITLE=$(pr_field "$PR_JSON" "title")
    PR_URL=$(pr_field "$PR_JSON" "url")
}

# Get topics from current branch (for "this" mode)
get_branch_topics() {
    local base_ref="origin/main"
    git rev-parse --verify "$base_ref" &>/dev/null || base_ref="main"
    git log --format="%B" "${base_ref}..HEAD" 2>/dev/null \
        | grep -oP 'Topic:\s*\K\S+' | sort -u
}

# Print PR header (number, title, url)
print_pr_header() {
    local number="$1" title="$2" url="$3"
    echo -e "${BOLD}${BLUE}PR #${number}:${NC} ${title}"
    echo -e "URL: ${CYAN}${url}${NC}"
}

# Require a topic argument, exit if missing
require_topic() {
    local mode="$1"
    local topic="$2"
    local flag="${3:-}"
    if [[ -z "$topic" ]]; then
        echo -e "${RED}Error:${NC} Topic required for ${mode}"
        if [[ -n "$flag" ]]; then
            echo "Usage: prs ${flag} <topic>"
        fi
        return 1
    fi
}

# Format seconds to human readable duration
format_duration() {
    local seconds="$1"
    if [[ $seconds -lt 60 ]]; then
        echo "${seconds}s"
    elif [[ $seconds -lt 3600 ]]; then
        local mins=$((seconds / 60))
        local secs=$((seconds % 60))
        echo "${mins}m ${secs}s"
    else
        local hours=$((seconds / 3600))
        local mins=$(((seconds % 3600) / 60))
        echo "${hours}h ${mins}m"
    fi
}

# Open URL in browser (cross-platform)
open_url() {
    local url="$1"
    local err
    if err=$(xdg-open "$url" 2>&1); then
        return 0
    elif err=$(open "$url" 2>&1); then
        return 0
    else
        echo -e "${YELLOW}Could not open browser. URL:${NC} $url"
        [[ -n "$err" ]] && echo -e "${DIM}${err}${NC}"
        return 1
    fi
}

# Require a comment number argument
require_comment_num() {
    local comment_num="$1"
    local mode_flag="$2"
    if [[ -z "$comment_num" ]]; then
        echo -e "${RED}Error:${NC} Comment number required"
        echo "Usage: prs ${mode_flag} <topic> <#>"
        return 1
    fi
}

# Copy title and URL to clipboard
copy_to_clipboard() {
    local number="$1"
    local title="$2"
    local url="$3"
    local ci_status="$4"
    local review_ok="$5"

    local ci_sym="X"
    local review_sym="X"
    [[ "$ci_status" == "pass" ]] && ci_sym="V"
    [[ "$ci_status" == "pending" ]] && ci_sym="O"
    [[ "$review_ok" == "true" ]] && review_sym="V"

    local text="${ci_sym}|${review_sym} #${number}: ${title}
${url}"

    if command -v xsel &>/dev/null; then
        echo -n "$text" | xsel --clipboard --input
        echo -e "${GREEN}Copied${NC}"
    elif command -v xclip &>/dev/null; then
        # xclip forks and holds clipboard data - just let it run
        echo -n "$text" | xclip -selection clipboard
        echo -e "${GREEN}Copied${NC}"
    elif command -v wl-copy &>/dev/null; then
        echo -n "$text" | wl-copy
        echo -e "${GREEN}Copied${NC}"
    else
        echo -e "${RED}No clipboard tool found${NC}" >&2
    fi
}

# Copy PR data to clipboard from JSON (returns 0 if copied, 1 otherwise)
copy_pr_to_clipboard() {
    local pr_json="$1"

    local number title url ci_status review_ok

    # Extract each field separately to avoid read issues
    number=$(echo "$pr_json" | jq -r '.[0].number')
    title=$(echo "$pr_json" | jq -r '.[0].title')
    url=$(echo "$pr_json" | jq -r '.[0].url')
    ci_status=$(echo "$pr_json" | jq -r --arg ci_ctx "$CI_CHECK_CONTEXT" '.[0] |
        ([(.statusCheckRollup // [])[] | select(.context | startswith($ci_ctx))] |
            if length == 0 then "pass"
            elif ([.[] | select(.state == "FAILURE" or .state == "ERROR")] | length > 0) then "fail"
            elif ([.[] | select(.state == "PENDING")] | length > 0) then "pending"
            else "pass" end)')
    review_ok=$(echo "$pr_json" | jq -r '.[0].reviewDecision == "APPROVED"')

    copy_to_clipboard "$number" "$title" "$url" "$ci_status" "$review_ok"
}

# ── Submodule helpers ──────────────────────────────────────────────

# Fetch all open submodule PRs (single API call)
# Returns JSON array with number, title, url, headRefName, reviewDecision, body
fetch_submodule_prs() {
    [[ -n "$SUBMODULE_REPO" ]] || return 0
    gh pr list -R "$SUBMODULE_REPO" --author "$GITHUB_USER" --state open \
        --json number,title,url,headRefName,reviewDecision,body 2>/dev/null || echo "[]"
}

# Get submodule PRs - always fetches fresh, caches result
# Returns JSON array
get_cached_submodule_prs() {
    [[ -n "$SUBMODULE_REPO" ]] || { echo "[]"; return 0; }

    local result
    result=$(fetch_submodule_prs)
    if [[ -n "$result" && "$result" != "[]" ]]; then
        cache_set "sub_outstanding" "$result"
    fi
    echo "$result"
}

# Parse submodule PRs into topic-keyed lookup lines
# Input: submodule PRs JSON
# Output: lines of "topic|number|title|url|review_ok" for each PR
parse_submodule_pr_map() {
    local sub_json="$1"
    [[ -z "$sub_json" || "$sub_json" == "[]" ]] && return 0
    echo "$sub_json" | jq -r '.[] |
        ((.body | capture("Topic:\\s*(?<t>\\S+)") | .t) // (.headRefName | split("/") | last)) as $topic |
        (.reviewDecision == "APPROVED") as $review_ok |
        "\($topic)|\(.number)|\(.title)|\(.url)|\($review_ok)"'
}
