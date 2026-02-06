#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: GPL-2.0

# Android workload (application) management via ADB

# Source utility functions if not already loaded
if ! command -v adb_root_exec >/dev/null 2>&1; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/adb_utils.sh"
fi

# Start Android application
# Args: $1 - package name, $2 - activity name (optional, can be full component or "")
# Returns: 0 on success, 1 on failure
start_android_app() {
    local package="$1"
    local activity="$2"
    
    if [ -z "$package" ]; then
        echo "Error: Package name not provided."
        return 1
    fi
    
    echo "Starting Android app: $package"
    
    # Stop app first to ensure clean start
    stop_android_app "$package" >/dev/null 2>&1
    sleep 1
    
    # Start the application
    if [ -n "$activity" ]; then
        # Use specified activity
        if [[ "$activity" == *"/"* ]]; then
            # Full component name (e.g., com.example.app/.MainActivity)
            adb shell "am start -n '$activity'" >/dev/null 2>&1
        else
            # Just activity name, prepend package
            adb shell "am start -n '${package}/${activity}'" >/dev/null 2>&1
        fi
    else
        # Use monkey to start with main activity
        adb shell "monkey -p '$package' -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1
    fi
    
    # Wait a bit for app to start
    sleep 2
    
    # Verify app is running
    if ! is_app_running "$package"; then
        echo "Error: Failed to start app: $package"
        return 1
    fi
    
    echo "App started successfully: $package"
    return 0
}

# Stop Android application
# Args: $1 - package name
# Returns: 0 on success
stop_android_app() {
    local package="$1"
    
    if [ -z "$package" ]; then
        echo "Error: Package name not provided."
        return 1
    fi
    
    echo "Stopping Android app: $package"
    
    adb shell "am force-stop '$package'" >/dev/null 2>&1
    
    # Wait a bit to ensure it's stopped
    sleep 1
    
    echo "App stopped: $package"
    return 0
}

# Check if Android application is running
# Args: $1 - package name
# Returns: 0 if running, 1 otherwise
is_app_running() {
    local package="$1"
    
    if [ -z "$package" ]; then
        return 1
    fi
    
    local pid
    pid=$(get_app_pid "$package")
    
    if [ -n "$pid" ] && [ "$pid" != "0" ]; then
        return 0
    else
        return 1
    fi
}

# Get main process PID of Android application
# Args: $1 - package name
# Returns: PID (or empty if not found)
get_app_pid() {
    local package="$1"
    
    if [ -z "$package" ]; then
        echo ""
        return
    fi
    
    # Method 1: Use pidof with package name
    local pid
    pid=$(adb_root_exec "pidof '$package'" | tr -d '\r\n' | awk '{print $1}')
    
    if [ -n "$pid" ] && [ "$pid" != "0" ]; then
        echo "$pid"
        return
    fi
    
    # Method 2: Search ps for package name
    pid=$(adb shell "ps -A | grep '$package' | grep -v ':' | head -1" 2>/dev/null | awk '{print $2}' | tr -d '\r\n')
    
    if [ -n "$pid" ] && [ "$pid" != "0" ]; then
        echo "$pid"
        return
    fi
    
    # Method 3: Use dumpsys activity
    pid=$(adb shell "dumpsys activity | grep -A 10 'mResumedActivity' | grep '$package' | head -1" 2>/dev/null | \
          grep -oP '\d+:'"$package" | cut -d: -f1 | tr -d '\r\n')
    
    if [ -n "$pid" ] && [ "$pid" != "0" ]; then
        echo "$pid"
        return
    fi
    
    echo ""
}

# Wait for Android application to be fully started
# Args: $1 - package name, $2 - timeout in seconds (optional, default: 60)
# Returns: 0 if app started, 1 on timeout
wait_for_app_ready() {
    local package="$1"
    local timeout="${2:-60}"
    local elapsed=0
    
    echo "Waiting for app to be ready: $package (timeout: ${timeout}s)"
    
    while [ $elapsed -lt $timeout ]; do
        if is_app_running "$package"; then
            # Additional check: ensure app has a valid PID and is responsive
            local pid
            pid=$(get_app_pid "$package")
            
            if [ -n "$pid" ] && [ "$pid" != "0" ]; then
                # Wait a bit more to ensure app is fully initialized
                sleep 3
                
                # Check if still running
                if is_app_running "$package"; then
                    echo "App is ready: $package (PID: $pid)"
                    return 0
                fi
            fi
        fi
        
        sleep 2
        elapsed=$((elapsed + 2))
        
        # Show progress every 10 seconds
        if [ $((elapsed % 10)) -eq 0 ]; then
            echo "  Still waiting... (${elapsed}s/${timeout}s)"
        fi
    done
    
    echo "Error: Timeout waiting for app to start: $package"
    return 1
}

# Wait for Android application to finish/stop
# Args: $1 - package name, $2 - timeout in seconds (optional, 0 = no timeout)
# Returns: 0 when app stops, 1 on timeout
wait_for_app_finish() {
    local package="$1"
    local timeout="${2:-0}"
    local elapsed=0
    
    echo "Waiting for app to finish: $package"
    
    while is_app_running "$package"; do
        sleep 1
        elapsed=$((elapsed + 1))
        
        # Check timeout
        if [ $timeout -gt 0 ] && [ $elapsed -ge $timeout ]; then
            echo "Timeout waiting for app to finish: $package"
            return 1
        fi
        
        # Show progress every 30 seconds
        if [ $((elapsed % 30)) -eq 0 ]; then
            echo "  App still running... (${elapsed}s)"
        fi
    done
    
    echo "App finished: $package (ran for ${elapsed}s)"
    return 0
}

