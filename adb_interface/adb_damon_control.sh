#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: GPL-2.0

# DAMON control via debugfs interface for Android devices (Linux 5.10)

# Source utility functions if not already loaded
if ! command -v adb_root_exec >/dev/null 2>&1; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/adb_utils.sh"
fi

# DAMON debugfs paths
DAMON_DEBUGFS_BASE="/sys/kernel/debug/damon"
DAMON_MONITOR_ON="${DAMON_DEBUGFS_BASE}/monitor_on"
DAMON_TARGET_IDS="${DAMON_DEBUGFS_BASE}/target_ids"
DAMON_ATTRS="${DAMON_DEBUGFS_BASE}/attrs"
DAMON_SCHEMES="${DAMON_DEBUGFS_BASE}/schemes"

# Convert time string to microseconds
# Args: $1 - time string (e.g., "5s", "100ms", "1000000us")
# Returns: time in microseconds
time_to_microseconds() {
    local time_str="$1"
    
    # Handle special cases
    if [ "$time_str" = "min" ] || [ "$time_str" = "0" ]; then
        echo "0"
        return
    fi
    
    if [ "$time_str" = "max" ]; then
        echo "18446744073709551615"  # ULLONG_MAX
        return
    fi
    
    # Extract number and unit using regex
    if [[ $time_str =~ ^([0-9]+)(us|ms|s|m|h|d)$ ]]; then
        local number="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"
        
        # Convert to microseconds based on unit
        case "$unit" in
            us) echo "$number" ;;
            ms) echo $((number * 1000)) ;;
            s)  echo $((number * 1000000)) ;;
            m)  echo $((number * 60000000)) ;;
            h)  echo $((number * 3600000000)) ;;
            d)  echo $((number * 86400000000)) ;;
            *)  echo "$number" ;;
        esac
    else
        # Assume microseconds if no unit or unrecognized format
        echo "$time_str"
    fi
}

# Convert size string to bytes
# Args: $1 - size string (e.g., "4K", "1M", "1024B")
# Returns: size in bytes
size_to_bytes() {
    local size_str="$1"
    
    # Handle special cases
    if [ "$size_str" = "min" ] || [ "$size_str" = "0" ]; then
        echo "0"
        return
    fi
    
    if [ "$size_str" = "max" ]; then
        echo "18446744073709551615"  # ULLONG_MAX
        return
    fi
    
    # Extract number and unit using regex
    if [[ $size_str =~ ^([0-9]+)([BKMGT])$ ]]; then
        local number="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"
        
        # Convert to bytes based on unit
        case "$unit" in
            B) echo "$number" ;;
            K) echo $((number * 1024)) ;;
            M) echo $((number * 1048576)) ;;
            G) echo $((number * 1073741824)) ;;
            T) echo $((number * 1099511627776)) ;;
            *) echo "$number" ;;
        esac
    else
        # Assume bytes if no unit or unrecognized format
        echo "$size_str"
    fi
}

# Initialize DAMON (ensure it's stopped)
# Returns: 0 on success, 1 on failure
damon_init() {
    echo "Initializing DAMON..."
    
    # Check if DAMON debugfs exists
    if ! adb_root_exec "test -d '$DAMON_DEBUGFS_BASE'" >/dev/null 2>&1; then
        echo "Error: DAMON debugfs not found at $DAMON_DEBUGFS_BASE"
        echo "Please ensure DAMON is enabled in kernel and debugfs is mounted."
        return 1
    fi
    
    # Stop DAMON if running
    damon_stop >/dev/null 2>&1
    
    # Clear any previous configuration
    adb_root_exec "echo '' > '$DAMON_TARGET_IDS'" 2>/dev/null
    adb_root_exec "echo '' > '$DAMON_SCHEMES'" 2>/dev/null
    
    echo "DAMON initialized successfully."
    return 0
}

