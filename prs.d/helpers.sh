# prs shared helpers - sourced by main script
# shellcheck shell=bash

# Update tab completion cache from PR JSON
# Usage: update_completion_cache "$prs_json"
update_completion_cache() {
    local prs_json="$1"
    local cache_file="/tmp/prs_topics_cache_${USER}"
    echo "$prs_json" | jq -r '.[] | ((.body | capture("Topic:\\s*(?<t>\\S+)") | .t) // (.headRefName | split("/") | last))' 2>/dev/null > "$cache_file"
}

# Find PR by topic - eliminates duplicated lookup code
# Usage: find_pr <topic> [state] [fields]
# state: open|closed|merged|all (default: all)
# fields: comma-separated jq fields (default: number,title,url)
find_pr() {
    local topic="$1"
    local state="${2:-all}"
    local fields="${3:-number,title,url}"

    # First try exact branch match
    local branch="${BRANCH_USER}/${BRANCH_PREFIX}/${topic}"
    local result
    result=$(gh pr list -R "$REPO" --head "$branch" --state "$state" --limit 1 \
        --json "$fields" 2>/dev/null || echo "[]")

    # If no results, try searching by author with topic in branch name
    if [[ "$(echo "$result" | jq 'length')" -eq 0 ]]; then
        result=$(gh pr list -R "$REPO" --author "$GITHUB_USER" --state "$state" \
            --json "$fields,headRefName" 2>/dev/null \
            | jq --arg topic "$topic" '[.[] | select(.headRefName | endswith("/" + $topic))] | .[0:1] | map(del(.headRefName))' \
            2>/dev/null || echo "[]")
    fi

    # If still no results, try searching by topic in PR body
    if [[ "$(echo "$result" | jq 'length')" -eq 0 ]]; then
        result=$(gh pr list -R "$REPO" --author "$GITHUB_USER" --state "$state" \
            --json "$fields,body" 2>/dev/null \
            | jq --arg topic "$topic" '[.[] | select(.body | test("Topic:\\s*" + $topic + "\\b"))] | .[0:1] | map(del(.body))' \
            2>/dev/null || echo "[]")
    fi

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

# Get topics from current branch (for "this" mode)
get_branch_topics() {
    local base_ref="origin/main"
    git rev-parse --verify "$base_ref" &>/dev/null || base_ref="main"
    git log --oneline --format="%s" "${base_ref}..HEAD" 2>/dev/null \
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
    if [[ -z "$topic" ]]; then
        echo -e "${RED}Error:${NC} Topic required for ${mode}"
        echo "Usage: prs -${mode:0:1} <topic>"
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
    xdg-open "$url" 2>/dev/null || open "$url" 2>/dev/null || {
        echo -e "${YELLOW}Could not open browser. URL:${NC} $url"
        return 1
    }
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
