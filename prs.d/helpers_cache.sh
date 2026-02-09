# prs cache helpers - caching layer for API responses
# shellcheck shell=bash

# Cache configuration
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/prs"

# Initialize cache directory
cache_init() {
    [[ -d "$CACHE_DIR" ]] || mkdir -p "$CACHE_DIR"
}

# Get cached JSON data
# Returns: cached data if exists, empty string otherwise
cache_get() {
    local key="$1"
    local cache_file="$CACHE_DIR/${key}.json"
    if [[ -f "$cache_file" ]]; then
        cat "$cache_file"
    fi
}

# Save data to cache
cache_set() {
    # Skip caching if NO_CACHE is set (e.g., when using -u flag)
    [[ -n "${NO_CACHE:-}" ]] && return 0

    local key="$1"
    local data="$2"
    cache_init
    local json_file="$CACHE_DIR/${key}.json"
    local ts_file="$CACHE_DIR/${key}.ts"
    # Atomic writes: write to tmp, then mv (rename is atomic on same FS)
    echo "$data" > "${json_file}.tmp" && mv "${json_file}.tmp" "$json_file"
    date +%s > "${ts_file}.tmp" && mv "${ts_file}.tmp" "$ts_file"
}

# Cached wrapper for find_pr - always fetches fresh, caches result
# Usage: cached_find_pr <topic> [state] [fields]
cached_find_pr() {
    local topic="$1"
    local state="${2:-all}"
    local fields="${3:-number,title,url}"
    local fields_hash="${fields//,/_}"
    local cache_key="pr_${topic}_${state}_${fields_hash}"

    local result
    result=$(find_pr "$topic" "$state" "$fields")

    if [[ -n "$result" && "$result" != "[]" ]]; then
        cache_set "$cache_key" "$result"
    fi

    echo "$result"
}

# Invalidate all caches for a topic (call after mutations like close/merge)
# Usage: invalidate_pr_caches <topic>
invalidate_pr_caches() {
    local topic="$1"
    rm -f "$CACHE_DIR"/pr_"${topic}"_*.json "$CACHE_DIR"/pr_"${topic}"_*.ts 2>/dev/null || true
    rm -f "$CACHE_DIR"/status_"${topic}".json "$CACHE_DIR"/status_"${topic}".ts 2>/dev/null || true
    rm -f "$CACHE_DIR"/comments_"${topic}".json "$CACHE_DIR"/comments_"${topic}".ts 2>/dev/null || true
    rm -f "$CACHE_DIR"/comments_data_"${topic}".json "$CACHE_DIR"/comments_data_"${topic}".ts 2>/dev/null || true
}

# Check if output is going to a terminal (for animation decisions)
is_interactive() {
    [[ -t 1 ]]
}

# Show a spinner while waiting for a command
# Usage: show_spinner "message" &  then  kill $! when done
show_spinner() {
    local msg="$1"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    # Hide cursor
    tput civis 2>/dev/null || true

    while true; do
        printf "\r${DIM}%s %s${NC}" "${spin:i++%10:1}" "$msg"
        sleep 0.1
    done
}

# Stop spinner and clear the line
stop_spinner() {
    local pid="$1"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    printf "\r\033[K"  # Clear line
    tput cnorm 2>/dev/null || true  # Show cursor
}

# Execute command with spinner if interactive, otherwise run quietly
# Args: $1=message, $2+=command and args
# Output: command output to stdout
fetch_with_spinner() {
    local msg="$1"
    shift

    if is_interactive; then
        show_spinner "$msg" &
        local pid=$!
        local result
        result=$("$@")
        stop_spinner "$pid"
        echo "$result"
    else
        "$@"
    fi
}

