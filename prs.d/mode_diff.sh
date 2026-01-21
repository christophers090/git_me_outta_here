# prs diff mode - show PR diff
# shellcheck shell=bash

run_diff() {
    local topic="$1"
    get_pr_or_fail "$topic" "diff" "all" "number,title" || return 1
    pr_basics

    echo -e "${BOLD}${BLUE}PR #${PR_NUMBER}:${NC} ${PR_TITLE}"
    echo ""

    gh pr diff "$PR_NUMBER" -R "$REPO"
}
