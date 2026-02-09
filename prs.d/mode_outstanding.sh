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

    # Parse submodule PRs into lookup (topic -> "number|title|url|review_ok")
    declare -A sub_pr_data
    declare -a sub_all_topics=()
    if [[ -n "$_OUTSTANDING_SUB_JSON" && "$_OUTSTANDING_SUB_JSON" != "[]" ]]; then
        local sub_parsed
        sub_parsed=$(parse_submodule_pr_map "$_OUTSTANDING_SUB_JSON")
        while IFS='|' read -r s_topic s_number s_title s_url s_review_ok; do
            [[ -z "$s_topic" || "$s_topic" == "null" ]] && continue
            sub_pr_data["$s_topic"]="$s_number|$s_title|$s_url|$s_review_ok"
            sub_all_topics+=("$s_topic")
        done <<< "$sub_parsed"
    fi

    # Parse PRs into structured data
    local parsed ci_context_pattern
    ci_context_pattern="${CI_CHECK_CONTEXT:-buildkite/}"
    parsed=$(echo "$prs_json" | jq -r --arg ci "$ci_context_pattern" '
      .[] |
      ((.body | capture("Topic:\\s*(?<t>\\S+)") | .t) // (.headRefName | split("/") | last)) as $topic |
      ((.body | capture("Relative:\\s*(?<r>\\S+)") | .r) // "") as $relative |
      ([(.statusCheckRollup // [])[] | select(.context | startswith($ci))] |
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

    # Helper: Get chain order string (main <- topic <- child <- grandchild)
    _get_chain_order() {
        local topic="$1"
        local result="$topic"
        local children="${pr_children[$topic]:-}"
        if [[ -n "$children" ]]; then
            local child_array=($children)
            for child in "${child_array[@]}"; do
                result="$result <- $(_get_chain_order "$child")"
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

        # Submodule PR line (if one exists for this topic)
        if [[ -n "${sub_pr_data[$topic]:-}" ]]; then
            local s_number s_title s_url s_review_ok
            IFS='|' read -r s_number s_title s_url s_review_ok <<< "${sub_pr_data[$topic]}"
            local sub_review_sym="$CROSS"
            [[ "$s_review_ok" == "true" ]] && sub_review_sym="$CHECK"
            local sub_link="\e]8;;${s_url}\a${CYAN}#${s_number}${NC}\e]8;;\a"
            echo -e "${prefix}    Sub ${sub_link}: Reviews ${sub_review_sym}"
        fi

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
                    echo -e "${DIM}main <- ${chain_order}${NC}"
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
        echo -e "${DIM}main <- ${chain_order}${NC}"
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
        echo -e "${DIM}main <- ${chain_order}${NC}"
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

    # Orphaned submodule PRs - sub PRs with no matching main-repo topic
    if [[ ${#sub_all_topics[@]} -gt 0 ]]; then
        local -a orphans=()
        for s_topic in "${sub_all_topics[@]}"; do
            if [[ -z "${pr_data[$s_topic]:-}" ]]; then
                orphans+=("$s_topic")
            fi
        done

        if [[ ${#orphans[@]} -gt 0 ]]; then
            echo ""
            echo -e "${RED}${BOLD}────────────────────────────────────────────────────────${NC}"
            echo -e "${RED}${BOLD}⚠ Orphaned Submodule PRs (no matching main PR)${NC}"
            echo -e "${RED}${BOLD}────────────────────────────────────────────────────────${NC}"
            echo ""

            for s_topic in "${orphans[@]}"; do
                local s_number s_title s_url s_review_ok
                IFS='|' read -r s_number s_title s_url s_review_ok <<< "${sub_pr_data[$s_topic]}"
                local sub_review_sym="$CROSS"
                [[ "$s_review_ok" == "true" ]] && sub_review_sym="$CHECK"
                local sub_link="\e]8;;${s_url}\a${RED}#${s_number}${NC}\e]8;;\a"

                echo -e "${BOLD}${sub_link}:${NC} ${s_title}"
                echo -e "    Reviews ${sub_review_sym}"
                echo -e "    ${DIM}Topic:${NC} ${s_topic}"
                echo ""
            done
        fi
    fi
}

# Global state for rendering (set by run_outstanding, used by wrapper functions)
_OUTSTANDING_FILTER_TOPIC=""
_OUTSTANDING_FILTER_TOPICS_STR=""
_OUTSTANDING_SUB_JSON=""

# Render wrapper that uses global filter state
_outstanding_render() {
    _render_outstanding "$1" "$_OUTSTANDING_FILTER_TOPIC" "$_OUTSTANDING_FILTER_TOPICS_STR"
}

# Post-cache hook: update completion cache and prefetch PR data
_outstanding_post_cache() {
    local fresh_json="$1"
    update_completion_cache "$fresh_json" "$_OUTSTANDING_SUB_JSON"
    # Prefetch status in background (only if interactive)
    if is_interactive; then
        prefetch_all_pr_data "$fresh_json" &
    fi
}

run_outstanding() {
    local filter_topic="$1"
    local filter_topics=()

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
    fi

    # Fetch submodule PRs fresh every time (still cache for status mode)
    _OUTSTANDING_SUB_JSON=""
    if [[ -n "$SUBMODULE_REPO" && "$SUBMODULE_MODE" != "true" ]]; then
        _OUTSTANDING_SUB_JSON=$(fetch_submodule_prs)
        if [[ -n "$_OUTSTANDING_SUB_JSON" && "$_OUTSTANDING_SUB_JSON" != "[]" ]]; then
            cache_set "sub_outstanding" "$_OUTSTANDING_SUB_JSON"
        fi
    fi

    # Set global state for render wrapper
    _OUTSTANDING_FILTER_TOPIC="$filter_topic"
    _OUTSTANDING_FILTER_TOPICS_STR="${filter_topics[*]}"

    # Use display_with_refresh for the standard cache-then-refresh pattern
    display_with_refresh \
        "outstanding" \
        "_fetch_outstanding_json" \
        "_outstanding_render" \
        "Fetching PRs..." \
        "_outstanding_post_cache"
}
