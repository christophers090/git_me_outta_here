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

# Submodule repo (optional - set PRS_SUBMODULE_REPO in config.local.sh)
SUBMODULE_REPO="${PRS_SUBMODULE_REPO:-}"
SUBMODULE_REPO_OWNER="${SUBMODULE_REPO%%/*}"
SUBMODULE_REPO_NAME="${SUBMODULE_REPO##*/}"

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

# User alias map - resolves shorthand names to github_user:branch_user
# Reads from user_map.conf (gitignored). Format: alias=github_user or alias=github_user:branch_user
# If branch_user is omitted, github_user is used for both.
USER_MAP_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/user_map.conf"

# Resolve a user alias to github_user and branch_user
# Usage: resolve_user_alias <name>
# Sets: GITHUB_USER, BRANCH_USER
# Returns: 0 if alias found (values set), 1 if not found (values unchanged)
resolve_user_alias() {
    local name="$1"
    [[ -f "$USER_MAP_FILE" ]] || return 1

    local line value
    while IFS= read -r line; do
        # Skip comments and blank lines
        [[ -z "$line" || "$line" == \#* ]] && continue
        # Match alias= prefix
        if [[ "$line" == "${name}="* ]]; then
            value="${line#*=}"
            if [[ "$value" == *:* ]]; then
                GITHUB_USER="${value%%:*}"
                BRANCH_USER="${value#*:}"
            else
                GITHUB_USER="$value"
                BRANCH_USER="$value"
            fi
            return 0
        fi
    done < "$USER_MAP_FILE"
    return 1
}

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
