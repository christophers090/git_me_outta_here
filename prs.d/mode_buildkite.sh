# prs buildkite mode - open Buildkite CI in browser
# shellcheck shell=bash

run_buildkite() {
    local topic="$1"
    get_build_pr_or_fail "$topic" "buildkite" || return 1
    local buildkite_url="$BK_BUILD_URL"

    if [[ -z "$buildkite_url" ]]; then
        echo -e "${RED}No Buildkite URL found for PR #${PR_NUMBER}:${NC} ${PR_TITLE}"
        return 1
    fi

    echo -e "${BOLD}Opening Buildkite for PR #${PR_NUMBER}:${NC} ${PR_TITLE}"
    echo -e "  ${CYAN}${buildkite_url}${NC}"

    open_url "$buildkite_url"
}
