# prs review_request_changes mode - request changes on a PR
# shellcheck shell=bash

run_review_request_changes() {
    local topic="$1"

    require_topic "review_request_changes" "$topic" || return 1

    # Show prompt immediately, start PR lookup in background
    echo -e "${BOLD}Request changes on PR${NC}"
    echo -e "${DIM}Enter your review comment (press Enter, then Ctrl+D when done):${NC}"

    # Start PR lookup in background
    local tmp_file
    tmp_file=$(mktemp)
    (
        local pr_json
        pr_json=$(cached_find_pr "$topic" "all" "number,title")
        if ! pr_exists "$pr_json"; then
            echo "ERROR:PR_NOT_FOUND" > "$tmp_file"
            exit 1
        fi
        local number title
        number=$(pr_field "$pr_json" "number")
        title=$(pr_field "$pr_json" "title")
        echo "${number}:${title}" > "$tmp_file"
    ) &
    local bg_pid=$!

    # Collect body while lookup happens
    local body
    body=$(cat)
    echo ""

    if [[ -z "$body" ]]; then
        kill "$bg_pid" 2>/dev/null
        rm -f "$tmp_file"
        echo -e "${RED}Error:${NC} Review comment cannot be empty"
        return 1
    fi

    # Wait for lookup to complete
    wait "$bg_pid"

    # Check lookup result
    local lookup_result
    lookup_result=$(cat "$tmp_file")
    rm -f "$tmp_file"

    if [[ "$lookup_result" == "ERROR:PR_NOT_FOUND" ]]; then
        pr_not_found "$topic"
        return 1
    fi

    local pr_number="${lookup_result%%:*}"
    local pr_title="${lookup_result#*:}"

    # Submit request-changes review
    if gh pr review "$pr_number" -R "$REPO" --request-changes -b "$body" 2>/dev/null; then
        echo -e "${CHECK} Requested changes on PR #${pr_number}: ${pr_title}"
    else
        echo -e "${CROSS} Failed to request changes on PR #${pr_number}"
        return 1
    fi
}
