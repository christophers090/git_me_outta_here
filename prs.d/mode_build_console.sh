# prs build_console mode - show console output from a buildkite job
# shellcheck shell=bash

run_build_console() {
    local topic="$1"
    local job_num="$2"
    shift 2 || true

    # Parse -n flag for line count
    local lines=10
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n)
                lines="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    require_topic "build_console" "$topic" || return 1

    if [[ -z "$job_num" ]]; then
        echo -e "${RED}Error:${NC} Job number required"
        echo "Usage: prs -bcon <topic> <job#> [-n lines]"
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

    # Get the raw log URL for this job
    local log_url
    log_url=$(echo "$BK_BUILD_JSON" | jq -r --arg id "$BK_JOB_ID" '.jobs[] | select(.id == $id) | .raw_log_url // empty')

    if [[ -z "$log_url" || "$log_url" == "null" ]]; then
        echo -e "${RED}No log available for job #${job_num} (${BK_JOB_NAME})${NC}"
        echo -e "${DIM}Job may still be queued or log not yet available${NC}"
        return 1
    fi

    # Get API token from bk config
    local bk_token
    bk_token=$(grep 'api_token:' ~/.config/bk.yaml 2>/dev/null | head -1 | awk '{print $2}')

    if [[ -z "$bk_token" ]]; then
        echo -e "${RED}Could not find Buildkite API token in ~/.config/bk.yaml${NC}"
        return 1
    fi

    echo -e "${BOLD}${BLUE}PR #${number}:${NC} ${title}"
    echo -e "${DIM}Build #${BK_BUILD_NUMBER} | Job #${job_num}: ${BK_JOB_NAME}${NC}"
    echo -e "${DIM}Showing last ${lines} lines${NC}"
    echo ""

    # Fetch and display log
    curl -sf -H "Authorization: Bearer $bk_token" "$log_url" 2>/dev/null | tail -n "$lines"

    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo -e "${RED}Failed to fetch log${NC}"
        return 1
    fi
}
