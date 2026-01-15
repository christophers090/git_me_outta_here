# helpers_comments.sh - Comment-specific helper functions
# shellcheck shell=bash

# Get count of unresolved review threads
# Usage: get_unresolved_count <pr_number>
# Returns: number of unresolved threads
get_unresolved_count() {
    local pr_number="$1"

    local graphql_query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          reviewThreads(first: 100) {
            nodes {
              isResolved
            }
          }
        }
      }
    }'

    gh api graphql \
        -f query="$graphql_query" \
        -f owner="$REPO_OWNER" \
        -f repo="$REPO_NAME" \
        -F number="$pr_number" 2>/dev/null \
    | jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length'
}

# Get comments in display order (roots first, then their replies per root)
# Usage: get_ordered_comments <pr_number>
# Returns: JSON array of comments in display order
get_ordered_comments() {
    local pr_number="$1"
    gh api "repos/${REPO}/pulls/${pr_number}/comments" 2>/dev/null | jq '
        [.[] | select(.in_reply_to_id == null)] as $roots |
        . as $all |
        [
            $roots[] |
            . as $root |
            $root,
            ($all | map(select(.in_reply_to_id == $root.id)))[]
        ]
    '
}

# Get comment info by display number
# Usage: get_comment_info <pr_number> <comment_num>
# Returns: "comment_id:root_id" or empty if not found
# root_id equals comment_id for root comments, or parent id for replies
get_comment_info() {
    local pr_number="$1"
    local comment_num="$2"
    get_ordered_comments "$pr_number" | jq -r --argjson n "$comment_num" '
        .[$n - 1] | "\(.id):\(.in_reply_to_id // .id)"
    '
}

# Add thumbs up reaction to a comment
# Usage: thumbsup_comment <comment_id> <display_num>
# Returns: 0 success, 1 failure
thumbsup_comment() {
    local comment_id="$1"
    local display_num="$2"
    if gh api "repos/${REPO}/pulls/comments/${comment_id}/reactions" \
        -f content="+1" >/dev/null 2>&1; then
        echo -e "${CHECK} Added thumbs up to comment #${display_num}"
        return 0
    else
        echo -e "${CROSS} Failed to add reaction"
        return 1
    fi
}

# Resolve a review thread by root comment ID
# Usage: resolve_thread <pr_number> <root_comment_id> <display_num>
# Returns: 0 success, 1 failure
resolve_thread() {
    local pr_number="$1"
    local root_id="$2"
    local display_num="$3"

    local graphql_query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          reviewThreads(first: 100) {
            nodes {
              id
              isResolved
              comments(first: 1) {
                nodes { databaseId }
              }
            }
          }
        }
      }
    }'

    local threads_json
    threads_json=$(gh api graphql \
        -f query="$graphql_query" \
        -f owner="$REPO_OWNER" \
        -f repo="$REPO_NAME" \
        -F number="$pr_number" 2>/dev/null)

    if [[ -z "$threads_json" ]]; then
        echo -e "${CROSS} Failed to fetch review threads"
        return 1
    fi

    local thread_id
    thread_id=$(echo "$threads_json" | jq -r --arg cid "$root_id" '
        .data.repository.pullRequest.reviewThreads.nodes[]
        | select(.comments.nodes[0].databaseId == ($cid | tonumber))
        | .id' 2>/dev/null)

    if [[ -z "$thread_id" ]]; then
        echo -e "${CROSS} Could not find review thread for comment #${display_num}"
        return 1
    fi

    local is_resolved
    is_resolved=$(echo "$threads_json" | jq -r --arg cid "$root_id" '
        .data.repository.pullRequest.reviewThreads.nodes[]
        | select(.comments.nodes[0].databaseId == ($cid | tonumber))
        | .isResolved' 2>/dev/null)

    if [[ "$is_resolved" == "true" ]]; then
        echo -e "${DIM}Thread #${display_num} already resolved${NC}"
        return 0
    fi

    local resolve_mutation='
    mutation($threadId: ID!) {
      resolveReviewThread(input: {threadId: $threadId}) {
        thread { isResolved }
      }
    }'

    if gh api graphql \
        -f query="$resolve_mutation" \
        -f threadId="$thread_id" >/dev/null 2>&1; then
        echo -e "${CHECK} Resolved thread #${display_num}"
        return 0
    else
        echo -e "${CROSS} Failed to resolve thread"
        return 1
    fi
}

# Post a reply to a comment
# Usage: reply_to_comment <pr_number> <comment_id> <display_num> <body>
# Returns: 0 success, 1 failure
reply_to_comment() {
    local pr_number="$1"
    local comment_id="$2"
    local display_num="$3"
    local body="$4"

    echo -e "${DIM}Posting reply...${NC}"
    if gh api "repos/${REPO}/pulls/${pr_number}/comments/${comment_id}/replies" \
        -f body="$body" >/dev/null 2>&1; then
        echo -e "${CHECK} Reply posted to comment #${display_num}"
        return 0
    else
        echo -e "${CROSS} Failed to post reply"
        return 1
    fi
}
