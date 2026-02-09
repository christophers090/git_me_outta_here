# prs comment_thumbsup mode - add thumbs up reaction to a PR review comment
# shellcheck shell=bash

run_comment_thumbsup() {
    local topic="$1"
    local comment_num="${2:-}"

    require_topic "comment_thumbsup" "$topic" "-ct" || return 1
    require_comment_num "$comment_num" "-ct" || return 1

    get_pr_and_comment "$topic" "$comment_num" || return 1
    thumbsup_comment "$COMMENT_ID" "$comment_num"
}
