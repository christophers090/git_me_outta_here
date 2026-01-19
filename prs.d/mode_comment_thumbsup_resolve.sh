# prs comment_thumbsup_resolve mode - thumbs up and resolve a PR review comment
# shellcheck shell=bash

run_comment_thumbsup_resolve() {
    local topic="$1"
    local comment_num="${2:-}"

    require_topic "comment_thumbsup_resolve" "$topic" || return 1
    require_comment_num "$comment_num" "-ctx" || return 1

    get_pr_and_comment "$topic" "$comment_num" || return 1
    thumbsup_comment "$COMMENT_ID" "$comment_num" || return 1
    resolve_thread "$PR_NUMBER" "$ROOT_ID" "$comment_num"
}
