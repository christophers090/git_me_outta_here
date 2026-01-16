# prs remove_queue mode - remove PR from merge queue
# shellcheck shell=bash

run_remove_queue() {
    local topic="$1"
    require_topic "remove_queue" "$topic" || return 1

    local pr_json
    pr_json=$(cached_find_pr "$topic" "open" "number,title,url,autoMergeRequest")

    if ! pr_exists "$pr_json"; then
        pr_not_found_open "$topic"
        return 1
    fi

    local number title url auto_merge
    number=$(pr_field "$pr_json" "number")
    title=$(pr_field "$pr_json" "title")
    url=$(pr_field "$pr_json" "url")
    auto_merge=$(echo "$pr_json" | jq -r '.[0].autoMergeRequest // empty')

    if [[ -z "$auto_merge" || "$auto_merge" == "null" ]]; then
        echo -e "${YELLOW}PR #${number} is not in merge queue${NC}"
        echo -e "  ${title}"
        return 1
    fi

    echo -e "${BOLD}Removing from merge queue:${NC} #${number} - ${title}"
    echo -e "  ${CYAN}${url}${NC}"

    if gh pr merge "$number" -R "$REPO" --disable-auto; then
        echo -e "  ${CHECK} Removed from merge queue"
        return 0
    else
        echo -e "  ${CROSS} Failed to remove from merge queue"
        return 1
    fi
}