# Get list of all running packages
# Returns: List of package names
get_running_packages() {
    adb shell "ps -A" 2>/dev/null | grep -oP 'com\.[a-zA-Z0-9._]+' | sort -u
}

# Check if package is installed
# Args: $1 - package name
# Returns: 0 if installed, 1 otherwise
is_package_installed() {
    local package="$1"
    
    local result
    result=$(adb shell "pm list packages | grep '$package'" 2>/dev/null)
    
    if [ -n "$result" ]; then
        return 0
    else
        return 1
    fi
}

# Get package information
# Args: $1 - package name
# Returns: Package details
get_package_info() {
    local package="$1"
    
    echo "=== Package Information: $package ==="
    
    if ! is_package_installed "$package"; then
        echo "Package not installed."
        return 1
    fi
    
    # Get package path
    local apk_path
    apk_path=$(adb shell "pm path '$package'" 2>/dev/null | cut -d: -f2 | tr -d '\r\n')
    echo "APK Path: $apk_path"
    
    # Get version
    local version
    version=$(adb shell "dumpsys package '$package' | grep versionName" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '\r\n')
    echo "Version: $version"
    
    # Check if running
    if is_app_running "$package"; then
        local pid
        pid=$(get_app_pid "$package")
        echo "Status: Running (PID: $pid)"
    else
        echo "Status: Not running"
    fi
    
    echo "======================================"
}

# Launch app with intent extras (for testing with parameters)
# Args: $1 - package, $2 - activity, $3... - intent extras
# Returns: 0 on success, 1 on failure
start_android_app_with_extras() {
    local package="$1"
    local activity="$2"
    shift 2
    local extras="$*"
    
    echo "Starting Android app with extras: $package $activity"
    echo "Extras: $extras"
    
    # Stop app first
    stop_android_app "$package" >/dev/null 2>&1
    sleep 1
    
    # Build component name
    local component
    if [[ "$activity" == *"/"* ]]; then
        component="$activity"
    else
        component="${package}/${activity}"
    fi
    
    # Start with extras
    adb shell "am start -n '$component' $extras" >/dev/null 2>&1
    
    sleep 2
    
    if ! is_app_running "$package"; then
        echo "Error: Failed to start app with extras"
        return 1
    fi
    
    echo "App started with extras successfully"
    return 0
}

# Bring app to foreground
# Args: $1 - package name
# Returns: 0 on success, 1 on failure
bring_app_to_foreground() {
    local package="$1"
    
    if ! is_app_running "$package"; then
        echo "Error: App not running: $package"
        return 1
    fi
    
    echo "Bringing app to foreground: $package"
    
    # Use monkey to bring to front
    adb shell "monkey -p '$package' -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1
    
    sleep 1
    return 0
}

# Clear app data and cache
# Args: $1 - package name
# Returns: 0 on success
clear_app_data() {
    local package="$1"
    
    echo "Clearing app data: $package"
    
    # Stop app first
    stop_android_app "$package"
    
    # Clear data
    adb shell "pm clear '$package'" >/dev/null 2>&1
    
    echo "App data cleared: $package"
    return 0
}

# Get app memory usage (RSS)
# Args: $1 - package name or PID
# Returns: RSS in KB
get_app_memory_usage() {
    local target="$1"
    
    # Check if it's a PID or package name
    local pid
    if [[ "$target" =~ ^[0-9]+$ ]]; then
        pid="$target"
    else
        pid=$(get_app_pid "$target")
    fi
    
    if [ -z "$pid" ]; then
        echo "0"
        return
    fi
    
    # Get RSS from dumpsys meminfo
    local rss
    rss=$(adb shell "dumpsys meminfo '$pid' | grep 'TOTAL RSS' | awk '{print \$3}'" 2>/dev/null | tr -d '\r\n')
    
    if [ -z "$rss" ]; then
        # Fallback: read from /proc
        rss=$(adb_root_exec "cat /proc/${pid}/status | grep VmRSS | awk '{print \$2}'" | tr -d '\r\n')
    fi
    
    echo "${rss:-0}"
}

# Parse workload command for Android apps
# Args: $1 - command string from workload_directory.txt
# Returns: Executes the command (am start or monkey)
execute_workload_command() {
    local command="$1"
    
    # Execute the command
    # Note: This will be a command like "am start -n pkg/.Activity"
    # or "monkey -p pkg 1"
    adb shell "$command" >/dev/null 2>&1
    
    return $?
}

# Export functions for use in other scripts
export -f start_android_app
export -f stop_android_app
export -f is_app_running
export -f get_app_pid
export -f wait_for_app_ready
export -f wait_for_app_finish
export -f get_running_packages
export -f is_package_installed
export -f get_package_info
export -f start_android_app_with_extras
export -f bring_app_to_foreground
export -f clear_app_data
export -f get_app_memory_usage
export -f execute_workload_command
