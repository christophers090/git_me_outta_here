# prs build_steps mode - show build steps status
# shellcheck shell=bash

run_build_steps() {
    local topic="$1"
    require_topic "build_steps" "$topic" || return 1

    local pr_json
    pr_json=$(find_pr "$topic" "all" "number,title,statusCheckRollup")

    if ! pr_exists "$pr_json"; then
        pr_not_found "$topic"
        return 1
    fi

    local number title
    number=$(pr_field "$pr_json" "number")
    title=$(pr_field "$pr_json" "title")

    # Get build URL and set up globals
    BK_BUILD_URL=$(echo "$pr_json" | jq -r ".[0].statusCheckRollup[]? | select(.context == \"${CI_CHECK_CONTEXT}\") | .targetUrl // empty" 2>/dev/null | head -1)

    if ! get_build_for_topic "$topic" "$number" "$title"; then
        return 1
    fi

    echo -e "${BOLD}${BLUE}PR #${number}:${NC} ${title}"
    echo -e "${DIM}Build #${BK_BUILD_NUMBER}${NC}"
    echo ""

    # Show build overall status
    local build_state state_color
    build_state=$(echo "$BK_BUILD_JSON" | jq -r '.state')

    case "$build_state" in
        passed) state_color="${GREEN}" ;;
        failed|canceled) state_color="${RED}" ;;
        running) state_color="${YELLOW}" ;;
        *) state_color="${DIM}" ;;
    esac
    echo -e "Build Status: ${state_color}${build_state}${NC}"
    echo ""

    # Format: # | Job | Status | Time
    local max_name_len=30

    # Print header
    printf "${BOLD}%3s │ %-${max_name_len}s │ %-14s │ %s${NC}\n" "#" "Job" "Status" "Time"
    printf "%.0s─" $(seq 1 3); printf "─┼─"; printf "%.0s─" $(seq 1 $max_name_len); printf "─┼─"; printf "%.0s─" $(seq 1 14); printf "─┼─"; printf "%.0s─" $(seq 1 12); echo ""

    # Process each job
    local job_num=0
    while read -r job; do
        job_num=$((job_num + 1))
        local name state started_at finished_at

        name=$(strip_emoji "$(echo "$job" | jq -r '.name // "unknown"')")
        [[ -z "$name" ]] && name="(pipeline)"
        state=$(echo "$job" | jq -r '.state // "unknown"')
        started_at=$(echo "$job" | jq -r '.started_at // empty')
        finished_at=$(echo "$job" | jq -r '.finished_at // empty')

        # Truncate name if too long
        if [[ ${#name} -gt $max_name_len ]]; then
            name="${name:0:$((max_name_len-3))}..."
        fi

        # Calculate time
        local time_str
        if [[ -n "$finished_at" && -n "$started_at" ]]; then
            local start_epoch end_epoch duration_sec
            start_epoch=$(date -d "$started_at" +%s 2>/dev/null || echo 0)
            end_epoch=$(date -d "$finished_at" +%s 2>/dev/null || echo 0)
            duration_sec=$((end_epoch - start_epoch))
            time_str=$(format_duration "$duration_sec")
        elif [[ -n "$started_at" ]]; then
            local start_epoch now_epoch elapsed_sec
            start_epoch=$(date -d "$started_at" +%s 2>/dev/null || echo 0)
            now_epoch=$(date +%s)
            elapsed_sec=$((now_epoch - start_epoch))
            time_str="$(format_duration "$elapsed_sec") ▶"
        else
            time_str="queued"
        fi

        # Color status with proper padding
        local status_colored
        local pad_len=$((14 - ${#state}))
        local padding=""
        for ((i=0; i<pad_len; i++)); do padding+=" "; done

        case "$state" in
            passed) status_colored="${GREEN}${state}${NC}${padding}" ;;
            failed|timed_out|canceled) status_colored="${RED}${state}${NC}${padding}" ;;
            running) status_colored="${YELLOW}${state}${NC}${padding}" ;;
            scheduled|assigned|waiting) status_colored="${CYAN}${state}${NC}${padding}" ;;
            *) status_colored="${DIM}${state}${NC}${padding}" ;;
        esac

        printf "%3d │ %-${max_name_len}s │ %b │ %s\n" "$job_num" "$name" "$status_colored" "$time_str"
    done < <(echo "$BK_BUILD_JSON" | jq -c '.jobs[] | select(.type == "script")')

    echo ""
    echo -e "${DIM}${BK_BUILD_URL}${NC}"
    echo -e "${DIM}Cancel a job: prs -bc ${topic} <#>${NC}"
}
