# prs status mode - detailed PR status
# shellcheck shell=bash

# Fields needed for status display
_STATUS_FIELDS="number,title,state,url,reviewDecision,reviewRequests,reviews,statusCheckRollup,mergeStateStatus,labels,isDraft"

# Fetch PR JSON for a topic (always fresh, bypasses cache)
_fetch_status_json() {
    local topic="$1"
    find_pr "$topic" "all" "$_STATUS_FIELDS"
}

# Render status from PR JSON
# cached_comment_count and cached_auto_merge avoid slow API calls when displaying cached data
_render_status() {
    local pr_json="$1"
    local cached_comment_count="${2:-}"
    local cached_auto_merge="${3:-}"

    if ! pr_exists "$pr_json"; then
        return 1
    fi

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

    # Show unresolved comments (use cached if provided, otherwise fetch)
    local unresolved_count
    if [[ -n "$cached_comment_count" ]]; then
        unresolved_count="$cached_comment_count"
    else
        unresolved_count=$(get_unresolved_count "$number")
    fi
    if [[ "$unresolved_count" -gt 0 ]]; then
        echo -e "  Unresolved comments: ${YELLOW}${unresolved_count}${NC}"
    else
        echo -e "  Unresolved comments: ${GREEN}0${NC}"
    fi
    echo ""

    # Merge Status section
    echo -e "${BOLD}Merge Status:${NC}"
    case "$merge_state" in
        "CLEAN")
            echo -e "  State: ${GREEN}Ready to merge${NC}"
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
    # Use cached auto-merge status (avoids slow API call)
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

