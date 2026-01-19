# prs close mode - close a PR
# shellcheck shell=bash

run_close() {
    local topic="$1"
    require_topic "close" "$topic" || return 1

    local pr_json
    pr_json=$(cached_find_pr "$topic" "open" "number,title,url")

    if ! pr_exists "$pr_json"; then
        pr_not_found_open "$topic"
        return 1
    fi

    local number title url
    number=$(pr_field "$pr_json" "number")
    title=$(pr_field "$pr_json" "title")
    url=$(pr_field "$pr_json" "url")

    echo -e "${BOLD}Closing PR:${NC} #${number} - ${title}"
    echo -e "  ${CYAN}${url}${NC}"

    if gh pr close "$number" -R "$REPO"; then
        invalidate_pr_caches "$topic"
        return 0
    else
        echo -e "  ${CROSS} Failed to close PR"
        return 1
    fi
}
