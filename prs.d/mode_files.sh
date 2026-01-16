# prs files mode - list changed files in PR
# shellcheck shell=bash

run_files() {
    local topic="$1"
    require_topic "files" "$topic" || return 1

    local pr_json
    pr_json=$(cached_find_pr "$topic" "all" "number,title,files")

    if ! pr_exists "$pr_json"; then
        pr_not_found "$topic"
        return 1
    fi

    local number title
    number=$(pr_field "$pr_json" "number")
    title=$(pr_field "$pr_json" "title")

    echo -e "${BOLD}${BLUE}PR #${number}:${NC} ${title}"
    echo ""

    echo "$pr_json" | jq -r '.[0].files[] | "\(.path) (+\(.additions)/-\(.deletions))"'
}
