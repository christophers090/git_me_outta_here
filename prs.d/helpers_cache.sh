# prs cache helpers - caching layer for API responses
# shellcheck shell=bash

# Cache configuration
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/prs"
CACHE_TTL_OUTSTANDING=60  # seconds
CACHE_TTL_STATUS=30       # seconds

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
    local key="$1"
    local data="$2"
    cache_init
    echo "$data" > "$CACHE_DIR/${key}.json"
    date +%s > "$CACHE_DIR/${key}.ts"
}

# Check if cache is fresh (within TTL)
# Returns: 0 if fresh, 1 if stale/missing
cache_is_fresh() {
    local key="$1"
    local ttl="$2"
    local ts_file="$CACHE_DIR/${key}.ts"
    local cache_file="$CACHE_DIR/${key}.json"

    [[ -f "$cache_file" && -f "$ts_file" ]] || return 1

    local cached_time now age
    cached_time=$(cat "$ts_file")
    now=$(date +%s)
    age=$((now - cached_time))

    [[ $age -lt $ttl ]]
}

# Get cache age in seconds (or -1 if no cache)
cache_age() {
    local key="$1"
    local ts_file="$CACHE_DIR/${key}.ts"

    if [[ -f "$ts_file" ]]; then
        local cached_time now
        cached_time=$(cat "$ts_file")
        now=$(date +%s)
        echo $((now - cached_time))
    else
        echo -1
    fi
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

# Render output with cache-then-refresh pattern
# Args:
#   $1 - cache_key
#   $2 - ttl in seconds
#   $3 - fetch command (string to eval)
#   $4 - render function name (called with JSON as $1)
#
# Flow:
#   - If cached: render cached, show "refreshing", fetch, update display
#   - If no cache: show spinner, fetch, render
render_with_refresh() {
    local cache_key="$1"
    local ttl="$2"
    local fetch_cmd="$3"
    local render_fn="$4"

    local cached_json fresh_json
    local cached_output fresh_output
    local line_count

    # Check for cached data (even if stale, for display)
    cached_json=$(cache_get "$cache_key")

    if [[ -n "$cached_json" ]] && is_interactive; then
        # Have cache - show it immediately, then refresh
        cached_output=$("$render_fn" "$cached_json")
        line_count=$(echo "$cached_output" | wc -l)

        # Print cached output
        echo "$cached_output"
        echo -e "${DIM}⟳ Refreshing...${NC}"

        # Fetch fresh data
        fresh_json=$(eval "$fetch_cmd" 2>/dev/null) || fresh_json=""

        if [[ -n "$fresh_json" ]]; then
            cache_set "$cache_key" "$fresh_json"
            fresh_output=$("$render_fn" "$fresh_json")
        else
            # API failed - keep showing cached
            fresh_output="$cached_output"
        fi

        # Move cursor up and clear (cached output + refreshing line)
        tput cuu $((line_count + 1)) 2>/dev/null || true
        tput ed 2>/dev/null || true

        # Print fresh output
        echo "$fresh_output"

        # Show status
        if [[ "$cached_output" != "$fresh_output" ]]; then
            echo -e "${DIM}↻ Updated${NC}"
        else
            echo -e "${DIM}✓ Up to date${NC}"
        fi

        # Return the fresh JSON for further processing
        echo "$fresh_json"
    else
        # No cache or non-interactive - fetch with spinner
        if is_interactive; then
            show_spinner "Fetching..." &
            local spinner_pid=$!
            fresh_json=$(eval "$fetch_cmd" 2>/dev/null) || fresh_json=""
            stop_spinner "$spinner_pid"
        else
            # Non-interactive (piped) - just fetch quietly
            fresh_json=$(eval "$fetch_cmd" 2>/dev/null) || fresh_json=""
        fi

        if [[ -n "$fresh_json" ]]; then
            cache_set "$cache_key" "$fresh_json"
            "$render_fn" "$fresh_json"
        else
            echo -e "${RED}Failed to fetch data${NC}" >&2
            return 1
        fi

        echo "$fresh_json"
    fi
}

# Background prefetch status for all open PRs
# Called after outstanding list is fetched
prefetch_status_all() {
    local prs_json="$1"

    # Don't prefetch if non-interactive or no data
    is_interactive || return 0
    [[ -n "$prs_json" ]] || return 0

    # Extract topics from PR JSON
    local topics
    topics=$(echo "$prs_json" | jq -r '
        .[] |
        ((.body | capture("Topic:\\s*(?<t>\\S+)") | .t) // (.headRefName | split("/") | last))
    ' 2>/dev/null) || return 0

    # Spawn background jobs to prefetch each PR's detailed status
    local topic
    while IFS= read -r topic; do
        [[ -z "$topic" || "$topic" == "null" ]] && continue

        # Skip if we have fresh cache
        cache_is_fresh "status_${topic}" "$CACHE_TTL_STATUS" && continue

        # Background fetch - find and cache the full PR data
        (
            local branch_pattern="${BRANCH_USER}/${BRANCH_PREFIX}/${topic}"
            local status_json
            status_json=$(gh pr list -R "$REPO" --author "$GITHUB_USER" --state all \
                --head "$branch_pattern" \
                --json number,title,state,url,reviewDecision,reviewRequests,latestReviews,statusCheckRollup,autoMergeRequest,mergeStateStatus,labels,isDraft \
                2>/dev/null)

            if [[ -n "$status_json" && "$(echo "$status_json" | jq 'length')" -gt 0 ]]; then
                cache_set "status_${topic}" "$status_json"
            fi
        ) &
    done <<< "$topics"

    # Don't wait for background jobs - let them complete on their own
}
