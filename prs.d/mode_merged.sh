# prs merged mode - show recent merged PRs
# shellcheck shell=bash

# Module-level state for render/fetch functions
_MERGED_LIMIT=10

_fetch_merged() {
    gh pr list -R "$REPO" --author "$GITHUB_USER" --state merged --limit "$_MERGED_LIMIT" \
        --json number,title,url,headRefName,mergedAt
}

_render_merged() {
    local prs_json="$1"
    echo "$prs_json" | jq -r '.[] | (.headRefName | split("/") | last) as $topic | "\(.number)|\(.title)|\(.url)|\($topic)|\(.mergedAt)"' \
        | while IFS='|' read -r number title url topic merged_at; do
            echo -e "${CHECK} ${BOLD}#${number}:${NC} ${title}"
            echo -e "    ${DIM}Topic:${NC} ${topic}"
            echo -e "    ${CYAN}${url}${NC}"
            echo ""
        done
}

run_merged() {
    local limit="${1:-10}"
    [[ ! "$limit" =~ ^[0-9]+$ ]] && limit=10
    _MERGED_LIMIT="$limit"

    echo -e "${BOLD}Recent merged PRs:${NC}"
    echo ""

    display_with_refresh "merged_${limit}" "_fetch_merged" "_render_merged" "Fetching merged PRs..."
}
