# prs review_approve mode - approve a PR
# shellcheck shell=bash

run_review_approve() {
    local topic="$1"

    require_topic "review_approve" "$topic" "-pa" || return 1

    # Show prompt immediately, start PR lookup in background
    echo -e "${BOLD}Approve PR${NC}"
    echo -e "${DIM}Enter optional comment (Ctrl+D twice when done, or just Ctrl+D to skip):${NC}"

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
        printf '%s\x1e%s' "$number" "$title" > "$tmp_file"
    ) </dev/null &
    local bg_pid=$!

    # Collect body while lookup happens
    local body
    body=$(cat)
    echo ""

    # Wait for lookup to complete (|| true: exit status checked below)
    wait "$bg_pid" || true

    # Check lookup result
    local lookup_result
    lookup_result=$(cat "$tmp_file")
    rm -f "$tmp_file"

    if [[ "$lookup_result" == "ERROR:PR_NOT_FOUND" ]]; then
        pr_not_found "$topic"
        return 1
    fi

    local pr_number pr_title
    IFS=$'\x1e' read -r pr_number pr_title <<< "$lookup_result"

    # Submit approval
    local cmd=(gh pr review "$pr_number" -R "$REPO" --approve)
    if [[ -n "$body" ]]; then
        cmd+=(-b "$body")
    fi

    if "${cmd[@]}" 2>/dev/null; then
        echo -e "${CHECK} Approved PR #${pr_number}: ${pr_title}"
    else
        echo -e "${CROSS} Failed to approve PR #${pr_number}"
        return 1
    fi
}
