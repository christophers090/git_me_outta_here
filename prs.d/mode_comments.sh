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

    local comments_json
    comments_json=$(get_ordered_comments "$number")

    local count
    count=$(echo "$comments_json" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        echo -e "${DIM}No review comments${NC}"
        return 0
    fi

    echo -e "${BOLD}Review Comments${NC} ${DIM}(${count})${NC}"
    echo ""

    # Display comments with threading
    local comment_num=0 prev_root_id=""
    while read -r encoded; do
        ((++comment_num))
        local comment id in_reply_to author created path line body

        comment=$(echo "$encoded" | base64 -d)
        id=$(echo "$comment" | jq -r '.id')
        in_reply_to=$(echo "$comment" | jq -r '.in_reply_to_id // empty')
        author=$(echo "$comment" | jq -r '.user.login')
        created=$(echo "$comment" | jq -r '.created_at | split("T")[0]')
        path=$(echo "$comment" | jq -r '.path')
        line=$(echo "$comment" | jq -r '.line // .original_line // "?"')
        body=$(echo "$comment" | jq -r '.body')

        if [[ -z "$in_reply_to" ]]; then
            # Root comment
            echo -e "${BOLD}#${comment_num}${NC}  ${CYAN}@${author}${NC} ${DIM}${created}${NC}"
            echo -e "    ${YELLOW}${path}${NC}${DIM}:${line}${NC}"
            echo "$body" | sed 's/^/    /'
            prev_root_id="$id"
        else
            # Reply - show indented
            echo ""
            echo -e "    ${DIM}└─${NC} ${BOLD}#${comment_num}${NC}  ${CYAN}@${author}${NC} ${DIM}${created}${NC}"
            echo "$body" | sed 's/^/       /'
        fi
    done < <(echo "$comments_json" | jq -r '.[] | @base64')

    echo ""
}
