#!/usr/bin/env bash
# prs test runner - Simple bash test framework
# Usage: ./run_tests.sh [test_file...]

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRS_DIR="$(dirname "$TESTS_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

# Counters
PASS=0
FAIL=0

main() {
    echo -e "${BOLD}prs Test Suite${NC}"
    echo ""

    # Determine which test files to run
    local test_files=()
    if [[ $# -gt 0 ]]; then
        test_files=("$@")
    else
        for f in "$TESTS_DIR"/test_*.sh; do
            [[ -f "$f" ]] && test_files+=("$f")
        done
    fi

    # Run each test file as standalone script
    for test_file in "${test_files[@]}"; do
        if [[ ! -f "$test_file" ]]; then
            echo -e "${RED}Test file not found:${NC} $test_file"
            continue
        fi

        echo -e "${BOLD}$(basename "$test_file")${NC}"

        # Run test file as subprocess with timeout
        if timeout 30 bash "$test_file" "$PRS_DIR"; then
            ((++PASS))
        else
            ((++FAIL))
        fi
        echo ""
    done

    # Summary
    echo -e "${BOLD}────────────────────────────────────────${NC}"
    echo -e "Results: ${GREEN}$PASS file(s) passed${NC}, ${RED}$FAIL file(s) failed${NC}"

    [[ $FAIL -eq 0 ]]
}

main "$@"
