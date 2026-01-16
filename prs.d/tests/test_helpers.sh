#!/usr/bin/env bash
# test_helpers.sh - Helper function unit tests
# Run with: ./run_tests.sh test_helpers.sh

set -euo pipefail

PRS_DIR="${1:-$(dirname "$(dirname "$(realpath "$0")")")}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Test counters
PASS=0
FAIL=0

# Source dependencies
source "$PRS_DIR/config.sh"
export GITHUB_USER="testuser"
export BRANCH_USER="testuser"
export REPO="test/repo"
export REPO_OWNER="test"
export REPO_NAME="repo"
export BRANCH_PREFIX="revup/main"
export CI_CHECK_CONTEXT="buildkite/test"
source "$PRS_DIR/helpers_cache.sh"
source "$PRS_DIR/helpers.sh"

# Create test cache dir
TEST_CACHE_DIR=$(mktemp -d)
export CACHE_DIR="$TEST_CACHE_DIR"
trap 'rm -rf "$TEST_CACHE_DIR"' EXIT

# Test helper
run_test() {
    local name="$1"
    shift
    if "$@"; then
        echo -e "  ${GREEN}✓${NC} $name"
        ((++PASS))
    else
        echo -e "  ${RED}✗${NC} $name"
        ((++FAIL))
    fi
}

# ─── TESTS ───────────────────────────────────────────────────────────

test_pr_exists_valid() {
    local pr_json='[{"number": 123, "title": "Test PR"}]'
    pr_exists "$pr_json"
}

test_pr_exists_empty() {
    local pr_json='[]'
    ! pr_exists "$pr_json"
}

test_pr_exists_null() {
    ! pr_exists ""
}

test_pr_field_extracts() {
    local pr_json='[{"number": 456, "title": "My PR Title", "url": "https://github.com/test"}]'
    local number=$(pr_field "$pr_json" "number")
    local title=$(pr_field "$pr_json" "title")
    local url=$(pr_field "$pr_json" "url")
    [[ "$number" == "456" ]] && [[ "$title" == "My PR Title" ]] && [[ "$url" == "https://github.com/test" ]]
}

test_pr_field_missing() {
    local pr_json='[{"number": 123}]'
    local result=$(pr_field "$pr_json" "nonexistent")
    [[ -z "$result" || "$result" == "null" ]]
}

test_require_topic_valid() {
    require_topic "test_mode" "valid-topic" 2>/dev/null
}

test_require_topic_empty() {
    ! require_topic "test_mode" "" 2>/dev/null
}

test_format_duration_seconds() {
    local result=$(format_duration 45)
    [[ "$result" == "45s" ]]
}

test_format_duration_minutes() {
    local result=$(format_duration 125)
    [[ "$result" == "2m 5s" ]]
}

test_format_duration_hours() {
    local result=$(format_duration 3725)
    [[ "$result" == "1h 2m" ]]
}

# ─── RUN TESTS ───────────────────────────────────────────────────────

run_test "pr_exists with valid JSON" test_pr_exists_valid
run_test "pr_exists with empty array" test_pr_exists_empty
run_test "pr_exists with empty string" test_pr_exists_null
run_test "pr_field extracts values" test_pr_field_extracts
run_test "pr_field with missing field" test_pr_field_missing
run_test "require_topic with valid topic" test_require_topic_valid
run_test "require_topic with empty topic" test_require_topic_empty
run_test "format_duration seconds" test_format_duration_seconds
run_test "format_duration minutes" test_format_duration_minutes
run_test "format_duration hours" test_format_duration_hours

# Exit with failure if any tests failed
[[ $FAIL -eq 0 ]]
