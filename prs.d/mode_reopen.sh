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
    else
        echo -e "  ${CROSS} Failed to reopen PR"
        return 1
    fi

    # Check for matching closed PR in the other repo
    if [[ -n "$SUBMODULE_REPO" ]]; then
        local other_repo other_label other_json other_info
        if [[ "$SUBMODULE_MODE" == "true" ]]; then
            other_repo="$MAIN_REPO"
            other_label="main repo"
        else
            other_repo="$SUBMODULE_REPO"
            other_label="submodule"
        fi
        other_json=$(gh pr list -R "$other_repo" --author "$GITHUB_USER" --state closed \
            --json number,title,url,headRefName,body 2>/dev/null || echo "[]")
        other_info=$(echo "$other_json" | jq -r --arg topic "$topic" '
            .[] |
            ((.body | capture("Topic:\\s*(?<t>\\S+)") | .t) // (.headRefName | split("/") | last)) as $t |
            select($t == $topic) |
            "\(.number)|\(.title)|\(.url)"' 2>/dev/null | head -1)

        if [[ -n "$other_info" ]]; then
            local other_number other_title other_url
            IFS='|' read -r other_number other_title other_url <<< "$other_info"
            echo ""
            echo -e "${YELLOW}Found matching closed ${other_label} PR:${NC} #${other_number} - ${other_title}"
            read -p "Reopen ${other_label} PR too? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if gh pr reopen "$other_number" -R "$other_repo"; then
                    echo -e "  ${CHECK} Reopened ${other_label} PR #${other_number}"
                    rm -f "$MAIN_CACHE_DIR"/sub_outstanding.json "$MAIN_CACHE_DIR"/sub_outstanding.ts 2>/dev/null
                    rm -f "$MAIN_CACHE_DIR"/outstanding.json "$MAIN_CACHE_DIR"/outstanding.ts 2>/dev/null
                else
                    echo -e "  ${CROSS} Failed to reopen ${other_label} PR #${other_number}"
                    return 1
                fi
            fi
        fi
    fi
}
