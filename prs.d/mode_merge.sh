# prs merge mode - add PR to merge queue
# shellcheck shell=bash

run_merge() {
    local topic="$1"
    require_topic "merge" "$topic" || return 1

    local pr_json
    pr_json=$(find_pr "$topic" "open" "number,title,baseRefName,url")

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
        echo -e "  ${DIM}Only PRs targeting main can be added to merge queue${NC}"
        echo -e "  ${DIM}Title: ${title}${NC}"
        return 1
    fi

    echo -e "${BOLD}Adding to merge queue:${NC} #${number} - ${title}"
    echo -e "  ${CYAN}${url}${NC}"

    if gh pr merge "$number" -R "$REPO"; then
        echo -e "  ${CHECK} Added to merge queue"
        return 0
    else
        echo -e "  ${CROSS} Failed to add to merge queue"
        return 1
    fi
}