# Count visual terminal lines (accounts for line wrapping from long lines)
# Uses terminal width to calculate how many screen rows text actually occupies.
_count_visual_lines() {
    local text="$1"
    local cols
    cols=$(tput cols 2>/dev/null || echo 80)
    # Strip all ANSI codes in one sed pass (instead of per-line fork)
    local stripped
    stripped=$(printf '%s' "$text" | sed $'s/\x1b\\[[0-9;]*[a-zA-Z]//g; s/\x1b\\]8;;[^\x07]*\x07//g')
    local total=0
    while IFS= read -r line; do
        local len=${#line}
        if [[ $len -le $cols ]]; then
            total=$((total + 1))
        else
            total=$((total + (len + cols - 1) / cols))
        fi
    done <<< "$stripped"
    echo "$total"
}

# Hook globals for display_with_refresh customization
# Set these before calling display_with_refresh(), reset to "" after
DISPLAY_EARLY_EXIT_FN=""    # Called first; return 0 to exit early (e.g., yank mode)
DISPLAY_NOT_FOUND_FN=""     # Called when data is empty (e.g., "similar topics" suggestions)

# Display cached data immediately, refresh in background, update display if changed
# This is the standard "show cached, then refresh" pattern used by multiple modes.
#
# Args:
#   $1 - cache_key: key for cache_get/cache_set
#   $2 - fetch_fn: function name to fetch fresh data (called directly, not eval'd)
#   $3 - render_fn: function name to render data (called with data as first arg)
#   $4 - spinner_msg: message for spinner when no cache
#   $5 - post_cache_fn: optional function to run after caching (called with fresh data as arg)
#   $6 - empty_check: optional expression to check if data is empty (default: checks for empty string or "[]")
#
# Hooks (set via globals before calling):
#   DISPLAY_EARLY_EXIT_FN - if set and returns 0, exits immediately (for special modes like yank)
#   DISPLAY_NOT_FOUND_FN - if set, called instead of generic error when data empty
#
# Returns: 0 on success, 1 on failure
# Sets: DISPLAY_REFRESH_DATA to the final data (for caller to use if needed)
display_with_refresh() {
    local cache_key="$1"
    local fetch_fn="$2"
    local render_fn="$3"
    local spinner_msg="$4"
    local post_cache_fn="${5:-}"
    local empty_check="${6:-}"

    # Early exit hook (e.g., yank mode)
    if [[ -n "$DISPLAY_EARLY_EXIT_FN" ]]; then
        if "$DISPLAY_EARLY_EXIT_FN"; then
            return 0
        fi
    fi

    local cached_data fresh_data
    cached_data=$(cache_get "$cache_key")

    # Helper to check if data is empty
    _is_empty() {
        local data="$1"
        if [[ -n "$empty_check" ]]; then
            "$empty_check" "$data"
        else
            [[ -z "$data" ]]
        fi
    }

    if [[ -n "$cached_data" ]] && [[ -z "${NO_CACHE:-}" ]] && is_interactive; then
        # Have cache - show it immediately, then refresh in background
        local cached_output
        cached_output=$("$render_fn" "$cached_data")

        # Count visual lines (accounts for terminal line wrapping)
        local cached_lines
        cached_lines=$(_count_visual_lines "$cached_output")

        # Print cached output + loading indicator
        echo "$cached_output"
        echo -e "${DIM}⟳ Refreshing...${NC}"

        # Fetch fresh data
        fresh_data=$("$fetch_fn")

        if ! _is_empty "$fresh_data"; then
            cache_set "$cache_key" "$fresh_data"

            # Run post-cache function if provided
            if [[ -n "$post_cache_fn" ]]; then
                "$post_cache_fn" "$fresh_data"
            fi

            local fresh_output
            fresh_output=$("$render_fn" "$fresh_data")

            # Move cursor up by (cached_lines + 1 for refreshing line), then clear to end
            local lines_to_clear=$((cached_lines + 1))
            tput cuu "$lines_to_clear" 2>/dev/null || true
            tput ed 2>/dev/null || true

            # Print fresh output
            echo "$fresh_output"

            # Show status
            if [[ "$cached_output" != "$fresh_output" ]]; then
                echo -e "${DIM}↻ Updated${NC}"
            else
                echo -e "${DIM}✓ Up to date${NC}"
            fi

            DISPLAY_REFRESH_DATA="$fresh_data"
        else
            # API failed - just remove the refreshing indicator
            tput cuu 1 2>/dev/null || true
            tput ed 2>/dev/null || true
            echo -e "${DIM}✓ (cached)${NC}"
            DISPLAY_REFRESH_DATA="$cached_data"
        fi
    else
        # No cache - fetch with spinner
        if is_interactive; then
            show_spinner "$spinner_msg" &
            local spinner_pid=$!
            fresh_data=$("$fetch_fn")
            stop_spinner "$spinner_pid"
        else
            fresh_data=$("$fetch_fn")
        fi

        if ! _is_empty "$fresh_data"; then
            cache_set "$cache_key" "$fresh_data"

            # Run post-cache function if provided
            if [[ -n "$post_cache_fn" ]]; then
                "$post_cache_fn" "$fresh_data"
            fi

            "$render_fn" "$fresh_data"
            DISPLAY_REFRESH_DATA="$fresh_data"
        else
            # Data not found - use custom handler or generic error
            if [[ -n "$DISPLAY_NOT_FOUND_FN" ]]; then
                "$DISPLAY_NOT_FOUND_FN"
            else
                echo -e "${RED}Failed to fetch data${NC}" >&2
            fi
            return 1
        fi
    fi

    return 0
}

# Background prefetch status AND comments for all open PRs
# Called after outstanding list is fetched - makes subsequent prs <topic> and prs -c <topic> instant
# Completely non-blocking - spawns background jobs and returns immediately
prefetch_all_pr_data() {
    local prs_json="$1"

    # Don't prefetch if non-interactive, no data, or NO_CACHE is set
    is_interactive || return 0
    [[ -n "$prs_json" ]] || return 0
    [[ -n "${NO_CACHE:-}" ]] && return 0

    # Extract topics and PR numbers from JSON
    local pr_data
    pr_data=$(echo "$prs_json" | jq -r '
        .[] |
        ((.body | capture("Topic:\\s*(?<t>\\S+)") | .t) // (.headRefName | split("/") | last)) as $topic |
        "\(.number)|\($topic)|\(.title)|\(.url)"
    ' 2>/dev/null) || return 0

    # Spawn background jobs to prefetch each PR's status and comments
    while IFS='|' read -r number topic title url; do
        [[ -z "$topic" || "$topic" == "null" ]] && continue

        (
            # Prefetch status
            local status_json
            status_json=$(gh pr view "$number" -R "$REPO" \
                --json number,title,state,url,reviewDecision,reviewRequests,reviews,statusCheckRollup,mergeStateStatus,labels,isDraft \
                2>/dev/null)

            if [[ -n "$status_json" ]]; then
                cache_set "status_${topic}" "[$status_json]"
            fi

            # Prefetch comments
            if [[ -n "$number" ]]; then
                local comments_json resolution_status
                comments_json=$(get_ordered_comments "$number" 2>/dev/null)
                resolution_status=$(fetch_thread_resolution_status "$number" 2>/dev/null)

                if [[ -n "$comments_json" && -n "$resolution_status" ]]; then
                    local data
                    data=$(jq -n \
                        --argjson number "$number" \
                        --arg title "$title" \
                        --arg url "$url" \
                        --argjson comments "$comments_json" \
                        --argjson resolution "$resolution_status" \
                        '{number: $number, title: $title, url: $url, comments: $comments, resolution: $resolution}')

                    cache_set "comments_data_${topic}" "$data"

                    local unresolved_count
                    unresolved_count=$(echo "$resolution_status" | jq '[to_entries[] | select(.value == false)] | length')
                    cache_set "comments_${topic}" "$unresolved_count"
                fi
            fi
        ) &>/dev/null &
        _PREFETCH_PIDS+=($!)
    done <<< "$pr_data"

    # Don't wait - background jobs cleaned up via _prs_cleanup trap on exit
}
