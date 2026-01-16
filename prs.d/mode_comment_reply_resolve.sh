# prs comment_reply_resolve mode - reply to and resolve a PR review comment
# shellcheck shell=bash

run_comment_reply_resolve() {
    local topic="$1"
    local comment_num="${2:-}"

    require_topic "comment_reply_resolve" "$topic" || return 1

    if [[ -z "$comment_num" ]]; then
        echo -e "${RED}Error:${NC} Comment number required"
        echo "Usage: prs -crx <topic> <comment_num>"
        return 1
    fi

    # Show prompt immediately, do lookups in background
    echo -e "${BOLD}Reply to comment #${comment_num}${NC}"
    echo -e "${DIM}Enter your reply (Ctrl+D when done):${NC}"

    # Start PR lookup in background
    local tmp_file
    tmp_file=$(mktemp)
    (
        pr_json=$(cached_find_pr "$topic" "all" "number")
        if ! pr_exists "$pr_json"; then
            echo "ERROR:PR_NOT_FOUND" > "$tmp_file"
            exit 1
        fi
        number=$(pr_field "$pr_json" "number")
        info=$(get_comment_info "$number" "$comment_num")
        if [[ -z "$info" || "$info" == "null:null" ]]; then
            echo "ERROR:COMMENT_NOT_FOUND" > "$tmp_file"
            exit 1
        fi
        echo "${number}:${info}" > "$tmp_file"
    ) &
    local bg_pid=$!

    # Collect reply while lookup happens
    local reply_body
    reply_body=$(cat)

    if [[ -z "$reply_body" ]]; then
        kill "$bg_pid" 2>/dev/null
        rm -f "$tmp_file"
        echo -e "${RED}Error:${NC} Reply cannot be empty"
        return 1
    fi

    # Wait for lookup to complete
    wait "$bg_pid"

    # Check lookup result
    local lookup_result
    lookup_result=$(cat "$tmp_file")
    rm -f "$tmp_file"

    if [[ "$lookup_result" == "ERROR:PR_NOT_FOUND" ]]; then
        echo -e "${CROSS} No PR found for topic: ${topic}"
        return 1
    elif [[ "$lookup_result" == "ERROR:COMMENT_NOT_FOUND" ]]; then
        echo -e "${CROSS} Comment #${comment_num} not found"
        return 1
    fi

    # Parse: number:comment_id:root_id
    local number comment_id root_id
    number="${lookup_result%%:*}"
    local rest="${lookup_result#*:}"
    comment_id="${rest%%:*}"
    root_id="${rest##*:}"

    reply_to_comment "$number" "$comment_id" "$comment_num" "$reply_body" || return 1
    resolve_thread "$number" "$root_id" "$comment_num"
}
