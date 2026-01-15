# prs status mode - detailed PR status
# shellcheck shell=bash

run_status() {
    local topic="$1"

    # No topic: list all open PRs
    if [[ -z "$topic" ]]; then
        echo -e "${BOLD}Your open PRs:${NC}"
        gh pr list -R "$REPO" --author "$GITHUB_USER" --state open
        return 0
    fi

    local pr_json
    pr_json=$(find_pr "$topic" "all" "number,title,state,url,reviewDecision,reviewRequests,latestReviews,statusCheckRollup,autoMergeRequest,mergeStateStatus,labels,isDraft")

    if ! pr_exists "$pr_json"; then
        echo -e "${RED}No PR found for topic:${NC} $topic"
        echo ""
        # Try to find similar topics
        local similar
        similar=$(gh pr list -R "$REPO" --author "$GITHUB_USER" --state open --json headRefName,number,title 2>/dev/null \
            | jq -r --arg topic "$topic" '.[] | select(.headRefName | ascii_downcase | contains($topic | ascii_downcase)) | (.headRefName | split("/") | last) as $t | "  \($t) - #\(.number): \(.title)"' 2>/dev/null || true)

        if [[ -n "$similar" ]]; then
            echo -e "${YELLOW}Similar topics:${NC}"
            echo "$similar"
        else
            echo -e "${BOLD}Your open PRs:${NC}"
            gh pr list -R "$REPO" --author "$GITHUB_USER" --state open
        fi
        return 1
    fi

    # Extract PR data
    local pr number title state url review_decision merge_state is_draft auto_merge
    pr=$(echo "$pr_json" | jq '.[0]')
    number=$(echo "$pr" | jq -r '.number')
    title=$(echo "$pr" | jq -r '.title')
    state=$(echo "$pr" | jq -r '.state')
    url=$(echo "$pr" | jq -r '.url')
    review_decision=$(echo "$pr" | jq -r '.reviewDecision // "NONE"')
    merge_state=$(echo "$pr" | jq -r '.mergeStateStatus // "UNKNOWN"')
    is_draft=$(echo "$pr" | jq -r '.isDraft')
    auto_merge=$(echo "$pr" | jq -r 'if .autoMergeRequest != null then "Yes" else "No" end')

    # Get Buildkite URL from status checks
    local buildkite_url
    buildkite_url=$(echo "$pr" | jq -r ".statusCheckRollup[]? | select(.context == \"${CI_CHECK_CONTEXT}\") | .targetUrl // empty" 2>/dev/null | head -1)

    # Header
    echo -e "${BOLD}${BLUE}PR #${number}:${NC} ${title}"
    echo -e "URL: ${CYAN}${url}${NC}"
    if [[ -n "$buildkite_url" ]]; then
        echo -e "CI:  ${CYAN}${buildkite_url}${NC}"
    fi
    echo -e "State: ${state}$(if [[ "$is_draft" == "true" ]]; then echo -e " ${YELLOW}(Draft)${NC}"; fi)"
    echo ""

    # CI Status section
    echo -e "${BOLD}CI Status:${NC}"
    local checks passed failed pending total
    checks=$(echo "$pr" | jq -r '.statusCheckRollup // []')
    if [[ "$checks" == "[]" ]] || [[ -z "$checks" ]]; then
        echo "  No CI checks found"
    else
        passed=$(echo "$pr" | jq '[.statusCheckRollup[] | select(.state == "SUCCESS")] | length')
        failed=$(echo "$pr" | jq '[.statusCheckRollup[] | select(.state == "FAILURE" or .state == "ERROR")] | length')
        pending=$(echo "$pr" | jq '[.statusCheckRollup[] | select(.state == "PENDING" or .state == "EXPECTED")] | length')
        total=$(echo "$pr" | jq '.statusCheckRollup | length')

        if [[ "$failed" -gt 0 ]]; then
            echo -e "  ${RED}${failed} failed${NC}, ${GREEN}${passed} passed${NC}, ${YELLOW}${pending} pending${NC} (${total} total)"
            echo ""
            echo -e "  ${RED}Failed:${NC}"
            echo "$pr" | jq -r '.statusCheckRollup[] | select(.state == "FAILURE" or .state == "ERROR") | "    \(.context // .name)"'
        elif [[ "$pending" -gt 0 ]]; then
            echo -e "  ${GREEN}${passed} passed${NC}, ${YELLOW}${pending} pending${NC} (${total} total)"
            echo ""
            echo -e "  ${YELLOW}Pending:${NC}"
            echo "$pr" | jq -r '.statusCheckRollup[] | select(.state == "PENDING" or .state == "EXPECTED") | "    \(.context // .name)"'
        else
            echo -e "  ${GREEN}All ${passed} checks passed${NC}"
        fi
    fi
    echo ""

    # Reviews section
    echo -e "${BOLD}Reviews:${NC}"
    case "$review_decision" in
        "APPROVED")
            echo -e "  Status: ${GREEN}APPROVED${NC}"
            ;;
        "CHANGES_REQUESTED")
            echo -e "  Status: ${RED}CHANGES REQUESTED${NC}"
            ;;
        "REVIEW_REQUIRED")
            echo -e "  Status: ${YELLOW}REVIEW REQUIRED${NC}"
            ;;
        *)
            echo -e "  Status: ${review_decision}"
            ;;
    esac

    local pending_reviewers approvers change_requesters
    pending_reviewers=$(echo "$pr" | jq -r '.reviewRequests[] | if .name then "@\(.slug // .name)" else "@\(.login)" end' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    if [[ -n "$pending_reviewers" ]]; then
        echo -e "  Pending: ${YELLOW}${pending_reviewers}${NC}"
    fi

    approvers=$(echo "$pr" | jq -r '.latestReviews[] | select(.state == "APPROVED") | "@\(.author.login)"' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    if [[ -n "$approvers" ]]; then
        echo -e "  Approved by: ${GREEN}${approvers}${NC}"
    fi

    change_requesters=$(echo "$pr" | jq -r '.latestReviews[] | select(.state == "CHANGES_REQUESTED") | "@\(.author.login)"' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    if [[ -n "$change_requesters" ]]; then
        echo -e "  Changes requested by: ${RED}${change_requesters}${NC}"
    fi
    echo ""

    # Merge Status section
    echo -e "${BOLD}Merge Status:${NC}"
    case "$merge_state" in
        "CLEAN")
            echo -e "  State: ${GREEN}Ready to merge${NC}"
            ;;
        "BLOCKED")
            echo -e "  State: ${RED}BLOCKED${NC}"
            ;;
        "BEHIND")
            echo -e "  State: ${YELLOW}Behind base branch${NC}"
            ;;
        "UNSTABLE")
            echo -e "  State: ${YELLOW}Unstable (some checks failing)${NC}"
            ;;
        "HAS_HOOKS")
            echo -e "  State: ${YELLOW}Waiting for merge hooks${NC}"
            ;;
        *)
            echo -e "  State: ${merge_state}"
            ;;
    esac
    echo -e "  Merge-when-ready: ${auto_merge}"

    local has_mwr_label
    has_mwr_label=$(echo "$pr" | jq -r '.labels[] | select(.name | ascii_downcase | contains("merge")) | .name' 2>/dev/null | head -1)
    if [[ -n "$has_mwr_label" ]]; then
        echo -e "  Label: ${CYAN}${has_mwr_label}${NC}"
    fi
}
