# prs comment_thumbsup mode - add thumbs up reaction to a PR review comment
# shellcheck shell=bash

run_comment_thumbsup() {
    local topic="$1"
    local comment_num="${2:-}"

    require_topic "comment_thumbsup" "$topic" || return 1

    if [[ -z "$comment_num" ]]; then
        echo -e "${RED}Error:${NC} Comment number required"
        echo "Usage: prs -ct <topic> <comment_num>"
        return 1
    fi

    local pr_json
    pr_json=$(find_pr "$topic" "all" "number")

    if ! pr_exists "$pr_json"; then
        pr_not_found "$topic"
        return 1
    fi

    local number
    number=$(pr_field "$pr_json" "number")

    local info
    info=$(get_comment_info "$number" "$comment_num")

    if [[ -z "$info" || "$info" == "null:null" ]]; then
        echo -e "${RED}Error:${NC} Comment #${comment_num} not found"
        return 1
    fi

    local comment_id="${info%%:*}"
    thumbsup_comment "$comment_id" "$comment_num"
}