# Set DAMON target process
# Args: $1 - PID of target process
# Returns: 0 on success, 1 on failure
damon_set_target() {
    local pid="$1"
    
    if [ -z "$pid" ]; then
        echo "Error: PID not provided."
        return 1
    fi
    
    # Ensure DAMON is stopped before changing target
    damon_stop >/dev/null 2>&1
    
    echo "Setting DAMON target to PID: $pid"
    
    if ! adb_root_exec "echo '$pid' > '$DAMON_TARGET_IDS'"; then
        echo "Error: Failed to set DAMON target PID."
        return 1
    fi
    
    # Verify
    local current_target
    current_target=$(adb_root_exec "cat '$DAMON_TARGET_IDS'" | tr -d '\r\n ')
    
    if [ "$current_target" != "$pid" ]; then
        echo "Error: Failed to verify DAMON target (expected: $pid, got: $current_target)"
        return 1
    fi
    
    echo "DAMON target set successfully."
    return 0
}

# Set DAMON sampling attributes
# Args: $1 - sample_interval (us), $2 - aggr_interval (us), 
#       $3 - update_interval (us), $4 - min_nr_regions, $5 - max_nr_regions
# Returns: 0 on success, 1 on failure
damon_set_attrs() {
    local sample_interval="${1:-5000}"       # 5ms default
    local aggr_interval="${2:-100000}"      # 100ms default
    local update_interval="${3:-1000000}"   # 1s default
    local min_nr_regions="${4:-10}"         # 10 default
    local max_nr_regions="${5:-1000}"       # 1000 default
    
    # Ensure DAMON is stopped
    damon_stop >/dev/null 2>&1
    
    echo "Setting DAMON attributes..."
    echo "  sample_interval: ${sample_interval} us"
    echo "  aggr_interval: ${aggr_interval} us"
    echo "  update_interval: ${update_interval} us"
    echo "  regions: ${min_nr_regions} - ${max_nr_regions}"
    
    local attrs_str="${sample_interval} ${aggr_interval} ${update_interval} ${min_nr_regions} ${max_nr_regions}"
    
    if ! adb_root_exec "echo '$attrs_str' > '$DAMON_ATTRS'"; then
        echo "Error: Failed to set DAMON attributes."
        return 1
    fi
    
    echo "DAMON attributes set successfully."
    return 0
}

# Set DAMON scheme (DAMOS)
# Args: $1 - min_size, $2 - max_size, $3 - min_acc, $4 - max_acc,
#       $5 - min_age, $6 - max_age, $7 - action
# Returns: 0 on success, 1 on failure
damon_set_scheme() {
    local min_size="$1"
    local max_size="$2"
    local min_acc="$3"
    local max_acc="$4"
    local min_age="$5"
    local max_age="$6"
    local action="$7"
    
    # Validate inputs
    if [ -z "$action" ]; then
        echo "Error: Missing required parameters for DAMON scheme."
        echo "Usage: damon_set_scheme <min_size> <max_size> <min_acc> <max_acc> <min_age> <max_age> <action>"
        return 1
    fi
    
    # Ensure DAMON is stopped
    damon_stop >/dev/null 2>&1
    
    # Convert units
    local min_sz_bytes
    local max_sz_bytes
    local min_age_us
    local max_age_us
    
    min_sz_bytes=$(size_to_bytes "$min_size")
    max_sz_bytes=$(size_to_bytes "$max_size")
    min_age_us=$(time_to_microseconds "$min_age")
    max_age_us=$(time_to_microseconds "$max_age")
    
    echo "Setting DAMON scheme..."
    echo "  Size range: $min_size ($min_sz_bytes bytes) - $max_size ($max_sz_bytes bytes)"
    echo "  Access range: $min_acc - $max_acc"
    echo "  Age range: $min_age ($min_age_us us) - $max_age ($max_age_us us)"
    echo "  Action: $action"
    
    # Format: min_sz max_sz min_acc max_acc min_age max_age action
    local scheme_str="${min_sz_bytes} ${max_sz_bytes} ${min_acc} ${max_acc} ${min_age_us} ${max_age_us} ${action}"
    
    if ! adb_root_exec "echo '$scheme_str' > '$DAMON_SCHEMES'"; then
        echo "Error: Failed to set DAMON scheme."
        return 1
    fi
    
    echo "DAMON scheme set successfully."
    return 0
}

