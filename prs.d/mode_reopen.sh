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

    # Check for matching closed submodule PR
    if [[ -n "$SUBMODULE_REPO" && "$SUBMODULE_MODE" != "true" ]]; then
        local sub_json sub_info
        sub_json=$(gh pr list -R "$SUBMODULE_REPO" --author "$GITHUB_USER" --state closed \
            --json number,title,url,headRefName,body 2>/dev/null || echo "[]")
        sub_info=$(echo "$sub_json" | jq -r --arg topic "$topic" '
            .[] |
            ((.body | capture("Topic:\\s*(?<t>\\S+)") | .t) // (.headRefName | split("/") | last)) as $t |
            select($t == $topic) |
            "\(.number)|\(.title)|\(.url)"' 2>/dev/null | head -1)

        if [[ -n "$sub_info" ]]; then
            local sub_number sub_title sub_url
            IFS='|' read -r sub_number sub_title sub_url <<< "$sub_info"
            echo ""
            echo -e "${YELLOW}Found matching closed submodule PR:${NC} #${sub_number} - ${sub_title}"
            read -p "Reopen submodule PR too? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if gh pr reopen "$sub_number" -R "$SUBMODULE_REPO"; then
                    echo -e "  ${CHECK} Reopened submodule PR #${sub_number}"
                else
                    echo -e "  ${CROSS} Failed to reopen submodule PR #${sub_number}"
                    return 1
                fi
            fi
        fi
    fi
}
