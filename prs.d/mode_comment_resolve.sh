# prs comment_resolve mode - resolve a PR review thread
# shellcheck shell=bash

run_comment_resolve() {
    local topic="$1"
    local comment_num="${2:-}"

    require_topic "comment_resolve" "$topic" || return 1

    if [[ -z "$comment_num" ]]; then
        echo -e "${RED}Error:${NC} Comment number required"
        echo "Usage: prs -cx <topic> <comment_num>"
        return 1
    fi

    local pr_json
    pr_json=$(cached_find_pr "$topic" "all" "number")

    if ! pr_exists "$pr_json"; then
        pr_not_found "$topic"
        return 1
    fi

    local number
    number=$(pr_field "$pr_json" "number")

    local info
    info=$(get_comment_info "$number" "$comment_num" "$topic")

    if [[ -z "$info" || "$info" == "null:null" ]]; then
        echo -e "${RED}Error:${NC} Comment #${comment_num} not found"
        return 1
    fi

    local root_id="${info##*:}"
    resolve_thread "$number" "$root_id" "$comment_num"
}
