# prs build_retry_failed mode - retry all failed buildkite jobs
# shellcheck shell=bash

run_build_retry_failed() {
    local topic="$1"
    get_pr_or_fail "$topic" "build_retry_failed" "all" "number,title,statusCheckRollup" || return 1
    pr_basics

    BK_BUILD_URL=$(echo "$PR_JSON" | jq -r ".[0].statusCheckRollup[]? | select(.context == \"${CI_CHECK_CONTEXT}\") | .targetUrl // empty" 2>/dev/null | head -1)

    if ! get_build_for_topic "$topic" "$PR_NUMBER" "$PR_TITLE"; then
        return 1
    fi

    echo -e "${BOLD}${BLUE}PR #${PR_NUMBER}:${NC} ${PR_TITLE}"
    echo -e "${DIM}Build #${BK_BUILD_NUMBER}${NC}"
    echo ""

    # Find failed jobs
    local failed_jobs=()
    local failed_names=()
    while read -r job; do
        local job_id job_name job_state
        job_id=$(echo "$job" | jq -r '.id')
        job_name=$(strip_emoji "$(echo "$job" | jq -r '.name')")
        job_state=$(echo "$job" | jq -r '.state')

        if [[ "$job_state" == "failed" || "$job_state" == "timed_out" ]]; then
            failed_jobs+=("$job_id")
            failed_names+=("$job_name")
        fi
    done < <(echo "$BK_BUILD_JSON" | jq -c '.jobs[] | select(.type == "script")')

    if [[ ${#failed_jobs[@]} -eq 0 ]]; then
        echo -e "${GREEN}No failed jobs to retry${NC}"
        return 0
    fi

    echo -e "Found ${RED}${#failed_jobs[@]} failed job(s)${NC}:"
    for name in "${failed_names[@]}"; do
        echo -e "  ${RED}✗${NC} $name"
    done
    echo ""

    echo -e "${BOLD}Retrying failed jobs...${NC}"
    local success_count=0
    local fail_count=0

    for i in "${!failed_jobs[@]}"; do
        local job_id="${failed_jobs[$i]}"
        local job_name="${failed_names[$i]}"

        if bk job retry "$job_id" -y &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Retried: $job_name"
            success_count=$((success_count + 1))
        else
            echo -e "  ${RED}✗${NC} Failed to retry: $job_name"
            fail_count=$((fail_count + 1))
        fi
    done

    echo ""
    if [[ $fail_count -eq 0 ]]; then
        echo -e "${GREEN}All ${success_count} job(s) retried successfully${NC}"
    else
        echo -e "${YELLOW}${success_count} retried, ${fail_count} failed${NC}"
    fi
}
