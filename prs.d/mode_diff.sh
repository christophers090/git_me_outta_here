# prs diff mode - show PR diff
# shellcheck shell=bash

run_diff() {
    local topic="$1"
    require_topic "diff" "$topic" || return 1

    local pr_json
    pr_json=$(find_pr "$topic" "all" "number,title")

    if ! pr_exists "$pr_json"; then
        pr_not_found "$topic"
        return 1
    fi

    local number title
    number=$(pr_field "$pr_json" "number")
    title=$(pr_field "$pr_json" "title")

    echo -e "${BOLD}${BLUE}PR #${number}:${NC} ${title}"
    echo ""

    gh pr diff "$number" -R "$REPO"
}
