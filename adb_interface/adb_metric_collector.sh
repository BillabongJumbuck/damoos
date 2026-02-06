#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: GPL-2.0

# Remote metric collection orchestration for Android devices

# Source utility functions if not already loaded
if ! command -v adb_root_exec >/dev/null 2>&1; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/adb_utils.sh"
fi

# Android paths
ANDROID_DAMOOS_DIR="/data/local/tmp/damoos"
ANDROID_SCRIPTS_DIR="${ANDROID_DAMOOS_DIR}/scripts"
ANDROID_RESULTS_DIR="${ANDROID_DAMOOS_DIR}/results"

# Mapping of metric names to collector scripts
declare -A COLLECTOR_SCRIPTS=(
    ["rss"]="rss_collector_android.sh"
    ["runtime"]="runtime_collector_android.sh"
    ["swapin"]="swapin_collector_android.sh"
    ["swapout"]="swapout_collector_android.sh"
    ["psi"]="psi_collector_android.sh"
)

# Start remote metric collector on Android device
# Args: $1 - metric name, $2 - PID
# Returns: 0 on success, 1 on failure
start_remote_collector() {
    local metric="$1"
    local pid="$2"
    
    if [ -z "$metric" ] || [ -z "$pid" ]; then
        echo "Error: Metric name and PID required."
        return 1
    fi
    
    local script="${COLLECTOR_SCRIPTS[$metric]}"
    if [ -z "$script" ]; then
        echo "Error: Unknown metric: $metric"
        return 1
    fi
    
    local script_path="${ANDROID_SCRIPTS_DIR}/${script}"
    
    # Check if script exists on device
    if ! adb_file_exists "$script_path"; then
        echo "Error: Collector script not found on device: $script_path"
        echo "Please run adb_push_collector_scripts first."
        return 1
    fi
    
    echo "Starting remote collector: $metric (PID: $pid)"
    
    # Create results directory for this metric
    adb_ensure_directory "${ANDROID_RESULTS_DIR}/${metric}"
    
    # Start collector in background on Android
    # Using simple background execution without nohup (nohup may not work on all Android devices)
    adb shell "su -c 'cd ${ANDROID_SCRIPTS_DIR} && sh ${script} ${pid} >/dev/null 2>&1 &'" &
    
    # Give command time to finish and collector to start
    sleep 2
    
    echo "Remote collector started: $metric"
    return 0
}

# Stop remote metric collector on Android device
# Args: $1 - metric name, $2 - PID
# Returns: 0 on success
stop_remote_collector() {
    local metric="$1"
    local pid="$2"
    
    if [ -z "$metric" ]; then
        echo "Error: Metric name required."
        return 1
    fi
    
    local script="${COLLECTOR_SCRIPTS[$metric]}"
    if [ -z "$script" ]; then
        echo "Error: Unknown metric: $metric"
        return 1
    fi
    
    echo "Stopping remote collector: $metric"
    
    # Find and kill collector processes by script name
    # Use background execution to avoid hanging
    adb shell "su -c 'pkill -f ${script}'" 2>/dev/null &
    
    # Don't wait for pkill to complete - it may hang on some devices
    sleep 1
    
    echo "Remote collector stopped: $metric"
    return 0
}

# Pull metric data from Android device to PC
# Args: $1 - metric name, $2 - PID, $3 - local results directory (optional)
# Returns: 0 on success, 1 on failure
pull_metric_data() {
    local metric="$1"
    local pid="$2"
    local local_results_dir="${3:-$DAMOOS/results}"
    
    if [ -z "$metric" ] || [ -z "$pid" ]; then
        echo "Error: Metric name and PID required."
        return 1
    fi
    
    # Remote stat file
    local remote_stat_file="${ANDROID_RESULTS_DIR}/${metric}/${pid}.stat"
    
    # Local stat file
    local local_metric_dir="${local_results_dir}/${metric}"
    mkdir -p "$local_metric_dir"
    local local_stat_file="${local_metric_dir}/${pid}.stat"
    
    echo "Pulling metric data: $metric (PID: $pid)"
    
    # Wait for stat file to appear (with timeout)
    if ! adb_wait_for_file "$remote_stat_file" 30; then
        echo "Error: Stat file not found: $remote_stat_file"
        return 1
    fi
    
    # Pull the file
    if ! adb_pull_file "$remote_stat_file" "$local_stat_file"; then
        echo "Error: Failed to pull metric data: $metric"
        return 1
    fi
    
    echo "Metric data pulled successfully: $local_stat_file"
    return 0
}

# Wait for remote metric collector to finish and pull data
# Args: $1 - metric name, $2 - PID, $3 - timeout (optional, default: 300s)
# Returns: 0 on success, 1 on timeout
wait_and_pull_metric() {
    local metric="$1"
    local pid="$2"
    local timeout="${3:-300}"
    
    echo "Waiting for metric collection to complete: $metric (PID: $pid)"
    
    local remote_stat_file="${ANDROID_RESULTS_DIR}/${metric}/${pid}.stat"
    
    # Wait for stat file with timeout
    if ! adb_wait_for_file "$remote_stat_file" "$timeout"; then
        echo "Error: Timeout waiting for metric collection: $metric"
        return 1
    fi
    
    # Pull the data
    pull_metric_data "$metric" "$pid"
    
    return $?
}

