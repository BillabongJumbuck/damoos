#!/bin/bash

# Quick non-interactive test for core functionality

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "========================================="
echo "Quick Core Function Test"
echo "========================================="
echo ""

# Source modules
source "${SCRIPT_DIR}/adb_utils.sh"
source "${SCRIPT_DIR}/adb_damon_control.sh"

# Test unit conversions
echo "Testing unit conversions..."
TESTS_PASSED=0
TESTS_FAILED=0

test_conversion() {
    local func=$1
    local input=$2
    local expected=$3
    local result
    result=$($func "$input")
    
    if [ "$result" = "$expected" ]; then
        echo -e "${GREEN}✓${NC} $func \"$input\" = $result"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $func \"$input\" = $result (expected $expected)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Time conversions
test_conversion time_to_microseconds "5s" "5000000"
test_conversion time_to_microseconds "100ms" "100000"
test_conversion time_to_microseconds "1000us" "1000"
test_conversion time_to_microseconds "1m" "60000000"
test_conversion time_to_microseconds "min" "0"
test_conversion time_to_microseconds "max" "18446744073709551615"

# Size conversions
test_conversion size_to_bytes "4K" "4096"
test_conversion size_to_bytes "1M" "1048576"
test_conversion size_to_bytes "1G" "1073741824"
test_conversion size_to_bytes "1024B" "1024"
test_conversion size_to_bytes "min" "0"
test_conversion size_to_bytes "max" "18446744073709551615"

echo ""
echo "========================================="
echo "Results: Passed=$TESTS_PASSED, Failed=$TESTS_FAILED"
echo "========================================="

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All unit conversion tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed!${NC}"
    exit 1
fi
