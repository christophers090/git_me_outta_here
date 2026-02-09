# prs comment mode helpers - shared logic for comment-related modes
# shellcheck shell=bash

# Find PR and get comment info - shared by all comment modes
# Usage: get_pr_and_comment <topic> <comment_num>
# Sets: PR_NUMBER, COMMENT_ID, ROOT_ID
# Returns: 1 if not found (prints error)
get_pr_and_comment() {
    local topic="$1"
    local comment_num="$2"

    local pr_json
    pr_json=$(cached_find_pr "$topic" "all" "number")

    if ! pr_exists "$pr_json"; then
        pr_not_found "$topic"
        return 1
    fi

    PR_NUMBER=$(pr_field "$pr_json" "number")

    local info
    info=$(get_comment_info "$PR_NUMBER" "$comment_num" "$topic")

    if [[ -z "$info" || "$info" == "null:null" ]]; then
        echo -e "${RED}Error:${NC} Comment #${comment_num} not found"
        return 1
    fi

    COMMENT_ID="${info%%:*}"
    ROOT_ID="${info##*:}"
}

# Start PR lookup in background (for reply modes that need concurrent input)
# Usage: start_pr_lookup_bg <topic> <comment_num> <tmp_file>
# Sets: _BG_LOOKUP_PID (must be waited on by caller)
# The result is written to tmp_file as: number:comment_id:root_id or ERROR:*
_BG_LOOKUP_PID=""
start_pr_lookup_bg() {
    local topic="$1"
    local comment_num="$2"
    local tmp_file="$3"

    (
        local pr_json number info
        pr_json=$(cached_find_pr "$topic" "all" "number")
        if ! pr_exists "$pr_json"; then
            echo "ERROR:PR_NOT_FOUND" > "$tmp_file"
            exit 1
        fi
        number=$(pr_field "$pr_json" "number")
        info=$(get_comment_info "$number" "$comment_num" "$topic")
        if [[ -z "$info" || "$info" == "null:null" ]]; then
            echo "ERROR:COMMENT_NOT_FOUND" > "$tmp_file"
            exit 1
        fi
        echo "${number}:${info}" > "$tmp_file"
    ) </dev/null &
    _BG_LOOKUP_PID=$!
}

# Check background lookup result
# Usage: check_pr_lookup_result <tmp_file> <comment_num>
# Sets: PR_NUMBER, COMMENT_ID, ROOT_ID
# Returns: 1 if error (prints error)
check_pr_lookup_result() {
    local tmp_file="$1"
    local comment_num="$2"

    local lookup_result
    lookup_result=$(cat "$tmp_file")
    rm -f "$tmp_file"

    if [[ "$lookup_result" == "ERROR:PR_NOT_FOUND" ]]; then
        echo -e "${CROSS} No PR found for topic"
        return 1
    elif [[ "$lookup_result" == "ERROR:COMMENT_NOT_FOUND" ]]; then
        echo -e "${CROSS} Comment #${comment_num} not found"
        return 1
    fi

    # Parse: number:comment_id:root_id
    PR_NUMBER="${lookup_result%%:*}"
    local rest="${lookup_result#*:}"
    COMMENT_ID="${rest%%:*}"
    ROOT_ID="${rest##*:}"
}
