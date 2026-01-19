# prs outstanding mode - list all outstanding PRs with chain detection
# shellcheck shell=bash

# Fetch all open PRs JSON from GitHub API
_fetch_outstanding_json() {
    gh pr list -R "$REPO" --author "$GITHUB_USER" --state open \
        --json number,title,url,body,headRefName,reviewDecision,statusCheckRollup 2>/dev/null || echo "[]"
}

# Render outstanding PRs from JSON
# Args: $1=prs_json, $2=filter_topic (optional), $3=filter_topics_str (space-separated, optional)
_render_outstanding() {
    local prs_json="$1"
    local filter_topic="${2:-}"
    local filter_topics_str="${3:-}"
    local -a filter_topics=()

    # Convert filter_topics_str to array if provided
    if [[ -n "$filter_topics_str" ]]; then
        read -ra filter_topics <<< "$filter_topics_str"
    fi

    if [[ "$(echo "$prs_json" | jq 'length')" -eq 0 ]]; then
        echo "No open PRs found for $GITHUB_USER"
        return 0
    fi

    # Parse PRs into structured data
    local parsed ci_context_pattern
    ci_context_pattern="${CI_CHECK_CONTEXT:-buildkite/}"
    parsed=$(echo "$prs_json" | jq -r --arg ci "$ci_context_pattern" '
      .[] |
      ((.body | capture("Topic:\\s*(?<t>\\S+)") | .t) // (.headRefName | split("/") | last)) as $topic |
      ((.body | capture("Relative:\\s*(?<r>\\S+)") | .r) // "") as $relative |
      ([.statusCheckRollup[] | select(.context | startswith($ci))] |
        if length == 0 then "pass"
        elif ([.[] | select(.state == "FAILURE" or .state == "ERROR")] | length > 0) then "fail"
        elif ([.[] | select(.state == "PENDING")] | length > 0) then "pending"
        else "pass"
        end) as $ci_status |
      (.reviewDecision == "APPROVED") as $review_ok |
      "\(.number)|\(.title)|\(.url)|\($topic)|\($relative)|\($ci_status)|\($review_ok)"
    ')

    # Build associative arrays for chain tracking
    declare -A pr_data pr_relative pr_children
    declare -a all_topics

    while IFS='|' read -r number title url topic relative ci_status review_ok; do
        [[ -z "$topic" || "$topic" == "null" ]] && continue
        pr_data["$topic"]="$number|$title|$url|$ci_status|$review_ok"
        pr_relative["$topic"]="$relative"
        all_topics+=("$topic")

        if [[ -n "$relative" && "$relative" != "main" ]]; then
            pr_children["$relative"]+="$topic "
        fi
    done <<< "$parsed"

    # Find chain roots (PRs with no open parent)
    declare -a roots standalone
    for topic in "${all_topics[@]}"; do
        local relative="${pr_relative[$topic]:-}"
        local has_children="${pr_children[$topic]:-}"
        local parent_is_open=""
        [[ -n "$relative" && "$relative" != "main" ]] && parent_is_open="${pr_data[$relative]:-}"

        if [[ -z "$relative" || "$relative" == "main" ]]; then
            if [[ -n "$has_children" ]]; then
                roots+=("$topic")
            else
                standalone+=("$topic")
            fi
        elif [[ -z "$parent_is_open" ]]; then
            if [[ -n "$has_children" ]]; then
                roots+=("$topic")
            else
                standalone+=("$topic")
            fi
        fi
    done

    # Helper: Find root of chain containing topic
    _find_chain_root() {
        local topic="$1"
        local relative="${pr_relative[$topic]:-}"
        if [[ -z "$relative" || "$relative" == "main" || -z "${pr_data[$relative]:-}" ]]; then
            echo "$topic"
        else
            _find_chain_root "$relative"
        fi
    }

    # Helper: Get chain order string (topic -> child -> grandchild)
    _get_chain_order() {
        local topic="$1"
        local result="$topic"
        local children="${pr_children[$topic]:-}"
        if [[ -n "$children" ]]; then
            local child_array=($children)
            for child in "${child_array[@]}"; do
                result="$result -> $(_get_chain_order "$child")"
            done
        fi
        echo "$result"
    }

    # Helper: Print single PR
    _print_pr() {
        local topic="$1"
        local prefix="$2"
        local data="${pr_data[$topic]}"
        local relative="${pr_relative[$topic]}"
        local number title url ci_status review_ok

        IFS='|' read -r number title url ci_status review_ok <<< "$data"

        local ci_sym="$CROSS"
        local review_sym="$CROSS"
        [[ "$ci_status" == "pass" ]] && ci_sym="$CHECK"
        [[ "$ci_status" == "pending" ]] && ci_sym="${YELLOW}●${NC}"
        [[ "$review_ok" == "true" ]] && review_sym="$CHECK"

        # Hyperlink the PR number (OSC 8 escape sequence with BEL terminator)
        local pr_link="\e]8;;${url}\a${BLUE}#${number}${NC}\e]8;;\a"

        echo -e "${prefix}${BOLD}${pr_link}:${NC} ${title}"
        echo -e "${prefix}    CI ${ci_sym} | Reviews ${review_sym}"
        echo -e "${prefix}    ${DIM}Topic:${NC} ${topic}"
        if [[ -n "$relative" && "$relative" != "main" ]]; then
            echo -e "${prefix}    ${DIM}Relative:${NC} ${relative}"
        else
            echo -e "${prefix}    ${DIM}Relative:${NC} (none)"
        fi
    }

    # Helper: Print chain recursively
    _print_chain() {
        local topic="$1"
        local prefix="$2"

        _print_pr "$topic" "$prefix"
        echo ""

        local children="${pr_children[$topic]:-}"
        if [[ -n "$children" ]]; then
            local child_array=($children)
            for child in "${child_array[@]}"; do
                _print_chain "$child" "$prefix"
            done
        fi
    }

    # If filter_topics provided (from "this" mode)
    if [[ ${#filter_topics[@]} -gt 0 ]]; then
        echo -e "${BOLD}Topics in current branch:${NC} ${filter_topics[*]}"
        echo ""

        declare -A shown_roots
        for topic in "${filter_topics[@]}"; do
            if [[ -n "${pr_data[$topic]:-}" ]]; then
                local root
                root=$(_find_chain_root "$topic")
                if [[ -z "${shown_roots[$root]:-}" ]]; then
                    shown_roots[$root]=1
                    local chain_order
                    chain_order=$(_get_chain_order "$root")
                    echo -e "${BOLD}────────────────────────────────────────────────────────${NC}"
                    echo -e "${DIM}${chain_order}${NC}"
                    echo -e "${BOLD}────────────────────────────────────────────────────────${NC}"
                    echo ""
                    _print_chain "$root" "  "
                    echo ""
                fi
            else
                echo -e "${YELLOW}Topic not found as open PR:${NC} $topic"
            fi
        done
        return 0
    fi

    # If single filter topic specified
    if [[ -n "$filter_topic" ]]; then
        if [[ -z "${pr_data[$filter_topic]:-}" ]]; then
            echo -e "${RED}Topic not found:${NC} $filter_topic"
            echo ""
            echo "Available topics:"
            for t in "${all_topics[@]}"; do
                echo "  $t"
            done
            return 1
        fi

        local filter_root chain_order
        filter_root=$(_find_chain_root "$filter_topic")
        chain_order=$(_get_chain_order "$filter_root")
        echo -e "${BOLD}────────────────────────────────────────────────────────${NC}"
        echo -e "${DIM}${chain_order}${NC}"
        echo -e "${BOLD}────────────────────────────────────────────────────────${NC}"
        echo ""
        _print_chain "$filter_root" "  "
        return 0
    fi

    # Print all chains
    for root in "${roots[@]}"; do
        local chain_order
        chain_order=$(_get_chain_order "$root")
        echo -e "${BOLD}────────────────────────────────────────────────────────${NC}"
        echo -e "${DIM}${chain_order}${NC}"
        echo -e "${BOLD}────────────────────────────────────────────────────────${NC}"
        echo ""
        _print_chain "$root" "  "
        echo ""
        echo ""
    done

    # Print standalone PRs (no chain)
    for topic in "${standalone[@]}"; do
        _print_pr "$topic" ""
        echo ""
    done
}

run_outstanding() {
    local filter_topic="$1"
    local filter_topics=()
    local filter_topics_str=""

    # Handle "this" - show PRs for current worktree's topics
    if [[ "$filter_topic" == "this" ]]; then
        if ! git rev-parse --git-dir &>/dev/null; then
            echo -e "${RED}Not in a git repository${NC}"
            return 1
        fi

        mapfile -t filter_topics < <(get_branch_topics)

        local current_branch
        current_branch=$(git branch --show-current)
        if [[ ${#filter_topics[@]} -eq 0 ]]; then
            echo -e "${YELLOW}No revup topics found in current branch${NC}"
            echo -e "Branch: ${CYAN}${current_branch}${NC}"
            return 0
        fi
        echo -e "${DIM}Branch: ${current_branch}${NC}"
        echo ""
        filter_topic=""  # Clear so we use filter_topics array instead
        filter_topics_str="${filter_topics[*]}"
    fi

    # Check cache
    local cached_json fresh_json
    local cache_key="outstanding"

    cached_json=$(cache_get "$cache_key")

    if [[ -n "$cached_json" ]] && is_interactive; then
        # Have cache - show it immediately, then refresh in background
        local cached_output fresh_output

        cached_output=$(_render_outstanding "$cached_json" "$filter_topic" "$filter_topics_str")

        # Save cursor position before printing cached output
        tput sc 2>/dev/null || true

        # Print cached output + loading indicator
        echo "$cached_output"
        echo -e "${DIM}⟳ Refreshing...${NC}"

        # Fetch fresh data
        fresh_json=$(_fetch_outstanding_json)

        if [[ -n "$fresh_json" && "$fresh_json" != "[]" ]]; then
            cache_set "$cache_key" "$fresh_json"
            update_completion_cache "$fresh_json"

            fresh_output=$(_render_outstanding "$fresh_json" "$filter_topic" "$filter_topics_str")

            # Restore cursor and clear to end of screen
            tput rc 2>/dev/null || true
            tput ed 2>/dev/null || true

            # Print fresh output
            echo "$fresh_output"

            # Show status
            if [[ "$cached_output" != "$fresh_output" ]]; then
                echo -e "${DIM}↻ Updated${NC}"
            else
                echo -e "${DIM}✓ Up to date${NC}"
            fi

            # Prefetch status for all PRs in background
            prefetch_all_pr_data "$fresh_json" &
        else
            # API failed - just remove the refreshing indicator
            tput cuu 1 2>/dev/null || true
            tput ed 2>/dev/null || true
            echo -e "${DIM}✓ (cached)${NC}"
        fi
    else
        # No cache - fetch with spinner
        if is_interactive; then
            show_spinner "Fetching PRs..." &
            local spinner_pid=$!
            fresh_json=$(_fetch_outstanding_json)
            stop_spinner "$spinner_pid"
        else
            # Non-interactive (piped) - fetch quietly
            fresh_json=$(_fetch_outstanding_json)
        fi

        if [[ -n "$fresh_json" && "$fresh_json" != "[]" ]]; then
            cache_set "$cache_key" "$fresh_json"
            update_completion_cache "$fresh_json"
            _render_outstanding "$fresh_json" "$filter_topic" "$filter_topics_str"

            # Prefetch status in background (only if interactive)
            if is_interactive; then
                prefetch_all_pr_data "$fresh_json" &
            fi
        elif [[ "$fresh_json" == "[]" ]]; then
            echo "No open PRs found for $GITHUB_USER"
        else
            echo -e "${RED}Failed to fetch PRs${NC}" >&2
            return 1
        fi
    fi
}
