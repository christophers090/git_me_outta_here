# prs build_dump mode - dump console output from all failed buildkite jobs
# shellcheck shell=bash

run_build_dump() {
    local topic="$1"
    get_pr_or_fail "$topic" "build_dump" "all" "number,title,statusCheckRollup" || return 1
    pr_basics

    # Get build URL and set up globals
    extract_bk_build_url "$PR_JSON"

    if ! get_build_for_topic "$topic" "$PR_NUMBER" "$PR_TITLE"; then
        return 1
    fi

    local bk_token
    bk_token=$(bk_get_token) || return 1

    # Find all failed jobs
    local failed_jobs
    failed_jobs=$(echo "$BK_BUILD_JSON" | jq -c '.jobs[] | select(.type == "script" and (.state == "failed" or .state == "timed_out"))')

    if [[ -z "$failed_jobs" ]]; then
        echo -e "${GREEN}No failed jobs in build #${BK_BUILD_NUMBER}${NC}"
        echo -e "${DIM}PR #${PR_NUMBER}: ${PR_TITLE}${NC}"
        return 0
    fi

    # Count failed jobs
    local failed_count
    failed_count=$(echo "$BK_BUILD_JSON" | jq '[.jobs[] | select(.type == "script" and (.state == "failed" or .state == "timed_out"))] | length')

    echo -e "${BOLD}${BLUE}PR #${PR_NUMBER}:${NC} ${PR_TITLE}"
    echo -e "${DIM}Build #${BK_BUILD_NUMBER} | ${RED}${failed_count} failed job(s)${NC}"
    echo -e "${DIM}${BK_BUILD_URL}${NC}"
    echo ""

    # Process each failed job
    local job_num=0
    while read -r job; do
        [[ -z "$job" ]] && continue
        job_num=$((job_num + 1))

        local job_id job_name job_state exit_status log_url
        job_id=$(echo "$job" | jq -r '.id')
        job_name=$(strip_emoji "$(echo "$job" | jq -r '.name // "unknown"')")
        [[ -z "$job_name" ]] && job_name="(pipeline)"
        job_state=$(echo "$job" | jq -r '.state')
        exit_status=$(echo "$job" | jq -r '.exit_status // "N/A"')
        log_url=$(echo "$job" | jq -r '.raw_log_url // empty')

        # Find the job number in the full list
        local actual_job_num=0
        while read -r check_job; do
            actual_job_num=$((actual_job_num + 1))
            local check_id
            check_id=$(echo "$check_job" | jq -r '.id')
            if [[ "$check_id" == "$job_id" ]]; then
                break
            fi
        done < <(echo "$BK_BUILD_JSON" | jq -c '.jobs[] | select(.type == "script")')

        # Print header
        echo -e "${BOLD}${RED}════════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}${RED}FAILED JOB #${actual_job_num}: ${job_name}${NC}"
        echo -e "${RED}────────────────────────────────────────────────────────────────────────────────${NC}"
        echo -e "${DIM}Build:${NC} #${BK_BUILD_NUMBER}  ${DIM}State:${NC} ${job_state}  ${DIM}Exit Code:${NC} ${exit_status}"
        echo -e "${RED}────────────────────────────────────────────────────────────────────────────────${NC}"
        echo ""

        if [[ -z "$log_url" || "$log_url" == "null" ]]; then
            echo -e "${YELLOW}No log available for this job${NC}"
            echo ""
            continue
        fi

        # Fetch and display full log
        local log_content
        log_content=$(curl -sf -H "Authorization: Bearer $bk_token" "$log_url" 2>/dev/null)

        if [[ -n "$log_content" ]]; then
            echo "$log_content"
        else
            echo -e "${YELLOW}Failed to fetch log${NC}"
        fi

        echo ""
    done <<< "$failed_jobs"

    echo -e "${BOLD}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${DIM}End of failed job logs${NC}"
}
