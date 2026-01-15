# prs comments mode - show PR review comments
# shellcheck shell=bash

run_comments() {
    local topic="$1"

    require_topic "comments" "$topic" || return 1

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

    print_pr_header "$number" "$title" "$url"
    echo ""

    # Fetch review comments (inline code comments)
    local comments_json
    comments_json=$(gh api "repos/${REPO}/pulls/${number}/comments" 2>/dev/null)

    local count
    count=$(echo "$comments_json" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        echo -e "${DIM}No review comments${NC}"
        return 0
    fi

    echo -e "${BOLD}Review Comments${NC} ${DIM}(${count})${NC}"
    echo ""

    # Process and display each comment
    echo "$comments_json" | jq -r '.[] | @base64' | while read -r encoded; do
        local comment author created path line body

        comment=$(echo "$encoded" | base64 -d)
        author=$(echo "$comment" | jq -r '.user.login')
        created=$(echo "$comment" | jq -r '.created_at | split("T")[0]')
        path=$(echo "$comment" | jq -r '.path')
        line=$(echo "$comment" | jq -r '.line // .original_line // "?"')
        body=$(echo "$comment" | jq -r '.body')

        # Comment header: author and date
        echo -e "${BOLD}${CYAN}@${author}${NC} ${DIM}${created}${NC}"

        # File location
        echo -e "${YELLOW}${path}${NC}${DIM}:${line}${NC}"

        # Comment body with indent
        echo "$body" | sed 's/^/  /'

        echo ""
    done
}
