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
    else
        echo -e "  ${CROSS} Failed to close PR"
        return 1
    fi

    # Check for matching submodule PR
    if [[ -n "$SUBMODULE_REPO" && "$SUBMODULE_MODE" != "true" ]]; then
        local sub_json sub_info
        sub_json=$(get_cached_submodule_prs)
        sub_info=$(echo "$sub_json" | jq -r --arg topic "$topic" '
            .[] |
            ((.body | capture("Topic:\\s*(?<t>\\S+)") | .t) // (.headRefName | split("/") | last)) as $t |
            select($t == $topic) |
            "\(.number)|\(.title)|\(.url)"' 2>/dev/null | head -1)

        if [[ -n "$sub_info" ]]; then
            local sub_number sub_title sub_url
            IFS='|' read -r sub_number sub_title sub_url <<< "$sub_info"
            echo ""
            echo -e "${YELLOW}Found matching submodule PR:${NC} #${sub_number} - ${sub_title}"
            read -p "Close submodule PR too? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if gh pr close "$sub_number" -R "$SUBMODULE_REPO"; then
                    echo -e "  ${CHECK} Closed submodule PR #${sub_number}"
                else
                    echo -e "  ${CROSS} Failed to close submodule PR #${sub_number}"
                    return 1
                fi
            fi
        fi
    fi
}
