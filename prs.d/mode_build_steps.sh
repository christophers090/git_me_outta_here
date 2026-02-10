# prs build_steps mode - show build steps status
# shellcheck shell=bash

# Render build steps from BK build JSON (single jq call, no per-job forks)
_render_build_steps_table() {
    local build_json="$1"
    local topic="$2"

    local now_epoch
    now_epoch=$(date +%s)

    # Extract build state + all job data in ONE jq call
    local extracted
    extracted=$(echo "$build_json" | jq -r --argjson now "$now_epoch" '
        .state,
        (.jobs[] | select(.type == "script") |
            # Strip :emoji: codes and trim whitespace
            ((.name // "unknown") | gsub(":[a-z_-]+:"; "") | gsub("^\\s+|\\s+$"; "")) as $name |
            (if $name == "" then "(pipeline)" else $name end) as $clean_name |
            (.state // "unknown") as $state |
            # Strip fractional seconds (.123Z -> Z) for fromdateiso8601
            (def parse_ts: gsub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
            if .finished_at and .started_at then
                ((.finished_at | parse_ts) - (.started_at | parse_ts)) | tostring
            elif .started_at then
                (($now - (.started_at | parse_ts)) | tostring) + " running"
            else
                "queued"
            end) as $duration |
            "\($clean_name)\t\($state)\t\($duration)"
        )
    ')

    # Read build state (first line)
    local build_state
    read -r build_state <<< "$extracted"

    local state_color
    case "$build_state" in
        passed) state_color="${GREEN}" ;;
        failed|canceled) state_color="${RED}" ;;
        running) state_color="${YELLOW}" ;;
        *) state_color="${DIM}" ;;
    esac
    echo -e "Build Status: ${state_color}${build_state}${NC}"
    echo ""

    local max_name_len=30

    printf "${BOLD}%3s │ %-${max_name_len}s │ %-14s │ %s${NC}\n" "#" "Job" "Status" "Time"
    printf "%.0s─" $(seq 1 3); printf "─┼─"; printf "%.0s─" $(seq 1 $max_name_len); printf "─┼─"; printf "%.0s─" $(seq 1 14); printf "─┼─"; printf "%.0s─" $(seq 1 12); echo ""

    # Read job lines (tab-separated: name, state, duration)
    local job_num=0 name state duration_str
    while IFS=$'\t' read -r name state duration_str; do
        [[ -z "$name" ]] && continue
        job_num=$((job_num + 1))

        # Truncate name if too long
        if [[ ${#name} -gt $max_name_len ]]; then
            name="${name:0:$((max_name_len-3))}..."
        fi

        # Format duration
        local time_str
        if [[ "$duration_str" == "queued" ]]; then
            time_str="queued"
        elif [[ "$duration_str" == *" running" ]]; then
            local secs="${duration_str% running}"
            time_str="$(format_duration "$secs") ▶"
        else
            time_str=$(format_duration "$duration_str")
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
    done < <(echo "$extracted" | tail -n +2)

    echo ""
    echo -e "${DIM}${BK_BUILD_URL}${NC}"
    echo -e "${DIM}Cancel a job: prs -bc ${topic} <#>${NC}"
}

run_build_steps() {
    local topic="$1"

    # Phase 1: PR lookup - fast from cache (status/outstanding), shows header immediately
    get_build_pr_or_fail "$topic" "build_steps" || return 1

    echo -e "${BOLD}${BLUE}PR #${PR_NUMBER}:${NC} ${PR_TITLE}"

    # Phase 2: BK build fetch - always fresh (volatile data)
    if ! get_build_for_topic "$topic" "$PR_NUMBER" "$PR_TITLE"; then
        return 1
    fi

    echo -e "${DIM}Build #${BK_BUILD_NUMBER}${NC}"
    echo ""

    # Phase 3: Render build steps table
    _render_build_steps_table "$BK_BUILD_JSON" "$topic"
}
