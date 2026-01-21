# prs files mode - list changed files in PR
# shellcheck shell=bash

run_files() {
    local topic="$1"
    get_pr_or_fail "$topic" "files" "all" "number,title,files" || return 1
    pr_basics

    echo -e "${BOLD}${BLUE}PR #${PR_NUMBER}:${NC} ${PR_TITLE}"
    echo ""

    echo "$PR_JSON" | jq -r '.[0].files[] | "\(.path) (+\(.additions)/-\(.deletions))"'
}
