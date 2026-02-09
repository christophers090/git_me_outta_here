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

    # Check for matching PR in the other repo
    if [[ -n "$SUBMODULE_REPO" ]]; then
        local other_repo other_label other_json other_info
        if [[ "$SUBMODULE_MODE" == "true" ]]; then
            other_repo="$MAIN_REPO"
            other_label="main repo"
            other_json=$(gh pr list -R "$MAIN_REPO" --author "$GITHUB_USER" --state open \
                --json number,title,url,headRefName,body 2>/dev/null || echo "[]")
        else
            other_repo="$SUBMODULE_REPO"
            other_label="submodule"
            other_json=$(get_cached_submodule_prs)
        fi
        other_info=$(echo "$other_json" | jq -r --arg topic "$topic" '
            .[] |
            ((.body | capture("Topic:\\s*(?<t>\\S+)") | .t) // (.headRefName | split("/") | last)) as $t |
            select($t == $topic) |
            "\(.number)|\(.title)|\(.url)"' 2>/dev/null | head -1)

        if [[ -n "$other_info" ]]; then
            local other_number other_title other_url
            IFS='|' read -r other_number other_title other_url <<< "$other_info"
            echo ""
            echo -e "${YELLOW}Found matching ${other_label} PR:${NC} #${other_number} - ${other_title}"
            read -p "Close ${other_label} PR too? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if gh pr close "$other_number" -R "$other_repo"; then
                    echo -e "  ${CHECK} Closed ${other_label} PR #${other_number}"
                    # Invalidate caches for the other repo
                    rm -f "$MAIN_CACHE_DIR"/sub_outstanding.json "$MAIN_CACHE_DIR"/sub_outstanding.ts 2>/dev/null
                    rm -f "$MAIN_CACHE_DIR"/outstanding.json "$MAIN_CACHE_DIR"/outstanding.ts 2>/dev/null
                else
                    echo -e "  ${CROSS} Failed to close ${other_label} PR #${other_number}"
                    return 1
                fi
            fi
        fi
    fi
}
