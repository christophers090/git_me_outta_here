# prs comment_reply_resolve mode - reply to and resolve a PR review comment
# shellcheck shell=bash

run_comment_reply_resolve() {
    local topic="$1"
    local comment_num="${2:-}"

    require_topic "comment_reply_resolve" "$topic" "-crx" || return 1
    require_comment_num "$comment_num" "-crx" || return 1

    # Show prompt immediately, do lookups in background
    echo -e "${BOLD}Reply to comment #${comment_num}${NC}"
    echo -e "${DIM}Enter your reply (Ctrl+D twice when done):${NC}"

    # Start PR lookup in background
    local tmp_file
    tmp_file=$(mktemp)
    start_pr_lookup_bg "$topic" "$comment_num" "$tmp_file"

    # Collect reply while lookup happens
    local reply_body
    reply_body=$(cat)
    echo ""  # Ensure newline after input before status messages

    if [[ -z "$reply_body" ]]; then
        kill "$_BG_LOOKUP_PID" 2>/dev/null
        rm -f "$tmp_file"
        echo -e "${RED}Error:${NC} Reply cannot be empty"
        return 1
    fi

    # Wait for lookup to complete (|| true: exit status handled by check_pr_lookup_result)
    wait "$_BG_LOOKUP_PID" || true

    # Check lookup result
    check_pr_lookup_result "$tmp_file" "$comment_num" || return 1

    reply_to_comment "$PR_NUMBER" "$COMMENT_ID" "$comment_num" "$reply_body" || return 1
    resolve_thread "$PR_NUMBER" "$ROOT_ID" "$comment_num"
}
