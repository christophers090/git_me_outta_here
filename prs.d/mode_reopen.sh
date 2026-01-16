# prs reopen mode - reopen a closed PR
# shellcheck shell=bash

run_reopen() {
    local topic="$1"
    require_topic "reopen" "$topic" || return 1

    local pr_json
    pr_json=$(cached_find_pr "$topic" "closed" "number,title,url")

    if ! pr_exists "$pr_json"; then
        echo -e "${RED}No closed PR found for topic:${NC} $topic"
        return 1
    fi

    local number title url
    number=$(pr_field "$pr_json" "number")
    title=$(pr_field "$pr_json" "title")
    url=$(pr_field "$pr_json" "url")

    echo -e "${BOLD}Reopening PR:${NC} #${number} - ${title}"
    echo -e "  ${CYAN}${url}${NC}"

    if gh pr reopen "$number" -R "$REPO"; then
        echo -e "  ${CHECK} PR reopened"
        invalidate_pr_caches "$topic"
        return 0
    else
        echo -e "  ${CROSS} Failed to reopen PR"
        return 1
    fi
}
