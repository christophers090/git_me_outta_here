# prs web mode - open GitHub PR in browser
# shellcheck shell=bash

run_web() {
    local topic="$1"
    require_topic "web" "$topic" || return 1

    local pr_json
    pr_json=$(find_pr "$topic" "all" "number,title,url")

    if ! pr_exists "$pr_json"; then
        pr_not_found "$topic"
        return 1
    fi

    local number title url
    number=$(pr_field "$pr_json" "number")
    title=$(pr_field "$pr_json" "title")
    url=$(pr_field "$pr_json" "url")

    echo -e "${BOLD}Opening PR #${number}:${NC} ${title}"
    echo -e "  ${CYAN}${url}${NC}"

    open_url "$url"
}
