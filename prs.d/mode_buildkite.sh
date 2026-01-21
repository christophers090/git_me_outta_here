# prs buildkite mode - open Buildkite CI in browser
# shellcheck shell=bash

run_buildkite() {
    local topic="$1"
    get_pr_or_fail "$topic" "buildkite" "all" "number,title,statusCheckRollup" || return 1
    pr_basics

    local buildkite_url
    buildkite_url=$(echo "$PR_JSON" | jq -r ".[0].statusCheckRollup[]? | select(.context == \"${CI_CHECK_CONTEXT}\") | .targetUrl // empty" 2>/dev/null | head -1)

    if [[ -z "$buildkite_url" ]]; then
        echo -e "${RED}No Buildkite URL found for PR #${PR_NUMBER}:${NC} ${PR_TITLE}"
        return 1
    fi

    echo -e "${BOLD}Opening Buildkite for PR #${PR_NUMBER}:${NC} ${PR_TITLE}"
    echo -e "  ${CYAN}${buildkite_url}${NC}"

    open_url "$buildkite_url"
}
