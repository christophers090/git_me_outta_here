# prs queue_status mode - show all PRs in merge queue
# shellcheck shell=bash

run_queue_status() {
    local filter_topic="$1"

    # Query the actual merge queue via GraphQL
    # Use headCommit on the entry (not PR) to get the queue's CI run
    local queue_json
    local cache_key="queue"

    if cache_is_fresh "$cache_key" "$CACHE_TTL_QUEUE"; then
        queue_json=$(cache_get "$cache_key")
    else
        queue_json=$(gh api graphql -f query='
    {
      repository(owner: "'"$REPO_OWNER"'", name: "'"$REPO_NAME"'") {
        mergeQueue(branch: "main") {
          entries(first: 50) {
            nodes {
              enqueuedAt
              position
              headCommit {
                statusCheckRollup {
                  contexts(first: 50) {
                    nodes {
                      ... on StatusContext {
                        context
                        targetUrl
                        state
                      }
                    }
                  }
                }
              }
              pullRequest {
                number
                title
                headRefName
                url
                body
                author { login }
                reviewDecision
              }
            }
          }
        }
      }
    }' 2>/dev/null)
        if [[ -n "$queue_json" ]]; then
            cache_set "$cache_key" "$queue_json"
        fi
    fi

    local queue_count
    queue_count=$(echo "$queue_json" | jq '.data.repository.mergeQueue.entries.nodes | length')

    if [[ "$queue_count" -eq 0 || "$queue_count" == "null" ]]; then
        echo -e "${YELLOW}No PRs currently in merge queue${NC}"
        return 0
    fi

    echo -e "${BOLD}Merge Queue (${queue_count} PRs):${NC}"
    echo ""

    local now_epoch
    now_epoch=$(date +%s)

    # Process each entry using jq to output JSON, then parse in bash
    local entries
    entries=$(echo "$queue_json" | jq -c '.data.repository.mergeQueue.entries.nodes[]')

    while IFS= read -r entry; do
        local position number title url head_ref author review_decision enqueued_at bk_url topic

        position=$(echo "$entry" | jq -r '.position')
        number=$(echo "$entry" | jq -r '.pullRequest.number')
        title=$(echo "$entry" | jq -r '.pullRequest.title')
        url=$(echo "$entry" | jq -r '.pullRequest.url')
        head_ref=$(echo "$entry" | jq -r '.pullRequest.headRefName')
        author=$(echo "$entry" | jq -r '.pullRequest.author.login')
        review_decision=$(echo "$entry" | jq -r '.pullRequest.reviewDecision // "NONE"')
        enqueued_at=$(echo "$entry" | jq -r '.enqueuedAt')
        bk_url=$(echo "$entry" | jq -r '.headCommit.statusCheckRollup.contexts.nodes | map(select(.context == "'"$CI_CHECK_CONTEXT"'")) | .[0].targetUrl // empty')

        # Extract topic from body or branch name (case-insensitive)
        topic=$(echo "$entry" | jq -r '.pullRequest.body // ""' | grep -oiP 'Topic:\s*\K\S+' | head -1 || true)
        if [[ -z "$topic" ]]; then
            topic=$(echo "$head_ref" | rev | cut -d'/' -f1 | rev)
        fi

        # Calculate time in queue
        local time_in_queue=""
        if [[ -n "$enqueued_at" && "$enqueued_at" != "null" ]]; then
            local enqueued_epoch
            enqueued_epoch=$(date -d "$enqueued_at" +%s 2>/dev/null || echo "0")
            if [[ "$enqueued_epoch" -gt 0 ]]; then
                local diff_seconds=$((now_epoch - enqueued_epoch))
                time_in_queue=$(format_duration "$diff_seconds")
            fi
        fi

        # CI status - items in merge queue generally have passing CI
        local ci_sym="$CHECK"

        # Review status
        local review_sym="$CROSS"
        [[ "$review_decision" == "APPROVED" ]] && review_sym="$CHECK"

        echo -e "${ci_sym}|${review_sym} ${BOLD}#${number}:${NC} ${title}"
        echo -e "    ${DIM}Position:${NC} ${YELLOW}#${position}${NC}  ${DIM}Topic:${NC} ${topic}  ${DIM}Author:${NC} @${author}"
        if [[ -n "$time_in_queue" ]]; then
            echo -e "    ${DIM}In queue:${NC} ${YELLOW}${time_in_queue}${NC}"
        fi
        echo -e "    ${CYAN}${url}${NC}"
        if [[ -n "$bk_url" && "$bk_url" != "null" ]]; then
            echo -e "    ${DIM}CI:${NC} ${CYAN}${bk_url}${NC}"
        fi
        echo ""
    done <<< "$entries"
}
