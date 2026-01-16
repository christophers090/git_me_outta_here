# prs build_cancel mode - cancel a buildkite job
# shellcheck shell=bash

run_build_cancel() {
    local topic="$1"
    local job_num="$2"

    require_topic "build_cancel" "$topic" || return 1

    if [[ -z "$job_num" ]]; then
        echo -e "${RED}Error:${NC} Job number required"
        echo "Usage: prs -bc <topic> <job#>"
        echo ""
        echo "Run 'prs -bs $topic' to see job numbers"
        return 1
    fi

    local pr_json
    pr_json=$(cached_find_pr "$topic" "all" "number,title,statusCheckRollup")

    if ! pr_exists "$pr_json"; then
        pr_not_found "$topic"
        return 1
    fi

    local number title
    number=$(pr_field "$pr_json" "number")
    title=$(pr_field "$pr_json" "title")

    BK_BUILD_URL=$(echo "$pr_json" | jq -r ".[0].statusCheckRollup[]? | select(.context == \"${CI_CHECK_CONTEXT}\") | .targetUrl // empty" 2>/dev/null | head -1)

    if ! get_build_for_topic "$topic" "$number" "$title"; then
        return 1
    fi

    if ! get_job_by_number "$job_num"; then
        echo -e "${RED}Job #${job_num} not found${NC}"
        echo "Run 'prs -bs $topic' to see available jobs"
        return 1
    fi

    if ! check_job_cancelable "$job_num" "$topic"; then
        return 1
    fi

    echo -e "${BOLD}Canceling job #${job_num}:${NC} ${BK_JOB_NAME}"
    echo -e "${DIM}Build #${BK_BUILD_NUMBER} | Job ID: ${BK_JOB_ID}${NC}"
    echo ""

    if bk job cancel "$BK_JOB_ID" -y 2>&1; then
        echo -e "${GREEN}Job canceled successfully${NC}"
    else
        echo -e "${RED}Failed to cancel job${NC}"
        return 1
    fi
}