# Start multiple collectors for a workload
# Args: $1 - PID, $2... - metric names
# Returns: 0 on success, 1 if any collector fails
start_all_collectors() {
    local pid="$1"
    shift
    local metrics=("$@")
    
    if [ -z "$pid" ] || [ ${#metrics[@]} -eq 0 ]; then
        echo "Error: PID and at least one metric required."
        return 1
    fi
    
    echo "Starting all collectors for PID: $pid"
    echo "Metrics: ${metrics[*]}"
    
    local failed=0
    
    for metric in "${metrics[@]}"; do
        if ! start_remote_collector "$metric" "$pid"; then
            echo "Warning: Failed to start collector: $metric"
            failed=1
        fi
    done
    
    if [ $failed -eq 0 ]; then
        echo "All collectors started successfully."
    else
        echo "Warning: Some collectors failed to start."
    fi
    
    return $failed
}

# Stop all collectors
# Args: $1... - metric names
# Returns: 0 on success
stop_all_collectors() {
    local metrics=("$@")
    
    echo "Stopping all collectors..."
    
    for metric in "${metrics[@]}"; do
        stop_remote_collector "$metric" ""
    done
    
    # Also kill any remaining collector processes
    adb_root_exec "pkill -f 'collector_android.sh'"
    
    echo "All collectors stopped."
    return 0
}

# Pull all metric data for a PID
# Args: $1 - PID, $2... - metric names
# Returns: 0 on success, 1 if any pull fails
pull_all_metrics() {
    local pid="$1"
    shift
    local metrics=("$@")
    
    if [ -z "$pid" ] || [ ${#metrics[@]} -eq 0 ]; then
        echo "Error: PID and at least one metric required."
        return 1
    fi
    
    echo "Pulling all metric data for PID: $pid"
    
    local failed=0
    
    for metric in "${metrics[@]}"; do
        if ! pull_metric_data "$metric" "$pid"; then
            echo "Warning: Failed to pull metric: $metric"
            failed=1
        fi
    done
    
    if [ $failed -eq 0 ]; then
        echo "All metric data pulled successfully."
    else
        echo "Warning: Some metric pulls failed."
    fi
    
    return $failed
}

# Clean up remote metric data on Android device
# Args: none (cleans all)
# Returns: 0 on success
cleanup_remote_data() {
    echo "Cleaning up remote metric data on Android..."
    
    # Kill any running collectors (run in background to avoid hanging)
    adb shell "su -c 'pkill -f collector_android'" 2>/dev/null &
    sleep 1
    
    # Remove all stat files
    adb shell "su -c 'rm -rf ${ANDROID_RESULTS_DIR}/*'" 2>/dev/null
    
    # Recreate result directories - run in background
    adb shell "su -c 'mkdir -p ${ANDROID_RESULTS_DIR}/{rss,runtime,swapin,swapout,psi}'" 2>/dev/null &
    sleep 1
    
    echo "Remote data cleaned up."
    return 0
}

# Verify all collector scripts are on device
# Returns: 0 if all present, 1 if any missing
verify_collector_scripts() {
    echo "Verifying collector scripts on Android device..."
    
    local all_present=0
    
    for metric in "${!COLLECTOR_SCRIPTS[@]}"; do
        local script="${COLLECTOR_SCRIPTS[$metric]}"
        local script_path="${ANDROID_SCRIPTS_DIR}/${script}"
        
        if adb_file_exists "$script_path"; then
            echo "  ✓ $script"
        else
            echo "  ✗ $script (missing)"
            all_present=1
        fi
    done
    
    if [ $all_present -eq 0 ]; then
        echo "All collector scripts verified."
        return 0
    else
        echo "Some collector scripts are missing."
        echo "Run: adb_push_collector_scripts <damoos_path>"
        return 1
    fi
}

# Get collector status
# Returns: List of running collectors
get_collector_status() {
    echo "=== Collector Status on Android ==="
    
    for metric in "${!COLLECTOR_SCRIPTS[@]}"; do
        local script="${COLLECTOR_SCRIPTS[$metric]}"
        local running
        running=$(adb_root_exec "ps -A | grep '$script' | grep -v grep")
        
        if [ -n "$running" ]; then
            echo "[$metric] RUNNING"
            echo "  $running"
        else
            echo "[$metric] STOPPED"
        fi
    done
    
    echo "==================================="
}

# Initialize remote metric collection environment
# Args: $1 - DAMOOS root path on PC
# Returns: 0 on success, 1 on failure
init_remote_collection() {
    local damoos_path="$1"
    
    if [ -z "$damoos_path" ]; then
        echo "Error: DAMOOS path required."
        return 1
    fi
    
    echo "Initializing remote metric collection environment..."
    
    # Initialize directories
    if ! adb_init_damoos_dirs; then
        return 1
    fi
    
    # Push collector scripts
    if ! adb_push_collector_scripts "$damoos_path"; then
        return 1
    fi
    
    # Verify scripts
    if ! verify_collector_scripts; then
        return 1
    fi
    
    echo "Remote collection environment initialized successfully."
    return 0
}

# Export functions for use in other scripts
export -f start_remote_collector
export -f stop_remote_collector
export -f pull_metric_data
export -f wait_and_pull_metric
export -f start_all_collectors
export -f stop_all_collectors
export -f pull_all_metrics
export -f cleanup_remote_data
export -f verify_collector_scripts
export -f get_collector_status
export -f init_remote_collection
