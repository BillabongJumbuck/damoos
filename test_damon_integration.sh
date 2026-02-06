#!/bin/bash

# Quick test for DAMON scheme integration with Android

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DAMOOS="${DAMOOS:-$(cd "$SCRIPT_DIR" && pwd)}"

source "$DAMOOS/adb_interface/adb_utils.sh"
source "$DAMOOS/adb_interface/adb_workload.sh"
source "$DAMOOS/adb_interface/adb_damon_control.sh"
source "$DAMOOS/adb_interface/adb_metric_collector.sh"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "DAMON Scheme Integration Test"
echo "=========================================="
echo ""

# Check prerequisites
echo "1. Checking ADB connection..."
if ! adb_check_connection || ! adb_check_root; then
    echo "Error: ADB connection or root failed"
    exit 1
fi
echo -e "${GREEN}✓${NC} ADB ready"

if ! adb_verify_damon_support; then
    echo "Error: DAMON not supported"
    exit 1
fi
echo -e "${GREEN}✓${NC} DAMON supported"

# Initialize
echo ""
echo "2. Initializing environment..."
adb_init_damoos_dirs
adb_push_collector_scripts "$DAMOOS"
echo -e "${GREEN}✓${NC} Environment ready"

# Start test app
echo ""
echo "3. Starting test app (Settings)..."
TEST_APP="com.android.settings"

if ! start_android_app "$TEST_APP" ""; then
    echo "Error: Failed to start app"
    exit 1
fi
sleep 2

PID=$(get_app_pid "$TEST_APP")
if [ -z "$PID" ]; then
    echo "Error: Failed to get PID"
    exit 1
fi
echo -e "${GREEN}✓${NC} App started, PID: $PID"

# Test DAMON control
echo ""
echo "4. Testing DAMON control..."

# Stop DAMON if running
STATUS=$(damon_get_status)
if [ "$STATUS" = "on" ]; then
    echo "  Stopping existing monitoring..."
    damon_stop
fi

# Initialize and set scheme
echo "  Initializing DAMON..."
damon_init

echo "  Setting target PID: $PID"
damon_set_target "$PID"

echo "  Setting scheme: min_size=4K, min_age=5s, action=pageout"
damon_set_scheme "4K" "16E" "0" "0" "5s" "4294967295" "pageout"

echo "  Starting DAMON monitoring..."
damon_start

sleep 2

# Verify
STATUS=$(damon_get_status)
if [ "$STATUS" = "on" ]; then
    echo -e "${GREEN}✓${NC} DAMON monitoring active"
else
    echo "Error: DAMON not active"
    exit 1
fi

# Show current configuration
echo ""
echo "5. Current DAMON configuration:"
echo "  Target IDs:"
adb_root_exec "cat /sys/kernel/debug/damon/target_ids" | sed 's/^/    /'
echo "  Attributes:"
adb_root_exec "cat /sys/kernel/debug/damon/attrs" | sed 's/^/    /'
echo "  Schemes:"
adb_root_exec "cat /sys/kernel/debug/damon/schemes" | sed 's/^/    /'
echo "  Status:"
adb_root_exec "cat /sys/kernel/debug/damon/monitor_on" | sed 's/^/    /'

# Monitor for 10 seconds
echo ""
echo "6. Monitoring for 10 seconds..."
for i in {1..10}; do
    MEM=$(get_app_memory_usage "$PID")
    echo "  [$i/10] Memory: ${MEM}KB"
    sleep 1
done

# Stop DAMON
echo ""
echo "7. Stopping DAMON..."
damon_stop

STATUS=$(damon_get_status)
if [ "$STATUS" = "off" ]; then
    echo -e "${GREEN}✓${NC} DAMON stopped"
else
    echo -e "${YELLOW}Warning:${NC} DAMON may still be running"
fi

# Cleanup
echo ""
echo "8. Cleanup..."
stop_android_app "$TEST_APP"
cleanup_remote_data

echo ""
echo "=========================================="
echo -e "${GREEN}DAMON Integration Test PASSED${NC}"
echo "=========================================="
echo ""
echo "Ready for full optimization workflow!"
