# prs build_retry mode - retry a specific buildkite job
# shellcheck shell=bash

run_build_retry() {
    local topic="${1:-}"
    local job_num="${2:-}"

    if [[ -z "$topic" ]]; then
        echo -e "${RED}Error:${NC} Topic required for build_retry"
        echo "Usage: prs -br <topic> <job#>"
        return 1
    fi

    if [[ -z "$job_num" ]]; then
        echo -e "${RED}Error:${NC} Job number required"
        echo "Usage: prs -br <topic> <job#>"
        echo ""
        echo "Run 'prs -bs $topic' to see job numbers"
        return 1
    fi

    get_build_pr_or_fail "$topic" "build_retry" || return 1

    if ! get_build_for_topic "$topic" "$PR_NUMBER" "$PR_TITLE"; then
        return 1
    fi

    if ! get_job_by_number "$job_num"; then
        echo -e "${RED}Job #${job_num} not found${NC}"
        echo "Run 'prs -bs $topic' to see available jobs"
        return 1
    fi

    if ! check_job_retriable "$job_num" "$topic"; then
        return 1
    fi

    echo -e "${BOLD}Retrying job #${job_num}:${NC} ${BK_JOB_NAME}"
    echo -e "${DIM}Build #${BK_BUILD_NUMBER} | Job ID: ${BK_JOB_ID}${NC}"
    echo ""

    if bk job retry "$BK_JOB_ID" -y 2>&1; then
        echo -e "${GREEN}Job retried successfully${NC}"
    else
        echo -e "${RED}Failed to retry job${NC}"
        return 1
    fi
}
