#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: GPL-2.0

# ADB utility functions for Android device interaction

# Global variables
ADB_DEVICE_SERIAL="${ANDROID_SERIAL:-}"
ANDROID_DAMOOS_DIR="/data/local/tmp/damoos"
ANDROID_RESULTS_DIR="${ANDROID_DAMOOS_DIR}/results"

# Check if ADB is available and device is connected
# Returns: 0 if connected, 1 otherwise
adb_check_connection() {
    if ! command -v adb >/dev/null 2>&1; then
        echo "Error: adb command not found. Please install Android SDK Platform Tools."
        return 1
    fi

    local devices
    devices=$(adb devices 2>/dev/null | grep -w "device" | grep -v "List of devices")
    
    if [ -z "$devices" ]; then
        echo "Error: No ADB device connected."
        echo "Please connect your Android device and enable USB debugging."
        return 1
    fi

    local device_count
    device_count=$(echo "$devices" | wc -l)
    
    if [ "$device_count" -gt 1 ] && [ -z "$ADB_DEVICE_SERIAL" ]; then
        echo "Error: Multiple devices connected. Please set ANDROID_SERIAL environment variable."
        echo "Available devices:"
        adb devices
        return 1
    fi

    return 0
}

# Check if device has root access
# Returns: 0 if root available, 1 otherwise
adb_check_root() {
    local result
    result=$(adb shell "su -c 'id'" 2>/dev/null | grep -o "uid=0")
    
    if [ -z "$result" ]; then
        echo "Error: Root access not available on device."
        echo "Please ensure your device is rooted and grant root permission to ADB."
        return 1
    fi
    
    return 0
}

# Execute command on Android device with root
# Args: $1 - command to execute
# Returns: command output
adb_root_exec() {
    local cmd="$1"
    adb shell "su -c '$cmd'" 2>/dev/null
}

# Check if file exists on Android device
# Args: $1 - remote file path
# Returns: 0 if exists, 1 otherwise
adb_file_exists() {
    local remote_path="$1"
    local result
    result=$(adb_root_exec "test -f '$remote_path' && echo 'exists'")
    
    if [ "$result" = "exists" ]; then
        return 0
    else
        return 1
    fi
}

# Check if directory exists on Android device
# Args: $1 - remote directory path
# Returns: 0 if exists, 1 otherwise
adb_dir_exists() {
    local remote_path="$1"
    local result
    result=$(adb_root_exec "test -d '$remote_path' && echo 'exists'")
    
    if [ "$result" = "exists" ]; then
        return 0
    else
        return 1
    fi
}

# Create directory on Android device
# Args: $1 - remote directory path
# Returns: 0 on success, 1 on failure
adb_ensure_directory() {
    local remote_path="$1"
    
    if ! adb_dir_exists "$remote_path"; then
        adb_root_exec "mkdir -p '$remote_path'"
        
        if ! adb_dir_exists "$remote_path"; then
            echo "Error: Failed to create directory: $remote_path"
            return 1
        fi
    fi
    
    return 0
}

# Push file to Android device
# Args: $1 - local file path, $2 - remote file path
# Returns: 0 on success, 1 on failure
adb_push_file() {
    local local_path="$1"
    local remote_path="$2"
    
    if [ ! -f "$local_path" ]; then
        echo "Error: Local file not found: $local_path"
        return 1
    fi
    
    # Push to temporary location first (no root needed)
    local temp_path="/data/local/tmp/$(basename "$remote_path")"
    if ! adb push "$local_path" "$temp_path" >/dev/null 2>&1; then
        echo "Error: Failed to push file: $local_path"
        return 1
    fi
    
    # Move to final location with root
    adb_root_exec "mv '$temp_path' '$remote_path'"
    adb_root_exec "chmod 755 '$remote_path'"
    
    return 0
}

# Pull file from Android device
# Args: $1 - remote file path, $2 - local file path
# Returns: 0 on success, 1 on failure
adb_pull_file() {
    local remote_path="$1"
    local local_path="$2"
    
    if ! adb_file_exists "$remote_path"; then
        echo "Error: Remote file not found: $remote_path"
        return 1
    fi
    
    # Copy to temporary location with world-readable permissions
    local temp_path="/data/local/tmp/pull_temp_$(basename "$remote_path")"
    adb_root_exec "cp '$remote_path' '$temp_path'"
    adb_root_exec "chmod 644 '$temp_path'"
    
    # Pull from temporary location
    if ! adb pull "$temp_path" "$local_path" >/dev/null 2>&1; then
        echo "Error: Failed to pull file: $remote_path"
        adb_root_exec "rm -f '$temp_path'"
        return 1
    fi
    
    # Clean up temporary file
    adb_root_exec "rm -f '$temp_path'"
    
    return 0
}

# Get PID of Android process by package name
# Args: $1 - package name
# Returns: PID (or empty if not found)
adb_get_pid() {
    local package="$1"
    local pid
    
    # Try pidof first (faster)
    pid=$(adb_root_exec "pidof '$package'" | tr -d '\r\n' | awk '{print $1}')
    
    if [ -z "$pid" ]; then
        # Fallback: search in ps output
        pid=$(adb_root_exec "ps -A | grep '$package' | head -1" | awk '{print $2}' | tr -d '\r\n')
    fi
    
    echo "$pid"
}

# Check if process is running
# Args: $1 - PID
# Returns: 0 if running, 1 otherwise
adb_is_process_running() {
    local pid="$1"
    local result
    result=$(adb_root_exec "kill -0 '$pid' 2>/dev/null && echo 'running'")
    
    if [ "$result" = "running" ]; then
        return 0
    else
        return 1
    fi
}

