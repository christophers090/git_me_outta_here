# prs build_console mode - show console output from a buildkite job
# shellcheck shell=bash

run_build_console() {
    local topic="${1:-}"
    local job_num="${2:-}"
    shift 2 || true

    # Parse -n flag for line count
    local lines=100
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n)
                if [[ $# -lt 2 ]]; then
                    echo -e "${RED}Error:${NC} -n requires a line count"
                    return 1
                fi
                if ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
                    echo -e "${RED}Error:${NC} -n must be a positive integer"
                    return 1
                fi
                lines="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$topic" ]]; then
        echo -e "${RED}Error:${NC} Topic required for build_console"
        echo "Usage: prs -bcon <topic> <job#> [-n lines]"
        return 1
    fi

    if [[ -z "$job_num" ]]; then
        echo -e "${RED}Error:${NC} Job number required"
        echo "Usage: prs -bcon <topic> <job#> [-n lines]"
        echo ""
        echo "Run 'prs -bs $topic' to see job numbers"
        return 1
    fi

    get_pr_or_fail "$topic" "build_console" "all" "number,title,statusCheckRollup" || return 1
    pr_basics

    extract_bk_build_url "$PR_JSON"

    if ! get_build_for_topic "$topic" "$PR_NUMBER" "$PR_TITLE"; then
        return 1
    fi

    if ! get_job_by_number "$job_num"; then
        echo -e "${RED}Job #${job_num} not found${NC}"
        echo "Run 'prs -bs $topic' to see available jobs"
        return 1
    fi

    # Get the raw log URL for this job
    local log_url
    log_url=$(echo "$BK_BUILD_JSON" | jq -r --arg id "$BK_JOB_ID" '.jobs[] | select(.id == $id) | .raw_log_url // empty')

    if [[ -z "$log_url" || "$log_url" == "null" ]]; then
        echo -e "${RED}No log available for job #${job_num} (${BK_JOB_NAME})${NC}"
        echo -e "${DIM}Job may still be queued or log not yet available${NC}"
        return 1
    fi

    local bk_token
    bk_token=$(bk_get_token) || return 1

    echo -e "${BOLD}${BLUE}PR #${PR_NUMBER}:${NC} ${PR_TITLE}"
    echo -e "${DIM}Build #${BK_BUILD_NUMBER} | Job #${job_num}: ${BK_JOB_NAME}${NC}"
    echo -e "${DIM}Showing last ${lines} lines${NC}"
    echo ""

    # Fetch and display log
    local log_output
    if ! log_output=$(curl -sf -H "Authorization: Bearer $bk_token" "$log_url" 2>/dev/null); then
        echo -e "${RED}Failed to fetch log${NC}"
        return 1
    fi
    echo "$log_output" | tail -n "$lines"
}
