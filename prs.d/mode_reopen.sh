# prs reopen mode - reopen a closed PR
# shellcheck shell=bash

run_reopen() {
    local topic="$1"
    get_pr_or_fail "$topic" "reopen" "closed" || return 1
    pr_basics

    echo -e "${BOLD}Reopening PR:${NC} #${PR_NUMBER} - ${PR_TITLE}"
    echo -e "  ${CYAN}${PR_URL}${NC}"

    if gh pr reopen "$PR_NUMBER" -R "$REPO"; then
        echo -e "  ${CHECK} PR reopened"
        invalidate_pr_caches "$topic"
        return 0
    else
        echo -e "  ${CROSS} Failed to reopen PR"
        return 1
    fi
}
