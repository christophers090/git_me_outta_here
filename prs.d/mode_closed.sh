# prs closed mode - show recent closed (not merged) PRs
# shellcheck shell=bash

_render_closed() {
    local prs_json="$1"
    local limit="$2"
    echo "$prs_json" | jq -r --argjson limit "$limit" '[.[] | select(.mergedAt == null)] | .[0:$limit] | .[] | (.headRefName | split("/") | last) as $topic | "\(.number)|\(.title)|\(.url)|\($topic)"' \
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

    local cache_key="closed"
    local prs_json

    echo -e "${BOLD}Recent closed PRs (not merged):${NC}"
    echo ""

    if cache_is_fresh "$cache_key" "$CACHE_TTL_CLOSED"; then
        prs_json=$(cache_get "$cache_key")
        _render_closed "$prs_json" "$limit"
    else
        prs_json=$(gh pr list -R "$REPO" --author "$GITHUB_USER" --state closed --limit 50 \
            --json number,title,url,headRefName,closedAt,mergedAt)
        if [[ -n "$prs_json" && "$prs_json" != "[]" ]]; then
            cache_set "$cache_key" "$prs_json"
        fi
        _render_closed "$prs_json" "$limit"
    fi
}
