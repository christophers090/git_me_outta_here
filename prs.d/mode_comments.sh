# prs comments mode - show PR review comments
# shellcheck shell=bash

# Fetch all comments data for a PR (comments + resolution status + pr info)
_fetch_comments_data() {
    local pr_number="$1"
    local pr_title="$2"
    local pr_url="$3"
    local comments_json resolution_status

    comments_json=$(get_ordered_comments "$pr_number")
    resolution_status=$(fetch_thread_resolution_status "$pr_number")

    jq -n \
        --argjson number "$pr_number" \
        --arg title "$pr_title" \
        --arg url "$pr_url" \
        --argjson comments "$comments_json" \
        --argjson resolution "$resolution_status" \
        '{number: $number, title: $title, url: $url, comments: $comments, resolution: $resolution}'
}

# Render comments from cached data
# Args: $1 = data JSON, $2 = show_resolved flag, $3 = include_header (optional, default true)
_render_comments() {
    local data="$1"
    local show_resolved="$2"
    local include_header="${3:-true}"

    # Extract ALL header data in ONE jq call for fast first output
    local number title url total_count
    IFS=$'\t' read -r number title url total_count < <(echo "$data" | jq -r '[.number, .title, .url, (.comments | length)] | @tsv')

    # Print PR header IMMEDIATELY (before heavy processing)
    if [[ "$include_header" == "true" ]]; then
        print_pr_header "$number" "$title" "$url"
        echo ""
    fi

    if [[ "$total_count" -eq 0 ]]; then
        echo -e "${DIM}No review comments${NC}"
        return 0
    fi

    # Now do filtering (heavier processing, but header is already visible)
    local filtered_json count
    if [[ "$show_resolved" == "true" ]]; then
        filtered_json=$(echo "$data" | jq '.comments')
        count="$total_count"
    else
        # Filter out resolved comments - get count and filtered JSON separately
        local filter_result
        filter_result=$(echo "$data" | jq '
            .resolution as $res |
            [$res | to_entries | map(select(.value == true)) | .[].key | tonumber] as $resolved_ids |
            [.comments[] | select(
                ((.in_reply_to_id == null) and ((.id | IN($resolved_ids[])) | not)) or
                (((.in_reply_to_id == null) | not) and ((.in_reply_to_id | IN($resolved_ids[])) | not))
            )]
        ')
        filtered_json="$filter_result"
        count=$(echo "$filter_result" | jq 'length')
    fi

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

    # Display comments - use record separator to handle multi-line bodies
    local comment_num=0
    while IFS=$'\x1e' read -r -d $'\x1f' in_reply_to author created path line body; do
        ((++comment_num))
        if [[ -z "$in_reply_to" || "$in_reply_to" == "null" ]]; then
            # Root comment
            echo -e "${BOLD}#${comment_num}${NC}  ${CYAN}@${author}${NC} ${DIM}${created}${NC}"
            echo -e "    ${YELLOW}${path}${NC}${DIM}:${line}${NC}"
            echo "$body" | sed 's/^/    /'
        else
            # Reply - show indented
            echo ""
            echo -e "    ${DIM}└─${NC} ${BOLD}#${comment_num}${NC}  ${CYAN}@${author}${NC} ${DIM}${created}${NC}"
            echo "$body" | sed 's/^/       /'
        fi
    done < <(echo "$filtered_json" | jq -j '.[] | (([(.in_reply_to_id // ""), .user.login, (.created_at | split("T")[0]), .path, (.line // .original_line // "?")] | join("\u001e")) + "\u001e" + .body + "\u001f")')
}

# Global state for comments mode (set by run_comments, used by wrapper functions)
_COMMENTS_TOPIC=""
_COMMENTS_SHOW_RESOLVED="false"

# Fetch comments for topic - finds PR if needed, then fetches comments
_comments_fetch_for_topic() {
    local pr_json number title url

    # First find the PR to get its info
    pr_json=$(cached_find_pr "$_COMMENTS_TOPIC" "all" "number,title,url")
    if ! pr_exists "$pr_json"; then
        return 1
    fi

    number=$(pr_field "$pr_json" "number")
    title=$(pr_field "$pr_json" "title")
    url=$(pr_field "$pr_json" "url")

    _fetch_comments_data "$number" "$title" "$url"
}

# Render wrapper that uses global show_resolved state
_comments_render() {
    local data="$1"
    _render_comments "$data" "$_COMMENTS_SHOW_RESOLVED" "true"
    echo ""  # Extra blank line for spacing
}

# Post-cache hook: update unresolved count cache
_comments_post_cache() {
    local fresh_data="$1"
    local unresolved_count
    unresolved_count=$(echo "$fresh_data" | jq '[.resolution | to_entries[] | select(.value == false)] | length')
    cache_set "comments_${_COMMENTS_TOPIC}" "$unresolved_count"
}

run_comments() {
    local topic="$1"
    shift

    # Parse extra args
    local show_resolved=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --show-resolved) show_resolved=true; shift ;;
            *) shift ;;
        esac
    done

    require_topic "comments" "$topic" || return 1

    # Set global state for wrapper functions
    _COMMENTS_TOPIC="$topic"
    _COMMENTS_SHOW_RESOLVED="$show_resolved"

    # Use display_with_refresh for the standard cache-then-refresh pattern
    if ! display_with_refresh \
        "comments_data_${topic}" \
        "_comments_fetch_for_topic" \
        "_comments_render" \
        "Fetching comments..." \
        "_comments_post_cache"; then
        # Fetch failed - likely PR not found
        pr_not_found "$topic"
        return 1
    fi
}
