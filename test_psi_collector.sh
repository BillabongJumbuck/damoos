#!/bin/bash

# Quick test script for PSI collector on Android device

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "PSI Collector Test for Android"
echo "=========================================="
echo ""

# Source ADB utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/adb_interface/adb_utils.sh"
source "${SCRIPT_DIR}/adb_interface/adb_metric_collector.sh"

# Test app (using Settings as it's lightweight and always available)
TEST_APP="com.android.settings"
TEST_DURATION=10

echo "Step 1: Check ADB connection and root..."
if ! adb_check_connection; then
    echo -e "${RED}[FAIL]${NC} ADB connection failed"
    exit 1
fi
echo -e "${GREEN}[OK]${NC} ADB connected"

if ! adb_check_root; then
    echo -e "${RED}[FAIL]${NC} Root access required"
    exit 1
fi
echo -e "${GREEN}[OK]${NC} Root access available"

echo ""
echo "Step 2: Check PSI support on device..."
PSI_SUPPORT=$(adb_root_exec "test -r /proc/pressure/memory && echo 'yes' || echo 'no'")
if [ "$PSI_SUPPORT" != "yes" ]; then
    echo -e "${RED}[FAIL]${NC} PSI not supported on this device"
    echo "PSI requires:"
    echo "  - Kernel 4.20+ with CONFIG_PSI=y"
    echo "  - Android 10+ (typically)"
    exit 1
fi
echo -e "${GREEN}[OK]${NC} PSI is supported"

# Show current PSI values
echo ""
echo "Current PSI values:"
adb_root_exec "cat /proc/pressure/memory"

echo ""
echo "Step 3: Initialize DAMOOS directories on device..."
adb_init_damoos_dirs
echo -e "${GREEN}[OK]${NC} Directories initialized"

echo ""
echo "Step 4: Push PSI collector script..."
PSI_COLLECTOR="${SCRIPT_DIR}/metrics_collector/collectors/android/psi_collector_android.sh"
if [ ! -f "$PSI_COLLECTOR" ]; then
    echo -e "${RED}[FAIL]${NC} PSI collector script not found: $PSI_COLLECTOR"
    exit 1
fi

REMOTE_SCRIPT="/data/local/tmp/damoos/scripts/psi_collector_android.sh"
if ! adb_push_file "$PSI_COLLECTOR" "$REMOTE_SCRIPT"; then
    echo -e "${RED}[FAIL]${NC} Failed to push collector script"
    exit 1
fi
adb_root_exec "chmod 755 '$REMOTE_SCRIPT'"
echo -e "${GREEN}[OK]${NC} PSI collector pushed and made executable"

echo ""
echo "Step 5: Start test app (${TEST_APP})..."
source "${SCRIPT_DIR}/adb_interface/adb_workload.sh"
if ! start_android_app "$TEST_APP"; then
    echo -e "${RED}[FAIL]${NC} Failed to start app"
    exit 1
fi
sleep 2

PID=$(get_app_pid "$TEST_APP")
if [ -z "$PID" ]; then
    echo -e "${RED}[FAIL]${NC} Could not get app PID"
    exit 1
fi
echo -e "${GREEN}[OK]${NC} App started, PID: $PID"

echo ""
echo "Step 6: Start PSI collector..."
if ! start_remote_collector "psi" "$PID"; then
    echo -e "${RED}[FAIL]${NC} Failed to start PSI collector"
    exit 1
fi
echo -e "${GREEN}[OK]${NC} PSI collector started"

echo ""
echo "Collecting PSI data for ${TEST_DURATION} seconds..."
for i in $(seq 1 $TEST_DURATION); do
    echo -n "."
    sleep 1
done
echo ""

echo ""
echo "Step 7: Stop collector and pull data..."
stop_remote_collector "psi" "$PID"

REMOTE_STAT="/data/local/tmp/damoos/results/psi/${PID}.stat"
if ! pull_metric_data "psi" "$PID" "${SCRIPT_DIR}/results"; then
    echo -e "${RED}[FAIL]${NC} Failed to pull PSI data"
    exit 1
fi
echo -e "${GREEN}[OK]${NC} PSI data pulled"

LOCAL_STAT="${SCRIPT_DIR}/results/psi/${PID}.stat"
if [ ! -f "$LOCAL_STAT" ]; then
    echo -e "${RED}[FAIL]${NC} Local stat file not found: $LOCAL_STAT"
    exit 1
fi

echo ""
echo "Step 8: Validate PSI data..."
LINE_COUNT=$(wc -l < "$LOCAL_STAT")
echo "PSI data file has $LINE_COUNT lines"

if [ "$LINE_COUNT" -lt 2 ]; then
    echo -e "${YELLOW}[WARN]${NC} Expected more data lines (header + data)"
fi

echo ""
echo "First 5 lines of PSI data:"
head -n 5 "$LOCAL_STAT"

echo ""
echo "Last 5 lines of PSI data:"
tail -n 5 "$LOCAL_STAT"

# Validate data format
echo ""
echo "Step 9: Check data format..."
DATA_LINE=$(tail -n 1 "$LOCAL_STAT")
FIELD_COUNT=$(echo "$DATA_LINE" | wc -w)

if [ "$FIELD_COUNT" -eq 9 ]; then
    echo -e "${GREEN}[OK]${NC} PSI data has correct format (9 fields)"
else
    echo -e "${YELLOW}[WARN]${NC} Expected 9 fields, got $FIELD_COUNT"
fi

echo ""
echo "Step 10: Cleanup..."
stop_android_app "$TEST_APP"
cleanup_remote_data

echo -e "${GREEN}[OK]${NC} Cleanup complete"

echo ""
echo "=========================================="
echo -e "${GREEN}PSI Collector Test PASSED${NC}"
echo "=========================================="
echo ""
echo "PSI data saved to: $LOCAL_STAT"
echo "You can now use PSI metrics in your optimization workflow!"
