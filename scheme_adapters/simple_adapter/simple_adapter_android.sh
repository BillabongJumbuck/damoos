#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: GPL-2.0

# Simple Scheme Adapter for Android workloads
# Tests different DAMON schemes to find optimal configuration

if [[ $# -ne 2 ]]
then
	echo "Usage: $0 <workload_name> <importance_weight>"
	echo "  workload_name: e.g., douyin, wechat, taobao"
	echo "  importance_weight: 0.0-1.0 (0=optimize RSS, 1=optimize runtime)"
	exit 1
fi

WORKLOAD="$1"
WEIGHT="$2"

# Source ADB modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DAMOOS="${DAMOOS:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

source "$DAMOOS/adb_interface/adb_utils.sh"
source "$DAMOOS/adb_interface/adb_workload.sh"
source "$DAMOOS/adb_interface/adb_damon_control.sh"
source "$DAMOOS/adb_interface/adb_metric_collector.sh"

# Check if workload is Android type
WORKLOAD_ENTRY=$(grep "^${WORKLOAD}@@@" "$DAMOOS/frontend/workload_directory.txt")
if [ -z "$WORKLOAD_ENTRY" ]; then
    echo "Error: Workload '$WORKLOAD' not found in workload_directory.txt"
    exit 1
fi

IS_ANDROID=$(echo "$WORKLOAD_ENTRY" | grep "@@@ANDROID@@@" || true)
if [ -z "$IS_ANDROID" ]; then
    echo "Error: Workload '$WORKLOAD' is not an Android workload"
    echo "Please use original simple_adapter.sh for local workloads"
    exit 1
fi

# Verify ADB connection
if ! adb_check_connection; then
    echo "Error: ADB connection failed"
    exit 1
fi

if ! adb_check_root; then
    echo "Error: Root access not available"
    exit 1
fi

# Verify DAMON support
if ! adb_verify_damon_support; then
    echo "Error: DAMON not supported on device"
    exit 1
fi

echo "=========================================="
echo "DAMOOS Simple Adapter - Android"
echo "=========================================="
echo "Workload: $WORKLOAD"
echo "Weight (runtime importance): $WEIGHT"
echo ""

# Initialize
adb_init_damoos_dirs
adb_push_collector_scripts "$DAMOOS"

# Get DAMON parameters
AGGR_INTERVAL=$(adb_root_exec "cat /sys/kernel/debug/damon/attrs" | awk '{print $2}')
MAX_REGION_SIZE="18446744073709551615"
MAX_AGE="4294967295"

echo "DAMON aggregation interval: ${AGGR_INTERVAL}us"
echo ""

# Helper functions
get_workload_runtime() {
    local pid="$1"
    local metric_type="${2:-android}"
    sudo DAMOOS="$DAMOOS" bash "$DAMOOS"/frontend/get_metric.sh "$pid" "runtime-${metric_type}" stat
    if [[ $? -ne 0 ]]; then
        echo "Error: Unable to get runtime metric"
        return 1
    fi
    cat "$DAMOOS/results/runtime/$pid.stat"
}

get_workload_rss() {
    local pid="$1"
    local metric_type="${2:-android}"
    sudo DAMOOS="$DAMOOS" bash "$DAMOOS"/frontend/get_metric.sh "$pid" "rss-${metric_type}" full_avg
    if [[ $? -ne 0 ]]; then
        echo "Error: Unable to get RSS metric"
        return 1
    fi
    cat "$DAMOOS/results/rss/$pid.full_avg"
}

run_workload_with_scheme() {
    local min_size="$1"
    local min_age="$2"
    local action="${3:-pageout}"
    
    # Start workload
    sudo DAMOOS="$DAMOOS" bash "$DAMOOS"/frontend/run_workloads.sh "$WORKLOAD" "runtime-android" "rss-android"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to start workload"
        return 1
    fi
    
    # Get PID
    local pid
    pid=$(cat "$DAMOOS/results/pid" 2>/dev/null)
    if [ -z "$pid" ]; then
        echo "Error: Failed to get PID"
        return 1
    fi
    
    echo "  PID: $pid"
    
    # Check if DAMON is already running
    local monitor_status
    monitor_status=$(damon_get_status)
    if [ "$monitor_status" = "on" ]; then
        echo "  Stopping existing DAMON monitoring..."
        damon_stop
        sleep 1
    fi
    
    # Set DAMON scheme
    echo "  Setting DAMON scheme: min_size=${min_size}, min_age=${min_age}, action=${action}"
    damon_init
    damon_set_target "$pid"
    damon_set_scheme "$min_size" "$MAX_REGION_SIZE" "0" "0" "$min_age" "$MAX_AGE" "$action"
    damon_start
    
    # Wait for workload to complete (30 seconds for Android apps)
    echo "  Running for 30 seconds..."
    sleep 30
    
    # Stop DAMON and workload
    damon_stop
    stop_android_app "$(echo "$WORKLOAD_ENTRY" | cut -d'@' -f4)"
    
    # Wait for data collection
    sudo DAMOOS="$DAMOOS" bash "$DAMOOS"/frontend/wait_for_metric_collector.sh "$pid" "runtime-android" "rss-android"
    
    # Get metrics
    local curr_runtime curr_rss
    curr_runtime=$(get_workload_runtime "$pid" "android")
    curr_rss=$(get_workload_rss "$pid" "android")
    
    echo "  Runtime: ${curr_runtime}s, RSS: ${curr_rss}KB"
    echo "$curr_runtime $curr_rss"
}

# Step 0: Get baseline (no DAMON scheme)
echo "=========================================="
echo "Step 0: Baseline (No DAMON)"
echo "=========================================="

orig_runtime_sum=0
orig_rss_sum=0
ITERATIONS=3

for ((i=1; i<=ITERATIONS; i++)); do
    echo ""
    echo "Baseline run $i/$ITERATIONS..."
    
    result=$(run_workload_with_scheme "0" "0" "stat")
    curr_runtime=$(echo "$result" | awk '{print $1}')
    curr_rss=$(echo "$result" | awk '{print $2}')
    
    orig_runtime_sum=$(echo "scale=2; $orig_runtime_sum + $curr_runtime" | bc)
    orig_rss_sum=$(echo "scale=2; $orig_rss_sum + $curr_rss" | bc)
    
    cleanup_remote_data
    sleep 2
done

orig_runtime=$(echo "scale=2; $orig_runtime_sum / $ITERATIONS" | bc)
orig_rss=$(echo "scale=2; $orig_rss_sum / $ITERATIONS" | bc)

echo ""
echo "Baseline Results:"
echo "  Average Runtime: ${orig_runtime}s"
echo "  Average RSS: ${orig_rss}KB"
echo ""

# Step 1: Optimize min_age (fixed min_size=4K)
echo "=========================================="
echo "Step 1: Optimize MIN_AGE (min_size=4K)"
echo "=========================================="

min_score=999999
best_min_age_sec=5
best_runtime=$orig_runtime
best_rss=$orig_rss

for age_sec in 5 8 10 13; do
    echo ""
    echo "Testing min_age=${age_sec}s..."
    
    # Convert seconds to DAMON units
    min_age_us=$((age_sec * 1000000))
    min_age_damon=$((min_age_us / AGGR_INTERVAL))
    
    runtime_sum=0
    rss_sum=0
    
    for ((i=1; i<=ITERATIONS; i++)); do
        echo "  Run $i/$ITERATIONS..."
        result=$(run_workload_with_scheme "4K" "${age_sec}s" "pageout")
        curr_runtime=$(echo "$result" | awk '{print $1}')
        curr_rss=$(echo "$result" | awk '{print $2}')
        
        runtime_sum=$(echo "scale=2; $runtime_sum + $curr_runtime" | bc)
        rss_sum=$(echo "scale=2; $rss_sum + $curr_rss" | bc)
        
        cleanup_remote_data
        sleep 2
    done
    
    avg_runtime=$(echo "scale=2; $runtime_sum / $ITERATIONS" | bc)
    avg_rss=$(echo "scale=2; $rss_sum / $ITERATIONS" | bc)
    
    runtime_overhead=$(echo "scale=2; (($avg_runtime - $orig_runtime) / $orig_runtime) * 100" | bc)
    rss_overhead=$(echo "scale=2; (($avg_rss - $orig_rss) / $orig_rss) * 100" | bc)
    
    temp=$(echo "scale=2; 1 - $WEIGHT" | bc)
    score=$(echo "scale=2; ($runtime_overhead * $WEIGHT) + ($rss_overhead * $temp)" | bc)
    
    echo "  Results: runtime=${avg_runtime}s, rss=${avg_rss}KB"
    echo "  Overhead: runtime=${runtime_overhead}%, rss=${rss_overhead}%"
    echo "  Score: $score"
    
    if (( $(echo "$score < $min_score" | bc -l) )); then
        min_score=$score
        best_min_age_sec=$age_sec
        best_runtime=$avg_runtime
        best_rss=$avg_rss
    fi
done

echo ""
echo "Best min_age: ${best_min_age_sec}s (score: $min_score)"
echo ""

# Step 2: Optimize min_size (fixed best min_age)
echo "=========================================="
echo "Step 2: Optimize MIN_SIZE (min_age=${best_min_age_sec}s)"
echo "=========================================="

best_min_size="4K"

for size in "4K" "8K" "12K" "16K" "20K"; do
    echo ""
    echo "Testing min_size=${size}..."
    
    runtime_sum=0
    rss_sum=0
    
    for ((i=1; i<=ITERATIONS; i++)); do
        echo "  Run $i/$ITERATIONS..."
        result=$(run_workload_with_scheme "$size" "${best_min_age_sec}s" "pageout")
        curr_runtime=$(echo "$result" | awk '{print $1}')
        curr_rss=$(echo "$result" | awk '{print $2}')
        
        runtime_sum=$(echo "scale=2; $runtime_sum + $curr_runtime" | bc)
        rss_sum=$(echo "scale=2; $rss_sum + $curr_rss" | bc)
        
        cleanup_remote_data
        sleep 2
    done
    
    avg_runtime=$(echo "scale=2; $runtime_sum / $ITERATIONS" | bc)
    avg_rss=$(echo "scale=2; $rss_sum / $ITERATIONS" | bc)
    
    runtime_overhead=$(echo "scale=2; (($avg_runtime - $orig_runtime) / $orig_runtime) * 100" | bc)
    rss_overhead=$(echo "scale=2; (($avg_rss - $orig_rss) / $orig_rss) * 100" | bc)
    
    temp=$(echo "scale=2; 1 - $WEIGHT" | bc)
    score=$(echo "scale=2; ($runtime_overhead * $WEIGHT) + ($rss_overhead * $temp)" | bc)
    
    echo "  Results: runtime=${avg_runtime}s, rss=${avg_rss}KB"
    echo "  Overhead: runtime=${runtime_overhead}%, rss=${rss_overhead}%"
    echo "  Score: $score"
    
    if (( $(echo "$score < $min_score" | bc -l) )); then
        min_score=$score
        best_min_size=$size
        best_runtime=$avg_runtime
        best_rss=$avg_rss
    fi
done

# Final results
echo ""
echo "=========================================="
echo "OPTIMIZATION COMPLETE"
echo "=========================================="
echo ""
echo "Baseline:"
echo "  Runtime: ${orig_runtime}s"
echo "  RSS: ${orig_rss}KB"
echo ""
echo "Optimized (Best Scheme):"
echo "  min_size: $best_min_size"
echo "  min_age: ${best_min_age_sec}s"
echo "  Runtime: ${best_runtime}s"
echo "  RSS: ${best_rss}KB"
echo ""

runtime_improvement=$(echo "scale=2; (($orig_runtime - $best_runtime) / $orig_runtime) * 100" | bc)
rss_improvement=$(echo "scale=2; (($orig_rss - $best_rss) / $orig_rss) * 100" | bc)

echo "Improvements:"
echo "  Runtime: ${runtime_improvement}%"
echo "  RSS: ${rss_improvement}%"
echo "  Final Score: $min_score"
echo ""

# Convert best scheme to DAMON format
best_min_age_us=$((best_min_age_sec * 1000000))

echo "DAMON Scheme (for debugfs):"
echo "  $best_min_size $MAX_REGION_SIZE 0 0 ${best_min_age_sec}s $MAX_AGE pageout"
echo ""

# Cleanup
sudo DAMOOS="$DAMOOS" bash "$DAMOOS"/frontend/cleanup.sh
cleanup_remote_data

echo "Done!"
