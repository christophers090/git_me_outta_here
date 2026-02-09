# prs status mode - detailed PR status
# shellcheck shell=bash

# Fields needed for status display
_STATUS_FIELDS="number,title,state,url,reviewDecision,reviewRequests,reviews,statusCheckRollup,mergeStateStatus,labels,isDraft"

# Module-level state
_STATUS_TOPIC=""

# Fetch PR JSON for a topic
# Two-phase: find PR number cheaply, then fetch heavy fields for just that one PR.
# Before: gh pr list --json <11 heavy fields> for ALL user's PRs (~3.4s)
# After: cache lookup (0ms) or lightweight gh pr list (~1s) + gh pr view (~1s)
_fetch_status() {
    local pr_number=""

    # If topic is already a PR number, use directly
    if [[ "$_STATUS_TOPIC" =~ ^[0-9]+$ ]]; then
        pr_number="$_STATUS_TOPIC"
    else
        # Try to find PR number from outstanding cache (no API call)
        local outstanding
        outstanding=$(cache_get "outstanding")
        if [[ -n "$outstanding" && "$outstanding" != "[]" ]]; then
            pr_number=$(echo "$outstanding" | jq -r --arg topic "$_STATUS_TOPIC" '
                ($topic | gsub("(?<c>[.+*?^${}()|\\[\\]])"; "\\\(.c)")) as $escaped |
                [.[] | select(
                    (.headRefName | endswith("/" + $topic)) or
                    (.body | test("Topic:\\s*" + $escaped + "\\b"))
                )] | .[0].number // empty' 2>/dev/null)
        fi

        # Fall back to lightweight API lookup (just number, no heavy fields)
        if [[ -z "$pr_number" ]]; then
            local lookup
            lookup=$(find_pr "$_STATUS_TOPIC" "all" "number")
            pr_number=$(echo "$lookup" | jq -r '.[0].number // empty' 2>/dev/null)
        fi
    fi

    # Fetch full status data for just this one PR
    if [[ -n "$pr_number" ]]; then
        # Start queue check in parallel
        local queue_tmp
        queue_tmp=$(mktemp)
        (gh api graphql -f query='{
          repository(owner: "'"$REPO_OWNER"'", name: "'"$REPO_NAME"'") {
            mergeQueue(branch: "main") {
              entries(first: 50) {
                nodes {
                  position
                  pullRequest { number }
                }
              }
            }
          }
        }' --jq ".data.repository.mergeQueue.entries.nodes[] | select(.pullRequest.number == ${pr_number}) | .position" > "$queue_tmp" 2>/dev/null) &
        local queue_pid=$!

        local result
        result=$(gh pr view "$pr_number" -R "$REPO" --json "$_STATUS_FIELDS" 2>/dev/null)

        # Collect queue result
        wait "$queue_pid" 2>/dev/null
        local queue_pos
        queue_pos=$(<"$queue_tmp")
        rm -f "$queue_tmp"
        cache_set "queue_pos_${_STATUS_TOPIC}" "${queue_pos:-}"

        if [[ -n "$result" ]]; then
            echo "[$result]"
            return 0
        fi
    fi

    echo "[]"
}

# Check if status data is empty/invalid
_status_is_empty() {
    local data="$1"
    [[ -z "$data" ]] || ! pr_exists "$data"
}

# Early exit hook for yank mode - copies URL and exits
_status_early_exit() {
    [[ "$COPY_TO_CLIPBOARD" != "true" ]] && return 1

    local pr_json
    pr_json=$(cache_get "status_${_STATUS_TOPIC}")
    if [[ -z "$pr_json" ]] || ! pr_exists "$pr_json"; then
        pr_json=$(_fetch_status)
        pr_exists "$pr_json" && cache_set "status_${_STATUS_TOPIC}" "$pr_json"
    fi
    if pr_exists "$pr_json"; then
        copy_pr_to_clipboard "$pr_json"
        return 0
    else
        pr_not_found "$_STATUS_TOPIC"
        return 0  # Still exit early, but with error shown
    fi
}

# Not-found hook - shows similar topics or lists all PRs
_status_not_found() {
    pr_not_found "$_STATUS_TOPIC"
    echo ""

    # Try to find similar topics from cache only (no extra API call)
    local similar=""
    local outstanding_data
    outstanding_data=$(cache_get "outstanding")
    if [[ -n "$outstanding_data" ]]; then
        similar=$(echo "$outstanding_data" | jq -r --arg topic "$_STATUS_TOPIC" '.[] | select(.headRefName | ascii_downcase | contains($topic | ascii_downcase)) | (.headRefName | split("/") | last) as $t | "  \($t) - #\(.number): \(.title)"' 2>/dev/null || true)
    fi

    if [[ -n "$similar" ]]; then
        echo -e "${YELLOW}Similar topics:${NC}"
        echo "$similar"
    fi
}

# Fetch and cache extra status data (comments + automerge) after getting PR JSON
# Runs in background and detached - completes after prs exits, results cached for next run
_post_cache_status() {
    local pr_json="$1"
    local topic="$_STATUS_TOPIC"
    (
        local pr_number comments automerge
        pr_number=$(echo "$pr_json" | jq -r '.[0].number')
        comments=$(get_unresolved_count "$pr_number")
        automerge=$(gh api "repos/${REPO}/pulls/${pr_number}" --jq '.auto_merge != null' 2>/dev/null || echo "false")

        cache_set "comments_${topic}" "$comments"
        cache_set "automerge_${topic}" "$automerge"
    ) &>/dev/null &
    disown  # Detach from shell so cleanup trap doesn't kill it
}

# Render status from PR JSON
# Reads comments/automerge from cache (set by _post_cache_status or from previous runs)
_render_status() {
    local pr_json="$1"

    if ! pr_exists "$pr_json"; then
        return 1
    fi

    # Read cached extras (may be empty on first render before post_cache runs)
    local cached_comment_count cached_auto_merge cached_queue_pos
    cached_comment_count=$(cache_get "comments_${_STATUS_TOPIC}")
    cached_auto_merge=$(cache_get "automerge_${_STATUS_TOPIC}")
    cached_queue_pos=$(cache_get "queue_pos_${_STATUS_TOPIC}")

    # Extract ALL data in ONE jq call - output as newline-separated for read
    local number title state url review_decision merge_state is_draft auto_merge buildkite_url
    local ci_passed ci_failed ci_pending ci_total ci_failed_names ci_pending_names
    local pending_reviewers approvers change_requesters merge_label

    {
        read -r number
        read -r title
        read -r state
        read -r url
        read -r review_decision
        read -r merge_state
        read -r is_draft
        read -r auto_merge
        read -r buildkite_url
        read -r ci_passed
        read -r ci_failed
        read -r ci_pending
        read -r ci_total
        IFS= read -r -d $'\x1e' ci_failed_names
        read -r  # consume trailing newline after \x1e
        IFS= read -r -d $'\x1e' ci_pending_names
        read -r  # consume trailing newline after \x1e
        read -r pending_reviewers
        read -r approvers
        read -r change_requesters
        read -r merge_label
    } < <(echo "$pr_json" | jq -r --arg ci_ctx "$CI_CHECK_CONTEXT" '.[0] |
        .number,
        .title,
        .state,
        .url,
        (.reviewDecision // "NONE"),
        (.mergeStateStatus // "UNKNOWN"),
        .isDraft,
        "",
        (((.statusCheckRollup // [])[] | select(.context == $ci_ctx) | .targetUrl) // ""),
        ([(.statusCheckRollup // [])[] | select(.state == "SUCCESS")] | length),
        ([(.statusCheckRollup // [])[] | select(.state == "FAILURE" or .state == "ERROR")] | length),
        ([(.statusCheckRollup // [])[] | select(.state == "PENDING" or .state == "EXPECTED")] | length),
        ((.statusCheckRollup // []) | length),
        (([(.statusCheckRollup // [])[] | select(.state == "FAILURE" or .state == "ERROR") | "    \(.context // .name)"] | join("\n")) + "\u001e"),
        (([(.statusCheckRollup // [])[] | select(.state == "PENDING" or .state == "EXPECTED") | "    \(.context // .name)"] | join("\n")) + "\u001e"),
        ([(.reviewRequests // [])[] | if .name then "@\(.slug // .name)" else "@\(.login)" end] | join(", ")),
        ([(.reviews // []) | group_by(.author.login)[] | sort_by(.submittedAt) | last] | [.[] | select(.state == "APPROVED") | "@\(.author.login)"] | join(", ")),
        ([(.reviews // []) | group_by(.author.login)[] | sort_by(.submittedAt) | last] | [.[] | select(.state == "CHANGES_REQUESTED") | "@\(.author.login)"] | join(", ")),
        (((.labels // [])[] | select(.name | ascii_downcase | contains("merge")) | .name) // "")
    ')

    # Header
    echo -e "${BOLD}${BLUE}PR #${number}:${NC} ${title}"
    echo -e "URL: ${CYAN}${url}${NC}"
    if [[ -n "$buildkite_url" ]]; then
        echo -e "CI:  ${CYAN}${buildkite_url}${NC}"
    fi
    echo -e "State: ${state}$(if [[ "$is_draft" == "true" ]]; then echo -e " ${YELLOW}(Draft)${NC}"; fi)"
    echo ""

    # CI Status section
    echo -e "${BOLD}CI Status:${NC}"
    if [[ "$ci_total" -eq 0 ]]; then
        echo "  No CI checks found"
    elif [[ "$ci_failed" -gt 0 ]]; then
        echo -e "  ${RED}${ci_failed} failed${NC}, ${GREEN}${ci_passed} passed${NC}, ${YELLOW}${ci_pending} pending${NC} (${ci_total} total)"
        echo ""
        echo -e "  ${RED}Failed:${NC}"
        echo "$ci_failed_names" | sed 's/^/    /'
    elif [[ "$ci_pending" -gt 0 ]]; then
        echo -e "  ${GREEN}${ci_passed} passed${NC}, ${YELLOW}${ci_pending} pending${NC} (${ci_total} total)"
        echo ""
        echo -e "  ${YELLOW}Pending:${NC}"
        echo "$ci_pending_names" | sed 's/^/    /'
    else
        echo -e "  ${GREEN}All ${ci_passed} checks passed${NC}"
    fi

    # Submodule PR line (if configured and not in submodule mode)
    if [[ -n "$SUBMODULE_REPO" && "$SUBMODULE_MODE" != "true" ]]; then
        local sub_json sub_review_sym
        sub_json=$(cache_get "sub_outstanding")
        if [[ -n "$sub_json" && "$sub_json" != "[]" ]]; then
            local sub_info
            sub_info=$(echo "$sub_json" | jq -r --arg topic "$_STATUS_TOPIC" '
                .[] |
                ((.body | capture("Topic:\\s*(?<t>\\S+)") | .t) // (.headRefName | split("/") | last)) as $t |
                select($t == $topic) |
                "\(.number)|\(.url)|\(.reviewDecision == "APPROVED")"' | head -1)
            if [[ -n "$sub_info" ]]; then
                local s_number s_url s_review_ok
                IFS='|' read -r s_number s_url s_review_ok <<< "$sub_info"
                sub_review_sym="$CROSS"
                [[ "$s_review_ok" == "true" ]] && sub_review_sym="$CHECK"
                local sub_link="\e]8;;${s_url}\a${CYAN}#${s_number}${NC}\e]8;;\a"
                echo -e "  Sub ${sub_link}: Reviews ${sub_review_sym}"
            fi
        fi
    fi
    echo ""

    # Reviews section
    echo -e "${BOLD}Reviews:${NC}"

    # Derive effective review status when GitHub's reviewDecision is empty/NONE
    # (can happen when PR has approvals but also unresolved comments)
    local effective_status="$review_decision"
    if [[ -z "$effective_status" || "$effective_status" == "NONE" ]]; then
        if [[ -n "$change_requesters" ]]; then
            effective_status="CHANGES_REQUESTED"
        elif [[ -n "$approvers" ]]; then
            effective_status="APPROVED"
        fi
    fi

    case "$effective_status" in
        "APPROVED")
            echo -e "  Status: ${GREEN}APPROVED${NC}"
            ;;
        "CHANGES_REQUESTED")
            echo -e "  Status: ${RED}CHANGES REQUESTED${NC}"
            ;;
        "REVIEW_REQUIRED")
            echo -e "  Status: ${YELLOW}REVIEW REQUIRED${NC}"
            ;;
        *)
            echo -e "  Status: ${effective_status:-No reviews}"
            ;;
    esac

    if [[ -n "$pending_reviewers" ]]; then
        echo -e "  Pending: ${YELLOW}${pending_reviewers}${NC}"
    fi
    # Only show approvers when PR is approved (hides stale approvals from before latest push)
    if [[ -n "$approvers" && "$effective_status" == "APPROVED" ]]; then
        echo -e "  Approved by: ${GREEN}${approvers}${NC}"
    fi
    # Only show change requesters when that's the actual current state
    if [[ -n "$change_requesters" && "$effective_status" == "CHANGES_REQUESTED" ]]; then
        echo -e "  Changes requested by: ${RED}${change_requesters}${NC}"
    fi

    # Show unresolved comments (use cached if available, otherwise placeholder until refresh)
    local unresolved_count
    if [[ -n "$cached_comment_count" ]]; then
        unresolved_count="$cached_comment_count"
        if [[ "$unresolved_count" -gt 0 ]]; then
            echo -e "  Unresolved comments: ${YELLOW}${unresolved_count}${NC}"
        else
            echo -e "  Unresolved comments: ${GREEN}0${NC}"
        fi
    else
        echo -e "  Unresolved comments: ${DIM}...${NC}"
    fi
    echo ""

    # Merge Status section
    echo -e "${BOLD}Merge Status:${NC}"
    case "$merge_state" in
        "CLEAN")
            if [[ -n "$cached_queue_pos" ]]; then
                echo -e "  State: ${GREEN}In merge queue${NC} (position #${cached_queue_pos})"
            else
                echo -e "  State: ${GREEN}Ready to merge${NC}"
            fi
            ;;
        "BLOCKED")
            echo -e "  State: ${RED}BLOCKED${NC}"
            ;;
        "BEHIND")
            echo -e "  State: ${YELLOW}Behind base branch${NC}"
            ;;
        "UNSTABLE")
            echo -e "  State: ${YELLOW}Unstable (some checks failing)${NC}"
            ;;
        "HAS_HOOKS")
            echo -e "  State: ${YELLOW}Waiting for merge hooks${NC}"
            ;;
        *)
            echo -e "  State: ${merge_state}"
            ;;
    esac
    # Use cached auto-merge status
    # Values: "true", "false", or empty (unknown/not yet fetched)
    local auto_merge_status
    case "$cached_auto_merge" in
        "true")  auto_merge_status="${GREEN}Enabled${NC}" ;;
        "false") auto_merge_status="Disabled" ;;
        *)       auto_merge_status="${DIM}...${NC}" ;;  # Will be fetched with fresh data
    esac
    echo -e "  Merge-when-ready: ${auto_merge_status}"
    if [[ -n "$merge_label" ]]; then
        echo -e "  Label: ${CYAN}${merge_label}${NC}"
    fi
}

# Show all open PRs when no topic given
_show_all_prs() {
    echo -e "${BOLD}Your open PRs:${NC}"
    gh pr list -R "$REPO" --author "$GITHUB_USER" --state open
}

run_status() {
    local topic="$1"

    # No topic: list all open PRs
    if [[ -z "$topic" ]]; then
        _show_all_prs
        return 0
    fi

    # Set up module state and hooks
    _STATUS_TOPIC="$topic"
    DISPLAY_EARLY_EXIT_FN="_status_early_exit"
    DISPLAY_NOT_FOUND_FN="_status_not_found"

    display_with_refresh \
        "status_${topic}" \
        "_fetch_status" \
        "_render_status" \
        "Fetching PR..." \
        "_post_cache_status" \
        "_status_is_empty"
    local result=$?

    # Clean up hooks
    DISPLAY_EARLY_EXIT_FN=""
    DISPLAY_NOT_FOUND_FN=""

    return $result
}
