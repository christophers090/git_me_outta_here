# prs merge mode - enable auto-merge on PR
# shellcheck shell=bash

run_merge() {
    local topic="$1"
    require_topic "merge" "$topic" || return 1

    local pr_json
    pr_json=$(cached_find_pr "$topic" "open" "number,title,baseRefName,url")

    if ! pr_exists "$pr_json"; then
        pr_not_found_open "$topic"
        return 1
    fi

    local number title base url
    number=$(pr_field "$pr_json" "number")
    title=$(pr_field "$pr_json" "title")
    base=$(pr_field "$pr_json" "baseRefName")
    url=$(pr_field "$pr_json" "url")

    # SAFETY: Only allow merging to main
    if [[ "$base" != "main" ]]; then
        echo -e "${RED}ERROR:${NC} PR #${number} targets '${base}', not 'main'"
        echo -e "  ${DIM}Only PRs targeting main can be merged${NC}"
        echo -e "  ${DIM}Title: ${title}${NC}"
        return 1
    fi

    echo -e "${BOLD}Enabling auto-merge:${NC} #${number} - ${title}"
    echo -e "  ${CYAN}${url}${NC}"

    if gh pr merge "$number" -R "$REPO" --rebase --auto; then
        invalidate_pr_caches "$topic"
        return 0
    else
        echo -e "  ${CROSS} Failed to enable auto-merge"
        return 1
    fi
}
