# prs merged mode - show recent merged PRs
# shellcheck shell=bash

# Module-level state for render/fetch functions
_MERGED_LIMIT=10
_MERGED_TOPIC=""

_fetch_merged() {
    gh pr list -R "$REPO" --author "$GITHUB_USER" --state merged --limit "$_MERGED_LIMIT" \
        --json number,title,url,headRefName,mergedAt,body
}

_render_merged() {
    local prs_json="$1"
    echo "$prs_json" | jq -r --arg topic "$_MERGED_TOPIC" '
        (if $topic != "" then
            [.[] | select(
                (.headRefName | endswith("/" + $topic)) or
                (.body | test("Topic:\\s*" + $topic + "\\b"; "x") // false)
            )]
        else . end) |
        .[] |
        ((.body | capture("Topic:\\s*(?<t>\\S+)") | .t) // (.headRefName | split("/") | last)) as $t |
        "\(.number)|\(.title)|\(.url)|\($t)|\(.mergedAt)"' \
        | while IFS='|' read -r number title url topic merged_at; do
            echo -e "${CHECK} ${BOLD}#${number}:${NC} ${title}"
            echo -e "    ${DIM}Topic:${NC} ${topic}"
            echo -e "    ${CYAN}${url}${NC}"
            echo ""
        done
}

run_merged() {
    local arg="${1:-}"
    local limit=10
    local topic=""

    if [[ "$arg" =~ ^[0-9]+$ ]]; then
        limit="$arg"
    elif [[ -n "$arg" ]]; then
        topic="$arg"
    fi
    _MERGED_LIMIT="$limit"
    _MERGED_TOPIC="$topic"

    if [[ -n "$topic" ]]; then
        echo -e "${BOLD}Merged PRs matching topic: ${CYAN}${topic}${NC}"
    else
        echo -e "${BOLD}Recent merged PRs:${NC}"
    fi
    echo ""

    display_with_refresh "merged_${limit}" "_fetch_merged" "_render_merged" "Fetching merged PRs..."
}
