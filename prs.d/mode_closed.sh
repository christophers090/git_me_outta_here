# prs closed mode - show recent closed (not merged) PRs
# shellcheck shell=bash

run_closed() {
    local limit="${1:-10}"
    [[ ! "$limit" =~ ^[0-9]+$ ]] && limit=10

    echo -e "${BOLD}Recent closed PRs (not merged):${NC}"
    echo ""

    gh pr list -R "$REPO" --author "$GITHUB_USER" --state closed --limit 50 \
        --json number,title,url,headRefName,closedAt,mergedAt \
        | jq -r --argjson limit "$limit" '[.[] | select(.mergedAt == null)] | .[0:$limit] | .[] | (.headRefName | split("/") | last) as $topic | "\(.number)|\(.title)|\(.url)|\($topic)"' \
        | while IFS='|' read -r number title url topic; do
            [[ -z "$number" ]] && continue
            echo -e "${CROSS} ${BOLD}#${number}:${NC} ${title}"
            echo -e "    ${DIM}Topic:${NC} ${topic}"
            echo -e "    ${CYAN}${url}${NC}"
            echo ""
        done
}
