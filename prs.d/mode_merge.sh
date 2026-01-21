# prs merge mode - add PR to merge queue
# shellcheck shell=bash

run_merge() {
    local topic="$1"
    get_pr_or_fail "$topic" "merge" "open" "number,title,baseRefName,url" || return 1
    pr_basics
    local base
    base=$(pr_field "$PR_JSON" "baseRefName")

    # SAFETY: Only allow merging to main
    if [[ "$base" != "main" ]]; then
        echo -e "${RED}ERROR:${NC} PR #${PR_NUMBER} targets '${base}', not 'main'"
        echo -e "  ${DIM}Only PRs targeting main can be merged${NC}"
        echo -e "  ${DIM}Title: ${PR_TITLE}${NC}"
        return 1
    fi

    echo -e "${BOLD}Adding to merge queue:${NC} #${PR_NUMBER} - ${PR_TITLE}"
    echo -e "  ${CYAN}${PR_URL}${NC}"

    # Get the PR's GraphQL node ID
    local pr_node_id
    pr_node_id=$(gh api graphql -f query="{ repository(owner: \"${REPO_OWNER}\", name: \"${REPO_NAME}\") { pullRequest(number: ${PR_NUMBER}) { id } } }" --jq '.data.repository.pullRequest.id')

    if [[ -z "$pr_node_id" ]]; then
        echo -e "  ${CROSS} Failed to get PR node ID"
        return 1
    fi

    # Add to merge queue via GraphQL
    local result
    result=$(gh api graphql -f query="mutation { enqueuePullRequest(input: {pullRequestId: \"${pr_node_id}\"}) { mergeQueueEntry { id position } } }" 2>&1)

    if echo "$result" | grep -q '"mergeQueueEntry"'; then
        local position
        position=$(echo "$result" | grep -o '"position":[0-9]*' | cut -d: -f2)
        echo -e "  ${CHECK} Added to merge queue (position ${position})"
        invalidate_pr_caches "$topic"
        return 0
    else
        local error_msg
        error_msg=$(echo "$result" | grep -o '"message":"[^"]*"' | cut -d'"' -f4 | head -1)
        echo -e "  ${CROSS} Failed to add to merge queue"
        [[ -n "$error_msg" ]] && echo -e "  ${DIM}${error_msg}${NC}"
        return 1
    fi
}
