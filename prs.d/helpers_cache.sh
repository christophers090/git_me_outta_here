# prs cache helpers - caching layer for API responses
# shellcheck shell=bash

# Cache configuration
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/prs"
# TTL constants defined in config.sh

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

# Cached wrapper for find_pr - avoids repeated API calls
# Usage: cached_find_pr <topic> [state] [fields]
# Returns: cached PR JSON if fresh, otherwise fetches and caches
cached_find_pr() {
    local topic="$1"
    local state="${2:-all}"
    local fields="${3:-number,title,url}"
    # Include fields in cache key to avoid returning incomplete data
    local fields_hash="${fields//,/_}"
    local cache_key="pr_${topic}_${state}_${fields_hash}"

    # Return from cache if fresh
    if cache_is_fresh "$cache_key" "$CACHE_TTL_PR_LOOKUP"; then
        cache_get "$cache_key"
        return 0
    fi

    # Fetch fresh data using the original find_pr
    local result
    result=$(find_pr "$topic" "$state" "$fields")

    # Cache if we got valid results
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

# Background prefetch status AND comments for all open PRs
# Called after outstanding list is fetched - makes subsequent prs <topic> and prs -c <topic> instant
# Completely non-blocking - spawns background jobs and returns immediately
prefetch_all_pr_data() {
    local prs_json="$1"

    # Don't prefetch if non-interactive or no data
    is_interactive || return 0
    [[ -n "$prs_json" ]] || return 0

    # Extract topics and PR numbers from JSON
    local pr_data
    pr_data=$(echo "$prs_json" | jq -r '
        .[] |
        ((.body | capture("Topic:\\s*(?<t>\\S+)") | .t) // (.headRefName | split("/") | last)) as $topic |
        "\(.number)|\($topic)|\(.title)|\(.url)"
    ' 2>/dev/null) || return 0

    # Spawn background jobs to prefetch each PR's data
    while IFS='|' read -r number topic title url; do
        [[ -z "$topic" || "$topic" == "null" ]] && continue

        # Check if both caches are fresh - skip if so
        local need_status="" need_comments=""
        cache_is_fresh "status_${topic}" "$CACHE_TTL_STATUS" || need_status=1
        cache_is_fresh "comments_data_${topic}" "$CACHE_TTL_COMMENTS" || need_comments=1

        [[ -z "$need_status" && -z "$need_comments" ]] && continue

        # Spawn background job for this PR
        (
            # Prefetch status if needed
            if [[ -n "$need_status" ]]; then
                local branch_pattern="${BRANCH_USER}/${BRANCH_PREFIX}/${topic}"
                local status_json
                status_json=$(gh pr list -R "$REPO" --author "$GITHUB_USER" --state all \
                    --head "$branch_pattern" \
                    --json number,title,state,url,reviewDecision,reviewRequests,latestReviews,statusCheckRollup,autoMergeRequest,mergeStateStatus,labels,isDraft \
                    2>/dev/null)

                if [[ -n "$status_json" && "$(echo "$status_json" | jq 'length')" -gt 0 ]]; then
                    cache_set "status_${topic}" "$status_json"
                fi
            fi

            # Prefetch comments if needed
            if [[ -n "$need_comments" && -n "$number" ]]; then
                local comments_json resolution_status
                comments_json=$(get_ordered_comments "$number" 2>/dev/null)
                resolution_status=$(fetch_thread_resolution_status "$number" 2>/dev/null)

                if [[ -n "$comments_json" && -n "$resolution_status" ]]; then
                    # Build full comments data structure
                    local data
                    data=$(jq -n \
                        --argjson number "$number" \
                        --arg title "$title" \
                        --arg url "$url" \
                        --argjson comments "$comments_json" \
                        --argjson resolution "$resolution_status" \
                        '{number: $number, title: $title, url: $url, comments: $comments, resolution: $resolution}')

                    cache_set "comments_data_${topic}" "$data"

                    # Also cache unresolved count for status display
                    local unresolved_count
                    unresolved_count=$(echo "$resolution_status" | jq '[to_entries[] | select(.value == false)] | length')
                    cache_set "comments_${topic}" "$unresolved_count"
                fi
            fi
        ) &>/dev/null &
    done <<< "$pr_data"

    # Don't wait - let background jobs complete on their own
}

# Alias for backwards compatibility
prefetch_status_all() {
    prefetch_all_pr_data "$@"
}
