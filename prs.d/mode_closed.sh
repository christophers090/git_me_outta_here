# prs closed mode - show recent closed (not merged) PRs
# shellcheck shell=bash

# Module-level state for render function
_CLOSED_LIMIT=10
_CLOSED_TOPIC=""

_fetch_closed() {
    gh pr list -R "$REPO" --author "$GITHUB_USER" --state closed --limit 20 \
        --json number,title,url,headRefName,closedAt,mergedAt,body
}

_render_closed() {
    local prs_json="$1"
    echo "$prs_json" | jq -r --argjson limit "$_CLOSED_LIMIT" --arg topic "$_CLOSED_TOPIC" '
        [.[] | select(.mergedAt == null)] |
        (if $topic != "" then
            [.[] | select(
                (.headRefName | endswith("/" + $topic)) or
                (.body | test("Topic:\\s*" + $topic + "\\b"; "x") // false)
            )]
        else . end) |
        .[0:$limit] | .[] |
        ((.body | capture("Topic:\\s*(?<t>\\S+)") | .t) // (.headRefName | split("/") | last)) as $t |
        "\(.number)|\(.title)|\(.url)|\($t)"' \
        | while IFS='|' read -r number title url topic; do
            [[ -z "$number" ]] && continue
            echo -e "${CROSS} ${BOLD}#${number}:${NC} ${title}"
            echo -e "    ${DIM}Topic:${NC} ${topic}"
            echo -e "    ${CYAN}${url}${NC}"
            echo ""
        done
}

run_closed() {
    local arg="${1:-}"
    local limit=10
    local topic=""

    if [[ "$arg" =~ ^[0-9]+$ ]]; then
        limit="$arg"
    elif [[ -n "$arg" ]]; then
        topic="$arg"
    fi
    _CLOSED_LIMIT="$limit"
    _CLOSED_TOPIC="$topic"

    if [[ -n "$topic" ]]; then
        echo -e "${BOLD}Closed PRs (not merged) matching topic: ${CYAN}${topic}${NC}"
    else
        echo -e "${BOLD}Recent closed PRs (not merged):${NC}"
    fi
    echo ""

    display_with_refresh "closed" "_fetch_closed" "_render_closed" "Fetching closed PRs..."
}
