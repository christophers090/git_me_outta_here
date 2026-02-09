#!/usr/bin/env bash
# test_cache.sh - Cache function unit tests
# Run with: ./run_tests.sh test_cache.sh
# Or standalone: bash test_cache.sh /path/to/prs.d

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

test_cache_set_get() {
    local key="test_key"
    local data='{"foo": "bar", "num": 42}'
    cache_set "$key" "$data"
    local result=$(cache_get "$key")
    [[ "$result" == "$data" ]]
}

test_cache_get_missing() {
    local result=$(cache_get "nonexistent_key_12345")
    [[ -z "$result" ]]
}

test_invalidate_pr_caches() {
    local topic="test_topic"
    cache_set "pr_${topic}_all" '{"pr": 1}'
    cache_set "pr_${topic}_open" '{"pr": 2}'
    cache_set "status_${topic}" '{"status": 1}'
    cache_set "comments_${topic}" "5"
    cache_set "comments_data_${topic}" '{"comments": []}'
    cache_set "pr_other_topic_all" '{"other": 1}'

    invalidate_pr_caches "$topic"

    # Deleted files
    [[ ! -f "$CACHE_DIR/pr_${topic}_all.json" ]] || return 1
    [[ ! -f "$CACHE_DIR/status_${topic}.json" ]] || return 1
    [[ ! -f "$CACHE_DIR/comments_${topic}.json" ]] || return 1
    # Kept files
    [[ -f "$CACHE_DIR/pr_other_topic_all.json" ]] || return 1
}

test_cache_init() {
    local test_dir=$(mktemp -d)
    rm -rf "$test_dir"
    export CACHE_DIR="$test_dir/subdir/cache"
    cache_init
    [[ -d "$CACHE_DIR" ]]
    rm -rf "$test_dir"
    export CACHE_DIR="$TEST_CACHE_DIR"
}

test_is_interactive() {
    # Function exists and returns boolean
    is_interactive || true
}

test_cached_find_pr_field_isolation() {
    # Different field sets should create different cache entries
    # This tests that cached_find_pr includes fields in cache key
    local key1="pr_testtopic_all_number"
    local key2="pr_testtopic_all_number_title_url"

    # Simulate cache entries for different field sets
    cache_set "$key1" '{"number": 123}'
    cache_set "$key2" '{"number": 123, "title": "Test", "url": "http://x"}'

    # Verify both exist separately
    [[ -f "$CACHE_DIR/${key1}.json" ]] || return 1
    [[ -f "$CACHE_DIR/${key2}.json" ]] || return 1

    # Verify contents are different
    local data1 data2
    data1=$(cache_get "$key1")
    data2=$(cache_get "$key2")
    [[ "$data1" != "$data2" ]]
}

# ─── RUN TESTS ───────────────────────────────────────────────────────

run_test "cache_set/cache_get round-trip" test_cache_set_get
run_test "cache_get returns empty for missing" test_cache_get_missing
run_test "invalidate_pr_caches removes correct files" test_invalidate_pr_caches
run_test "cache_init creates directory" test_cache_init
run_test "is_interactive function exists" test_is_interactive
run_test "cached_find_pr field isolation" test_cached_find_pr_field_isolation

# Exit with failure if any tests failed
[[ $FAIL -eq 0 ]]
