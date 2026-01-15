# prs merged mode - show recent merged PRs
# shellcheck shell=bash

run_merged() {
    local limit="${1:-10}"
    [[ ! "$limit" =~ ^[0-9]+$ ]] && limit=10

    echo -e "${BOLD}Recent merged PRs:${NC}"
    echo ""

    gh pr list -R "$REPO" --author "$GITHUB_USER" --state merged --limit "$limit" \
        --json number,title,url,headRefName,mergedAt \
        | jq -r '.[] | (.headRefName | split("/") | last) as $topic | "\(.number)|\(.title)|\(.url)|\($topic)|\(.mergedAt)"' \
        | while IFS='|' read -r number title url topic merged_at; do
            echo -e "${CHECK} ${BOLD}#${number}:${NC} ${title}"
            echo -e "    ${DIM}Topic:${NC} ${topic}"
            echo -e "    ${CYAN}${url}${NC}"
            echo ""
        done
}
