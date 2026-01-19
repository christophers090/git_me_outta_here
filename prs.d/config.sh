# prs configuration - sourced by main script
# shellcheck shell=bash

# Source local config if it exists (gitignored)
_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$_CONFIG_DIR/config.local.sh" ]] && source "$_CONFIG_DIR/config.local.sh"
unset _CONFIG_DIR

# User configuration - set these environment variables or use -u flag
GITHUB_USER="${GITHUB_USER:-}"
BRANCH_USER="${BRANCH_USER:-}"
REPO="${PRS_REPO:-}"
REPO_OWNER="${REPO%%/*}"
REPO_NAME="${REPO##*/}"

# Path patterns
BRANCH_PREFIX="${PRS_BRANCH_PREFIX:-revup/main}"
CI_CHECK_CONTEXT="${PRS_CI_CHECK_CONTEXT:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Symbols
CHECK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"

# Cache TTLs (seconds)
# These values balance responsiveness with API rate limits.
# Shorter TTLs = fresher data but more API calls
# Longer TTLs = faster responses but potentially stale data
#
# OUTSTANDING: List of open PRs. 60s is reasonable since new PRs are rare.
# STATUS: Individual PR details. 30s catches CI updates reasonably quickly.
# PR_LOOKUP: find_pr results. 30s matches STATUS since they're often used together.
# COMMENTS: Review thread data. 120s since comments change less frequently.
# BUILDKITE: CI job status. 30s balances freshness with API load.
# QUEUE: Merge queue position. 15s for quicker feedback during active merges.
# MERGED/CLOSED: Historical data. Longer TTLs since these rarely change.
CACHE_TTL_OUTSTANDING=60
CACHE_TTL_STATUS=30
CACHE_TTL_PR_LOOKUP=30
CACHE_TTL_COMMENTS=120
CACHE_TTL_BUILDKITE=30
CACHE_TTL_QUEUE=15
CACHE_TTL_MERGED=120
CACHE_TTL_CLOSED=60
