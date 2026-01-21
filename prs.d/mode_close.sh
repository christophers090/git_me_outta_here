# prs close mode - close a PR
# shellcheck shell=bash

run_close() {
    local topic="$1"
    get_pr_or_fail "$topic" "close" "open" || return 1
    pr_basics

    echo -e "${BOLD}Closing PR:${NC} #${PR_NUMBER} - ${PR_TITLE}"
    echo -e "  ${CYAN}${PR_URL}${NC}"

    if gh pr close "$PR_NUMBER" -R "$REPO"; then
        invalidate_pr_caches "$topic"
        return 0
    else
        echo -e "  ${CROSS} Failed to close PR"
        return 1
    fi
}
