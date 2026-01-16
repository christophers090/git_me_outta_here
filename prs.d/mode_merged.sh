# prs merged mode - show recent merged PRs
# shellcheck shell=bash

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

    local cache_key="merged_${limit}"
    local prs_json

    echo -e "${BOLD}Recent merged PRs:${NC}"
    echo ""

    if cache_is_fresh "$cache_key" "$CACHE_TTL_MERGED"; then
        prs_json=$(cache_get "$cache_key")
        _render_merged "$prs_json"
    else
        prs_json=$(gh pr list -R "$REPO" --author "$GITHUB_USER" --state merged --limit "$limit" \
            --json number,title,url,headRefName,mergedAt)
        if [[ -n "$prs_json" && "$prs_json" != "[]" ]]; then
            cache_set "$cache_key" "$prs_json"
        fi
        _render_merged "$prs_json"
    fi
}
