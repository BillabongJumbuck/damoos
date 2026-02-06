#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: GPL-2.0

# End-to-End Test for DAMOOS Android Integration (Phase 2)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DAMOOS="$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Test configuration
TEST_APP="${1:-com.android.settings}"
TEST_DURATION="${2:-15}"  # seconds

print_header "DAMOOS Android Integration Test (Phase 2)"
echo "Test App: $TEST_APP"
echo "Test Duration: $TEST_DURATION seconds"
echo ""

# Step 1: Environment check
print_header "Step 1: Environment Check"

# Source ADB modules
source "$DAMOOS/adb_interface/adb_utils.sh"
source "$DAMOOS/adb_interface/adb_workload.sh"
source "$DAMOOS/adb_interface/adb_metric_collector.sh"

if ! adb_check_connection; then
    print_error "ADB connection failed"
    exit 1
fi
print_success "ADB connected"

if ! adb_check_root; then
    print_error "Root access required"
    exit 1
fi
print_success "Root access available"

# Step 2: Initialize Android environment
print_header "Step 2: Initialize Android Environment"

if ! adb_init_damoos_dirs; then
    print_error "Failed to initialize directories"
    exit 1
fi
print_success "Directories initialized"

if ! adb_push_collector_scripts "$DAMOOS"; then
    print_error "Failed to push collector scripts"
    exit 1
fi
print_success "Collector scripts pushed"

# Step 3: Clean up previous test data
print_header "Step 3: Cleanup Previous Data"

cleanup_remote_data
sudo rm -rf "$DAMOOS/results/"*/*.stat 2>/dev/null
print_success "Cleanup completed"

# Step 4: Start workload
print_header "Step 4: Start Android Workload"

if ! start_android_app "$TEST_APP" ""; then
    print_error "Failed to start app"
    exit 1
fi
print_success "App started: $TEST_APP"

sleep 2

PID=$(get_app_pid "$TEST_APP")
if [ -z "$PID" ]; then
    print_error "Failed to get PID"
    exit 1
fi
print_success "Got PID: $PID"

# Step 5: Start metric collectors
print_header "Step 5: Start Metric Collectors"

METRICS=("rss" "runtime" "psi" "swapin" "swapout")

for metric in "${METRICS[@]}"; do
    if start_remote_collector "$metric" "$PID"; then
        print_success "Started collector: $metric"
    else
        print_error "Failed to start collector: $metric"
    fi
done

# Step 6: Let it run for a while
print_header "Step 6: Monitor Application"
echo "Monitoring $TEST_APP (PID: $PID) for $TEST_DURATION seconds..."

for ((i=1; i<=TEST_DURATION; i++)); do
    if ! is_app_running "$TEST_APP"; then
        print_error "App stopped unexpectedly"
        break
    fi
    
    if [ $((i % 5)) -eq 0 ]; then
        MEM=$(get_app_memory_usage "$PID")
        echo "  [${i}s/${TEST_DURATION}s] Memory: ${MEM} KB"
    fi
    
    sleep 1
done

# Step 7: Stop application
print_header "Step 7: Stop Application"

stop_android_app "$TEST_APP"
print_success "App stopped"

# Wait for collectors to finish
sleep 3

# Step 8: Collect metrics
print_header "Step 8: Pull Metric Data"

for metric in "${METRICS[@]}"; do
    if pull_metric_data "$metric" "$PID"; then
        print_success "Pulled metric: $metric"
        
        # Show sample data
        stat_file="$DAMOOS/results/$metric/$PID.stat"
        if [ -f "$stat_file" ]; then
            lines=$(wc -l < "$stat_file")
            echo "  Samples collected: $lines"
            
            if [ "$metric" = "rss" ] && [ "$lines" -gt 0 ]; then
                avg=$(awk '{sum+=$1} END {print sum/NR}' "$stat_file")
                echo "  Average RSS: $avg KB"
            elif [ "$metric" = "runtime" ]; then
                runtime=$(cat "$stat_file")
                echo "  Runtime: $runtime seconds"
            fi
        fi
    else
        print_error "Failed to pull metric: $metric"
    fi
done

# Step 9: Verify data on device
print_header "Step 9: Verify Remote Data"

for metric in "${METRICS[@]}"; do
    remote_file="/data/local/tmp/damoos/results/$metric/$PID.stat"
    if adb_file_exists "$remote_file"; then
        size=$(adb_root_exec "wc -l < '$remote_file'" | tr -d '\r\n ')
        print_success "Remote file exists: $metric ($size lines)"
    else
        print_error "Remote file missing: $metric"
    fi
done

# Step 10: Summary
print_header "Test Summary"

echo "App: $TEST_APP"
echo "PID: $PID"
echo "Duration: $TEST_DURATION seconds"
echo ""

SUCCESS=true
for metric in "${METRICS[@]}"; do
    stat_file="$DAMOOS/results/$metric/$PID.stat"
    if [ -f "$stat_file" ] && [ -s "$stat_file" ]; then
        print_success "Metric OK: $metric"
    else
        print_error "Metric FAILED: $metric"
        SUCCESS=false
    fi
done

echo ""
if [ "$SUCCESS" = true ]; then
    echo -e "${GREEN}✓ All tests PASSED!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Test with other apps (e.g., com.miHoYo.Yuanshen)"
    echo "  2. Test DAMON integration"
    echo "  3. Test with scheme adapters"
    exit 0
else
    echo -e "${RED}✗ Some tests FAILED${NC}"
    exit 1
fi
