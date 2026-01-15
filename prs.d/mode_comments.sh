# prs comments mode - show PR review comments
# shellcheck shell=bash

# Get resolution status for all review threads
# Returns JSON map of root_comment_id -> isResolved
get_thread_resolution_status() {
    local pr_number="$1"

    local graphql_query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          reviewThreads(first: 100) {
            nodes {
              isResolved
              comments(first: 1) {
                nodes { databaseId }
              }
            }
          }
        }
      }
    }'

    gh api graphql \
        -f query="$graphql_query" \
        -f owner="$REPO_OWNER" \
        -f repo="$REPO_NAME" \
        -F number="$pr_number" 2>/dev/null \
    | jq '[.data.repository.pullRequest.reviewThreads.nodes[] |
          {key: (.comments.nodes[0].databaseId | tostring), value: .isResolved}] |
          from_entries'
}

run_comments() {
    local topic="$1"
    shift
    local show_resolved=false

    # Parse extra args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --show-resolved) show_resolved=true; shift ;;
            *) shift ;;
        esac
    done

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

    local total_count
    total_count=$(echo "$comments_json" | jq 'length')

    if [[ "$total_count" -eq 0 ]]; then
        echo -e "${DIM}No review comments${NC}"
        return 0
    fi

    # Get thread resolution status
    local resolution_status
    resolution_status=$(get_thread_resolution_status "$number")

    # Build list of resolved root comment IDs
    local resolved_roots
    resolved_roots=$(echo "$resolution_status" | jq -r 'to_entries | map(select(.value == true)) | map(.key) | .[]')

    # Filter comments if not showing resolved
    local filtered_json="$comments_json"
    if [[ "$show_resolved" == "false" ]]; then
        # Filter out resolved root comments and their replies
        filtered_json=$(echo "$comments_json" | jq --argjson resolved "$(echo "$resolution_status" | jq 'to_entries | map(select(.value == true)) | map(.key | tonumber)')" '
            # Get IDs of resolved root comments
            ($resolved) as $resolved_ids |
            # Filter: keep if not a resolved root AND not a reply to a resolved root
            [.[] | select(
                ((.in_reply_to_id == null) and ((.id | IN($resolved_ids[])) | not)) or
                ((.in_reply_to_id != null) and ((.in_reply_to_id | IN($resolved_ids[])) | not))
            )]
        ')
    fi

    local count
    count=$(echo "$filtered_json" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        echo -e "${DIM}No unresolved comments${NC}"
        return 0
    fi

    local header_suffix=""
    if [[ "$show_resolved" == "false" ]]; then
        local resolved_count=$((total_count - count))
        if [[ "$resolved_count" -gt 0 ]]; then
            header_suffix=" ${DIM}(${resolved_count} resolved hidden)${NC}"
        fi
    fi

    echo -e "${BOLD}Review Comments${NC} ${DIM}(${count})${NC}${header_suffix}"
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
    done < <(echo "$filtered_json" | jq -r '.[] | @base64')

    echo ""
}
