# prs remove_queue mode - remove PR from merge queue
# shellcheck shell=bash

run_remove_queue() {
    local topic="$1"
    get_pr_or_fail "$topic" "remove_queue" "open" "number,title,url" || return 1
    pr_basics

    # Get the PR's GraphQL node ID and check if in merge queue
    local query_result
    query_result=$(gh api graphql -f query="{ repository(owner: \"${REPO_OWNER}\", name: \"${REPO_NAME}\") { pullRequest(number: ${PR_NUMBER}) { id, mergeQueueEntry { id } } } }")

    local pr_node_id
    pr_node_id=$(echo "$query_result" | jq -r '.data.repository.pullRequest.id // empty')

    if [[ -z "$pr_node_id" ]]; then
        echo -e "  ${CROSS} Failed to get PR node ID"
        return 1
    fi

    # Check if PR is in merge queue
    local queue_entry_id
    queue_entry_id=$(echo "$query_result" | jq -r '.data.repository.pullRequest.mergeQueueEntry.id // empty')

    if [[ -z "$queue_entry_id" ]]; then
        echo -e "${YELLOW}PR #${PR_NUMBER} is not in merge queue${NC}"
        echo -e "  ${PR_TITLE}"
        return 1
    fi

    echo -e "${BOLD}Removing from merge queue:${NC} #${PR_NUMBER} - ${PR_TITLE}"
    echo -e "  ${CYAN}${PR_URL}${NC}"

    # Remove from merge queue via GraphQL - uses PR node ID, not queue entry ID
    local result
    result=$(gh api graphql -f query="mutation { dequeuePullRequest(input: {id: \"${pr_node_id}\"}) { mergeQueueEntry { id } } }" 2>&1)

    if echo "$result" | grep -q '"mergeQueueEntry"'; then
        echo -e "  ${CHECK} Removed from merge queue"
        invalidate_pr_caches "$topic"
        return 0
    else
        local error_msg
        error_msg=$(echo "$result" | grep -o '"message":"[^"]*"' | cut -d'"' -f4 | head -1)
        echo -e "  ${CROSS} Failed to remove from merge queue"
        [[ -n "$error_msg" ]] && echo -e "  ${DIM}${error_msg}${NC}"
        return 1
    fi
}