# Kill process by PID
# Args: $1 - PID, $2 - signal (optional, default: TERM)
# Returns: 0 on success, 1 on failure
adb_kill_process() {
    local pid="$1"
    local signal="${2:-TERM}"
    
    adb_root_exec "kill -$signal '$pid'"
    
    # Wait a bit and check if process is gone
    sleep 1
    
    if adb_is_process_running "$pid"; then
        # Try KILL if TERM didn't work
        if [ "$signal" = "TERM" ]; then
            adb_root_exec "kill -KILL '$pid'"
            sleep 1
        fi
    fi
    
    if adb_is_process_running "$pid"; then
        return 1
    fi
    
    return 0
}

# Wait for file to appear on Android device
# Args: $1 - remote file path, $2 - timeout in seconds (optional, default: 30)
# Returns: 0 if file appears, 1 on timeout
adb_wait_for_file() {
    local remote_path="$1"
    local timeout="${2:-30}"
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if adb_file_exists "$remote_path"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    
    echo "Error: Timeout waiting for file: $remote_path"
    return 1
}

# Initialize DAMOOS directory structure on Android device
# Returns: 0 on success, 1 on failure
adb_init_damoos_dirs() {
    echo "Initializing DAMOOS directories on Android device..."
    
    # Create main directories
    adb_ensure_directory "$ANDROID_DAMOOS_DIR" || return 1
    adb_ensure_directory "${ANDROID_DAMOOS_DIR}/scripts" || return 1
    adb_ensure_directory "${ANDROID_RESULTS_DIR}" || return 1
    adb_ensure_directory "${ANDROID_RESULTS_DIR}/rss" || return 1
    adb_ensure_directory "${ANDROID_RESULTS_DIR}/runtime" || return 1
    adb_ensure_directory "${ANDROID_RESULTS_DIR}/swapin" || return 1
    adb_ensure_directory "${ANDROID_RESULTS_DIR}/swapout" || return 1
    
    echo "DAMOOS directories initialized successfully."
    return 0
}

# Push metric collector scripts to Android device
# Args: $1 - DAMOOS root path on PC
# Returns: 0 on success, 1 on failure
adb_push_collector_scripts() {
    local damoos_path="$1"
    local collectors_dir="${damoos_path}/metrics_collector/collectors/android"
    
    if [ ! -d "$collectors_dir" ]; then
        echo "Error: Android collectors directory not found: $collectors_dir"
        return 1
    fi
    
    echo "Pushing metric collector scripts to Android device..."
    
    local scripts=(
        "rss_collector_android.sh"
        "runtime_collector_android.sh"
        "swapin_collector_android.sh"
        "swapout_collector_android.sh"
    )
    
    for script in "${scripts[@]}"; do
        local local_script="${collectors_dir}/${script}"
        local remote_script="${ANDROID_DAMOOS_DIR}/scripts/${script}"
        
        if [ -f "$local_script" ]; then
            adb_push_file "$local_script" "$remote_script" || return 1
            echo "  Pushed: $script"
        else
            echo "  Warning: Script not found: $local_script"
        fi
    done
    
    echo "Collector scripts pushed successfully."
    return 0
}

# Clean up all DAMOOS data on Android device
# Returns: 0 on success
adb_cleanup_damoos_data() {
    echo "Cleaning up DAMOOS data on Android device..."
    
    adb_root_exec "rm -rf ${ANDROID_RESULTS_DIR}/*"
    adb_root_exec "rm -f ${ANDROID_DAMOOS_DIR}/pid"
    
    echo "Cleanup completed."
    return 0
}

# Get Android device information
# Returns: Device info string
adb_get_device_info() {
    echo "=== Android Device Information ==="
    echo "Model: $(adb shell getprop ro.product.model | tr -d '\r')"
    echo "Android Version: $(adb shell getprop ro.build.version.release | tr -d '\r')"
    echo "Kernel Version: $(adb shell uname -r | tr -d '\r')"
    echo "Architecture: $(adb shell uname -m | tr -d '\r')"
    echo "=================================="
}

# Verify DAMON support on Android device
# Returns: 0 if DAMON is supported, 1 otherwise
adb_verify_damon_support() {
    echo "Verifying DAMON support on Android device..."
    
    # Check kernel config
    local config
    config=$(adb_root_exec "zcat /proc/config.gz 2>/dev/null | grep 'CONFIG_DAMON=y'")
    
    if [ -z "$config" ]; then
        echo "Error: DAMON not enabled in kernel config."
        return 1
    fi
    
    # Check debugfs
    local debugfs_damon
    debugfs_damon=$(adb_root_exec "ls /sys/kernel/debug/damon/ 2>/dev/null")
    
    if [ -z "$debugfs_damon" ]; then
        echo "Error: DAMON debugfs interface not available."
        echo "Please ensure debugfs is mounted."
        return 1
    fi
    
    echo "DAMON support verified successfully."
    echo "Available DAMON files:"
    echo "$debugfs_damon"
    
    return 0
}

# Export functions for use in other scripts
export -f adb_check_connection
export -f adb_check_root
export -f adb_root_exec
export -f adb_file_exists
export -f adb_dir_exists
export -f adb_ensure_directory
export -f adb_push_file
export -f adb_pull_file
export -f adb_get_pid
export -f adb_is_process_running
export -f adb_kill_process
export -f adb_wait_for_file
export -f adb_init_damoos_dirs
export -f adb_push_collector_scripts
export -f adb_cleanup_damoos_data
export -f adb_get_device_info
export -f adb_verify_damon_support
