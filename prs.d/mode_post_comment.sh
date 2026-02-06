# prs post_comment mode - post an inline comment on a specific line
# shellcheck shell=bash

run_post_comment() {
    local topic="$1"
    local file_line="${2:-}"

    require_topic "post_comment" "$topic" || return 1

    # Validate file:line argument
    if [[ -z "$file_line" ]]; then
        echo -e "${RED}Error:${NC} File and line number required"
        echo "Usage: prs --pc <topic> <file>:<line>"
        return 1
    fi

    if [[ "$file_line" != *:* ]]; then
        echo -e "${RED}Error:${NC} Invalid format '${file_line}', expected <file>:<line>"
        return 1
    fi

    local file_path="${file_line%%:*}"
    local line_number="${file_line##*:}"

    if [[ -z "$file_path" || -z "$line_number" ]]; then
        echo -e "${RED}Error:${NC} Invalid format '${file_line}', expected <file>:<line>"
        return 1
    fi

    if ! [[ "$line_number" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error:${NC} Line number must be a positive integer, got '${line_number}'"
        return 1
    fi

    # Show prompt immediately, start PR lookup in background
    echo -e "${BOLD}Comment on ${file_path}:${line_number}${NC}"
    echo -e "${DIM}Enter your comment (press Enter, then Ctrl+D when done):${NC}"

    # Start PR lookup + commit SHA fetch in background
    local tmp_file
    tmp_file=$(mktemp)
    (
        local pr_json
        pr_json=$(cached_find_pr "$topic" "all" "number,title")
        if ! pr_exists "$pr_json"; then
            echo "ERROR:PR_NOT_FOUND" > "$tmp_file"
            exit 1
        fi
        local number title
        number=$(pr_field "$pr_json" "number")
        title=$(pr_field "$pr_json" "title")

        # Get head commit SHA
        local commit_sha
        commit_sha=$(gh pr view "$number" -R "$REPO" --json commits -q '.commits[-1].oid' 2>/dev/null)
        if [[ -z "$commit_sha" ]]; then
            echo "ERROR:NO_COMMIT_SHA" > "$tmp_file"
            exit 1
        fi

        echo "${number}:${title}:${commit_sha}" > "$tmp_file"
    ) &
    local bg_pid=$!

    # Collect comment body while lookup happens
    local body
    body=$(cat)
    echo ""

    if [[ -z "$body" ]]; then
        kill "$bg_pid" 2>/dev/null
        rm -f "$tmp_file"
        echo -e "${RED}Error:${NC} Comment cannot be empty"
        return 1
    fi

    # Wait for lookup to complete
    wait "$bg_pid"

    # Check lookup result
    local lookup_result
    lookup_result=$(cat "$tmp_file")
    rm -f "$tmp_file"

    if [[ "$lookup_result" == "ERROR:PR_NOT_FOUND" ]]; then
        pr_not_found "$topic"
        return 1
    elif [[ "$lookup_result" == "ERROR:NO_COMMIT_SHA" ]]; then
        echo -e "${CROSS} Failed to get commit SHA for PR"
        return 1
    fi

    # Parse: number:title:commit_sha
    local pr_number="${lookup_result%%:*}"
    local rest="${lookup_result#*:}"
    local pr_title="${rest%%:*}"
    local commit_sha="${rest##*:}"

    # Post inline comment via REST API
    if gh api "repos/${REPO}/pulls/${pr_number}/comments" \
        -f body="$body" \
        -f commit_id="$commit_sha" \
        -f path="$file_path" \
        -F line="$line_number" \
        -f side="RIGHT" \
        --silent 2>/dev/null; then
        echo -e "${CHECK} Comment posted on ${file_path}:${line_number} (PR #${pr_number})"
    else
        echo -e "${CROSS} Failed to post comment on ${file_path}:${line_number}"
        return 1
    fi
}