run_status() {
    local topic="$1"

    # No topic: list all open PRs (use outstanding cache if available)
    if [[ -z "$topic" ]]; then
        echo -e "${BOLD}Your open PRs:${NC}"
        if cache_is_fresh "outstanding" "$CACHE_TTL_OUTSTANDING"; then
            cache_get "outstanding" | jq -r '.[] | "#\(.number)\t\(.title)\t\(.url)"' | column -t -s $'\t'
        else
            gh pr list -R "$REPO" --author "$GITHUB_USER" --state open
        fi
        return 0
    fi

    # Yank mode: just copy to clipboard and exit
    if [[ "$COPY_TO_CLIPBOARD" == "true" ]]; then
        local cache_key="status_${topic}"
        local pr_json
        pr_json=$(cache_get "$cache_key")
        if [[ -z "$pr_json" ]] || ! pr_exists "$pr_json"; then
            pr_json=$(_fetch_status_json "$topic")
            pr_exists "$pr_json" && cache_set "$cache_key" "$pr_json"
        fi
        if pr_exists "$pr_json"; then
            copy_pr_to_clipboard "$pr_json"
        else
            echo -e "${RED}No PR found for topic:${NC} $topic"
            return 1
        fi
        return 0
    fi

    local cache_key="status_${topic}"
    local comments_cache_key="comments_${topic}"
    local automerge_cache_key="automerge_${topic}"
    local cached_json fresh_json cached_comments cached_automerge

    cached_json=$(cache_get "$cache_key")
    cached_comments=$(cache_get "$comments_cache_key")
    cached_automerge=$(cache_get "$automerge_cache_key")

    # Don't use cached data if PR is already merged (stale cache from different PR)
    local cached_state
    cached_state=$(echo "$cached_json" | jq -r '.[0].state // empty' 2>/dev/null)

    if [[ -n "$cached_json" ]] && pr_exists "$cached_json" && [[ "$cached_state" != "MERGED" ]] && is_interactive; then
        # Have valid cache - render to variable first, count lines, then display
        local cached_output line_count
        cached_output=$(_render_status "$cached_json" "$cached_comments" "$cached_automerge")
        line_count=$(($(echo "$cached_output" | wc -l) + 1))  # +1 for "Refreshing..." line

        # Display cached output
        echo "$cached_output"
        echo -e "${DIM}⟳ Refreshing...${NC}"

        # Fetch fresh data (user sees cached immediately)
        fresh_json=$(_fetch_status_json "$topic")

        if pr_exists "$fresh_json"; then
            # Check if data changed by comparing JSON
            if [[ "$fresh_json" != "$cached_json" ]] || [[ -z "$cached_comments" ]]; then
                cache_set "$cache_key" "$fresh_json"

                local pr_number fresh_comments fresh_automerge
                pr_number=$(echo "$fresh_json" | jq -r '.[0].number')
                fresh_comments=$(get_unresolved_count "$pr_number")
                fresh_automerge=$(gh api "repos/${REPO}/pulls/${pr_number}" --jq '.auto_merge != null' 2>/dev/null || echo "false")
                cache_set "$comments_cache_key" "$fresh_comments"
                cache_set "$automerge_cache_key" "$fresh_automerge"

                # Move cursor up by line_count, clear to end of screen, re-render
                tput cuu "$line_count" 2>/dev/null || true
                tput ed 2>/dev/null || true
                _render_status "$fresh_json" "$fresh_comments" "$fresh_automerge"
                echo -e "${DIM}↻ Updated${NC}"
            else
                # Just update the refreshing line
                tput cuu 1 2>/dev/null || true
                tput el 2>/dev/null || true
                echo -e "${DIM}✓ Up to date${NC}"
            fi
        else
            tput cuu 1 2>/dev/null || true
            tput el 2>/dev/null || true
            echo -e "${DIM}✓ (cached)${NC}"
        fi
    else
        # No cache or non-interactive - fetch with spinner
        if is_interactive; then
            show_spinner "Fetching PR..." &
            local spinner_pid=$!
            fresh_json=$(_fetch_status_json "$topic")
            stop_spinner "$spinner_pid"
        else
            fresh_json=$(_fetch_status_json "$topic")
        fi

        if pr_exists "$fresh_json"; then
            cache_set "$cache_key" "$fresh_json"

            # Fetch comment count and auto-merge status, then cache
            local pr_number fresh_comments fresh_automerge
            pr_number=$(echo "$fresh_json" | jq -r '.[0].number')
            fresh_comments=$(get_unresolved_count "$pr_number")
            fresh_automerge=$(gh api "repos/${REPO}/pulls/${pr_number}" --jq '.auto_merge != null' 2>/dev/null || echo "false")
            cache_set "$comments_cache_key" "$fresh_comments"
            cache_set "$automerge_cache_key" "$fresh_automerge"

            _render_status "$fresh_json" "$fresh_comments" "$fresh_automerge"
        else
            echo -e "${RED}No PR found for topic:${NC} $topic"
            echo ""
            # Try to find similar topics (use outstanding cache if available)
            local similar outstanding_data
            if cache_is_fresh "outstanding" "$CACHE_TTL_OUTSTANDING"; then
                outstanding_data=$(cache_get "outstanding")
            else
                outstanding_data=$(gh pr list -R "$REPO" --author "$GITHUB_USER" --state open --json headRefName,number,title 2>/dev/null)
            fi
            similar=$(echo "$outstanding_data" | jq -r --arg topic "$topic" '.[] | select(.headRefName | ascii_downcase | contains($topic | ascii_downcase)) | (.headRefName | split("/") | last) as $t | "  \($t) - #\(.number): \(.title)"' 2>/dev/null || true)

            if [[ -n "$similar" ]]; then
                echo -e "${YELLOW}Similar topics:${NC}"
                echo "$similar"
            else
                echo -e "${BOLD}Your open PRs:${NC}"
                if [[ -n "$outstanding_data" ]]; then
                    echo "$outstanding_data" | jq -r '.[] | "#\(.number)\t\(.title)\t\(.url)"' | column -t -s $'\t'
                else
                    gh pr list -R "$REPO" --author "$GITHUB_USER" --state open
                fi
            fi
            return 1
        fi
    fi
}