# Set DAMON scheme with quota (advanced)
# Note: Quota support may vary by kernel version
# For now, we implement basic scheme setting
# TODO: Add quota support if needed
damon_set_scheme_with_quota() {
    echo "Warning: Quota configuration not yet implemented for debugfs interface."
    echo "Falling back to basic scheme setting."
    damon_set_scheme "$@"
}

# Start DAMON monitoring
# Returns: 0 on success, 1 on failure
damon_start() {
    echo "Starting DAMON monitoring..."
    
    # Verify target is set
    local target
    target=$(adb_root_exec "cat '$DAMON_TARGET_IDS'" | tr -d '\r\n ')
    
    if [ -z "$target" ]; then
        echo "Error: No target PID set. Call damon_set_target first."
        return 1
    fi
    
    # Start monitoring
    if ! adb_root_exec "echo on > '$DAMON_MONITOR_ON'"; then
        echo "Error: Failed to start DAMON monitoring."
        return 1
    fi
    
    # Verify it's running
    sleep 0.5
    local status
    status=$(damon_get_status)
    
    if [ "$status" != "on" ]; then
        echo "Error: DAMON failed to start (status: $status)"
        return 1
    fi
    
    echo "DAMON monitoring started successfully."
    return 0
}

# Stop DAMON monitoring
# Returns: 0 on success
damon_stop() {
    local status
    status=$(damon_get_status)
    
    if [ "$status" = "on" ]; then
        echo "Stopping DAMON monitoring..."
        adb_root_exec "echo off > '$DAMON_MONITOR_ON'" 2>/dev/null
        
        # Wait a bit for it to stop
        sleep 0.5
        
        echo "DAMON monitoring stopped."
    fi
    
    return 0
}

# Get DAMON status
# Returns: "on" or "off"
damon_get_status() {
    local status
    status=$(adb_root_exec "cat '$DAMON_MONITOR_ON' 2>/dev/null" | tr -d '\r\n ')
    echo "${status:-off}"
}

# Get current DAMON configuration
# Returns: Configuration details
damon_get_config() {
    echo "=== DAMON Configuration ==="
    echo "Status: $(damon_get_status)"
    echo ""
    echo "Target PIDs:"
    adb_root_exec "cat '$DAMON_TARGET_IDS' 2>/dev/null" | tr -d '\r'
    echo ""
    echo "Attributes (sample aggr update min_regions max_regions):"
    adb_root_exec "cat '$DAMON_ATTRS' 2>/dev/null" | tr -d '\r'
    echo ""
    echo "Schemes (min_sz max_sz min_acc max_acc min_age max_age action):"
    adb_root_exec "cat '$DAMON_SCHEMES' 2>/dev/null" | tr -d '\r'
    echo "==========================="
}

# Apply a complete DAMON configuration and start monitoring
# Args: $1 - PID, $2 - min_size, $3 - max_size, $4 - min_age, $5 - max_age, $6 - action
# Returns: 0 on success, 1 on failure
damon_apply_and_start() {
    local pid="$1"
    local min_size="$2"
    local max_size="$3"
    local min_age="$4"
    local max_age="$5"
    local action="${6:-pageout}"
    
    # Use default access frequency range (0-100)
    local min_acc="0"
    local max_acc="100"
    
    echo "Applying DAMON configuration and starting..."
    
    # Initialize
    if ! damon_init; then
        return 1
    fi
    
    # Set default attributes (can be customized)
    if ! damon_set_attrs 5000 100000 1000000 10 1000; then
        return 1
    fi
    
    # Set target
    if ! damon_set_target "$pid"; then
        return 1
    fi
    
    # Set scheme
    if ! damon_set_scheme "$min_size" "$max_size" "$min_acc" "$max_acc" "$min_age" "$max_age" "$action"; then
        return 1
    fi
    
    # Start monitoring
    if ! damon_start; then
        return 1
    fi
    
    echo "DAMON applied and started successfully."
    return 0
}

# Export functions for use in other scripts
export -f time_to_microseconds
export -f size_to_bytes
export -f damon_init
export -f damon_set_target
export -f damon_set_attrs
export -f damon_set_scheme
export -f damon_set_scheme_with_quota
export -f damon_start
export -f damon_stop
export -f damon_get_status
export -f damon_get_config
export -f damon_apply_and_start
