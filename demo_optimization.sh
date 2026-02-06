#!/bin/bash

# Simple DAMON optimization demo

export DAMOOS=/home/qjm/Desktop/damoos
source "$DAMOOS/adb_interface/adb_utils.sh"
source "$DAMOOS/adb_interface/adb_workload.sh"
source "$DAMOOS/adb_interface/adb_damon_control.sh"
source "$DAMOOS/adb_interface/adb_metric_collector.sh"

WORKLOAD="${1:-douyin}"
DURATION=30

# Get app package from workload_directory.txt
WORKLOAD_ENTRY=$(grep "^${WORKLOAD}@@@" "$DAMOOS/frontend/workload_directory.txt")
if [ -z "$WORKLOAD_ENTRY" ]; then
    echo "Error: Workload '$WORKLOAD' not found"
    echo "Available Android workloads:"
    grep "@@@ANDROID@@@" "$DAMOOS/frontend/workload_directory.txt" | cut -d'@' -f1
    exit 1
fi

APP=$(echo "$WORKLOAD_ENTRY" | cut -d'@' -f4)

echo "=========================================="
echo "DAMON Optimization Demo"
echo "=========================================="
echo "Workload: $WORKLOAD"
echo "Package: $APP"
echo "Duration: ${DURATION}s per test"
echo ""

# Initialize
adb_init_damoos_dirs
adb_push_collector_scripts "$DAMOOS"

# Test 1: Without DAMON
echo "[1/2] Running WITHOUT DAMON..."
start_android_app "$APP" ""
sleep 2
PID1=$(get_app_pid "$APP")
echo "  PID: $PID1"

# Start collectors
start_remote_collector "rss" "$PID1"
start_remote_collector "runtime" "$PID1"

# Monitor
echo "  Monitoring for ${DURATION} seconds..."
sleep 5
MEM1_5=$(get_app_memory_usage "$PID1")
sleep 5
MEM1_10=$(get_app_memory_usage "$PID1")
sleep 5
MEM1_15=$(get_app_memory_usage "$PID1")
sleep 5
MEM1_20=$(get_app_memory_usage "$PID1")

echo "  Memory: 5s=${MEM1_5}KB, 10s=${MEM1_10}KB, 15s=${MEM1_15}KB, 20s=${MEM1_20}KB"

# Stop
stop_android_app "$APP"
pull_metric_data "rss" "$PID1"
pull_metric_data "runtime" "$PID1"

# Calculate average RSS directly
RSS1=$(awk '{sum+=$1; count++} END {if(count>0) print int(sum/count); else print 0}' "$DAMOOS/results/rss/$PID1.stat" 2>/dev/null)
echo "  Average RSS: ${RSS1}KB"

cleanup_remote_data
sleep 5

# Test 2: With DAMON
echo ""
echo "[2/2] Running WITH DAMON (4K, 10s, pageout)..."
start_android_app "$APP" ""
sleep 2
PID2=$(get_app_pid "$APP")
echo "  PID: $PID2"

# Start DAMON
damon_init
damon_set_target "$PID2"
damon_set_scheme "4K" "16E" "0" "0" "10s" "4294967295" "pageout"
damon_start

# Start collectors  
start_remote_collector "rss" "$PID2"
start_remote_collector "runtime" "$PID2"

# Monitor
echo "  Monitoring for ${DURATION} seconds..."
sleep 5
MEM2_5=$(get_app_memory_usage "$PID2")
sleep 5
MEM2_10=$(get_app_memory_usage "$PID2")
sleep 5
MEM2_15=$(get_app_memory_usage "$PID2")
sleep 5
MEM2_20=$(get_app_memory_usage "$PID2")

echo "  Memory: 5s=${MEM2_5}KB, 10s=${MEM2_10}KB, 15s=${MEM2_15}KB, 20s=${MEM2_20}KB"

# Stop
damon_stop
stop_android_app "$APP"
pull_metric_data "rss" "$PID2"
pull_metric_data "runtime" "$PID2"

# Calculate average RSS directly
RSS2=$(awk '{sum+=$1; count++} END {if(count>0) print int(sum/count); else print 0}' "$DAMOOS/results/rss/$PID2.stat" 2>/dev/null)
echo "  Average RSS: ${RSS2}KB"

cleanup_remote_data

# Summary
echo ""
echo "=========================================="
echo "Results"
echo "=========================================="
echo "Without DAMON: ${RSS1}KB average RSS"
echo "With DAMON:    ${RSS2}KB average RSS"

if [ -n "$RSS1" ] && [ -n "$RSS2" ] && [ "$RSS1" != "0" ]; then
    DIFF=$((RSS1 - RSS2))
    PERCENT=$(echo "scale=1; ($DIFF * 100.0) / $RSS1" | bc)
    echo ""
    echo "Difference: ${DIFF}KB (${PERCENT}% reduction)"
    
    if [ "$DIFF" -gt 0 ]; then
        echo "✓ DAMON optimization effective!"
    fi
fi

echo ""
echo "Done!"
