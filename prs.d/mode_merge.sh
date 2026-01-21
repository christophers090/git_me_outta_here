# prs merge mode - enable auto-merge on PR
# shellcheck shell=bash

run_merge() {
    local topic="$1"
    get_pr_or_fail "$topic" "merge" "open" "number,title,baseRefName,url" || return 1
    pr_basics
    local base
    base=$(pr_field "$PR_JSON" "baseRefName")

    # SAFETY: Only allow merging to main
    if [[ "$base" != "main" ]]; then
        echo -e "${RED}ERROR:${NC} PR #${PR_NUMBER} targets '${base}', not 'main'"
        echo -e "  ${DIM}Only PRs targeting main can be merged${NC}"
        echo -e "  ${DIM}Title: ${PR_TITLE}${NC}"
        return 1
    fi

    echo -e "${BOLD}Enabling auto-merge:${NC} #${PR_NUMBER} - ${PR_TITLE}"
    echo -e "  ${CYAN}${PR_URL}${NC}"

    if gh pr merge "$PR_NUMBER" -R "$REPO" --rebase --auto; then
        invalidate_pr_caches "$topic"
        return 0
    else
        echo -e "  ${CROSS} Failed to enable auto-merge"
        return 1
    fi
}
