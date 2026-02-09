# prs comment_resolve mode - resolve a PR review thread
# shellcheck shell=bash

run_comment_resolve() {
    local topic="$1"
    local comment_num="${2:-}"

    require_topic "comment_resolve" "$topic" "-cx" || return 1
    require_comment_num "$comment_num" "-cx" || return 1

    get_pr_and_comment "$topic" "$comment_num" || return 1
    resolve_thread "$PR_NUMBER" "$ROOT_ID" "$comment_num"
}
