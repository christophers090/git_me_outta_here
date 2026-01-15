# prs outstanding mode - list all outstanding PRs with chain detection
# shellcheck shell=bash

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

    # Fetch all open PRs
    local prs_json
    prs_json=$(gh pr list -R "$REPO" --author "$GITHUB_USER" --state open \
        --json number,title,url,body,headRefName,reviewDecision,statusCheckRollup 2>/dev/null || echo "[]")

    # Update tab completion cache while we have the data
    update_completion_cache "$prs_json"

    if [[ "$(echo "$prs_json" | jq 'length')" -eq 0 ]]; then
        echo "No open PRs found for $GITHUB_USER"
        return 0
    fi

    # Parse PRs into structured data
    # ci_status: "pass" (all success), "fail" (any failure), "pending" (running/pending)
    # Only check the configured CI context (not green-commits or other downstream pipelines)
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
    find_chain_root() {
        local topic="$1"
        local relative="${pr_relative[$topic]:-}"
        if [[ -z "$relative" || "$relative" == "main" || -z "${pr_data[$relative]:-}" ]]; then
            echo "$topic"
        else
            find_chain_root "$relative"
        fi
    }

    # Helper: Get chain order string (topic -> child -> grandchild)
    get_chain_order() {
        local topic="$1"
        local result="$topic"
        local children="${pr_children[$topic]:-}"
        if [[ -n "$children" ]]; then
            local child_array=($children)
            for child in "${child_array[@]}"; do
                result="$result -> $(get_chain_order "$child")"
            done
        fi
        echo "$result"
    }

    # Helper: Print single PR
    print_pr() {
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

        echo -e "${prefix}${ci_sym}|${review_sym} ${BOLD}#${number}:${NC} ${title}"
        echo -e "${prefix}    ${DIM}Topic:${NC} ${topic}"
        if [[ -n "$relative" && "$relative" != "main" ]]; then
            echo -e "${prefix}    ${DIM}Relative:${NC} ${relative}"
        else
            echo -e "${prefix}    ${DIM}Relative:${NC} (none)"
        fi
        echo -e "${prefix}    ${CYAN}${url}${NC}"
    }

    # Helper: Print chain recursively
    print_chain() {
        local topic="$1"
        local prefix="$2"

        print_pr "$topic" "$prefix"
        echo ""

        local children="${pr_children[$topic]:-}"
        if [[ -n "$children" ]]; then
            local child_array=($children)
            for child in "${child_array[@]}"; do
                print_chain "$child" "$prefix"
            done
        fi
    }

    # If "this" mode with topics from current branch
    if [[ ${#filter_topics[@]} -gt 0 ]]; then
        echo -e "${BOLD}Topics in current branch:${NC} ${filter_topics[*]}"
        echo ""

        declare -A shown_roots
        for topic in "${filter_topics[@]}"; do
            if [[ -n "${pr_data[$topic]:-}" ]]; then
                local root
                root=$(find_chain_root "$topic")
                if [[ -z "${shown_roots[$root]:-}" ]]; then
                    shown_roots[$root]=1
                    local chain_order
                    chain_order=$(get_chain_order "$root")
                    echo -e "${BOLD}────────────────────────────────────────────────────────${NC}"
                    echo -e "${DIM}${chain_order}${NC}"
                    echo -e "${BOLD}────────────────────────────────────────────────────────${NC}"
                    echo ""
                    print_chain "$root" "  "
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
        filter_root=$(find_chain_root "$filter_topic")
        chain_order=$(get_chain_order "$filter_root")
        echo -e "${BOLD}────────────────────────────────────────────────────────${NC}"
        echo -e "${DIM}${chain_order}${NC}"
        echo -e "${BOLD}────────────────────────────────────────────────────────${NC}"
        echo ""
        print_chain "$filter_root" "  "
        return 0
    fi

    # Print all chains
    for root in "${roots[@]}"; do
        local chain_order
        chain_order=$(get_chain_order "$root")
        echo -e "${BOLD}────────────────────────────────────────────────────────${NC}"
        echo -e "${DIM}${chain_order}${NC}"
        echo -e "${BOLD}────────────────────────────────────────────────────────${NC}"
        echo ""
        print_chain "$root" "  "
        echo ""
        echo ""
    done

    # Print standalone PRs (no chain)
    for topic in "${standalone[@]}"; do
        print_pr "$topic" ""
        echo ""
    done
}
