# prs buildkite mode - open Buildkite CI in browser
# shellcheck shell=bash

run_buildkite() {
    local topic="$1"
    require_topic "buildkite" "$topic" || return 1

    local pr_json
    pr_json=$(cached_find_pr "$topic" "all" "number,title,statusCheckRollup")

    if ! pr_exists "$pr_json"; then
        pr_not_found "$topic"
        return 1
    fi

    local number title buildkite_url
    number=$(pr_field "$pr_json" "number")
    title=$(pr_field "$pr_json" "title")
    buildkite_url=$(echo "$pr_json" | jq -r ".[0].statusCheckRollup[]? | select(.context == \"${CI_CHECK_CONTEXT}\") | .targetUrl // empty" 2>/dev/null | head -1)

    if [[ -z "$buildkite_url" ]]; then
        echo -e "${RED}No Buildkite URL found for PR #${number}:${NC} ${title}"
        return 1
    fi

    echo -e "${BOLD}Opening Buildkite for PR #${number}:${NC} ${title}"
    echo -e "  ${CYAN}${buildkite_url}${NC}"

    open_url "$buildkite_url"
}
