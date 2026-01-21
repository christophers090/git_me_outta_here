# prs closed mode - show recent closed (not merged) PRs
# shellcheck shell=bash

# Module-level state for render function
_CLOSED_LIMIT=10

_fetch_closed() {
    gh pr list -R "$REPO" --author "$GITHUB_USER" --state closed --limit 50 \
        --json number,title,url,headRefName,closedAt,mergedAt
}

_render_closed() {
    local prs_json="$1"
    echo "$prs_json" | jq -r --argjson limit "$_CLOSED_LIMIT" '[.[] | select(.mergedAt == null)] | .[0:$limit] | .[] | (.headRefName | split("/") | last) as $topic | "\(.number)|\(.title)|\(.url)|\($topic)"' \
        | while IFS='|' read -r number title url topic; do
            [[ -z "$number" ]] && continue
            echo -e "${CROSS} ${BOLD}#${number}:${NC} ${title}"
            echo -e "    ${DIM}Topic:${NC} ${topic}"
            echo -e "    ${CYAN}${url}${NC}"
            echo ""
        done
}

run_closed() {
    local limit="${1:-10}"
    [[ ! "$limit" =~ ^[0-9]+$ ]] && limit=10
    _CLOSED_LIMIT="$limit"

    echo -e "${BOLD}Recent closed PRs (not merged):${NC}"
    echo ""

    display_with_refresh "closed" "_fetch_closed" "_render_closed" "Fetching closed PRs..."
}
