# prs web mode - open GitHub PR in browser
# shellcheck shell=bash

run_web() {
    local topic="$1"
    get_pr_or_fail "$topic" "web" || return 1
    pr_basics

    echo -e "${BOLD}Opening PR #${PR_NUMBER}:${NC} ${PR_TITLE}"
    echo -e "  ${CYAN}${PR_URL}${NC}"

    open_url "$PR_URL"
}
