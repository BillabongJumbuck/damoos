#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: GPL-2.0

# Test script for ADB Interface Layer (Phase 1)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAMOOS_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Print colored message
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_test() {
    echo -e "\n${YELLOW}[TEST] $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

print_skip() {
    echo -e "${YELLOW}⊘ $1${NC}"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Source the modules
source_modules() {
    print_header "Loading ADB Interface Modules"
    
    if [ ! -f "${SCRIPT_DIR}/adb_utils.sh" ]; then
        echo "Error: adb_utils.sh not found!"
        exit 1
    fi
    
    source "${SCRIPT_DIR}/adb_utils.sh"
    print_success "Loaded adb_utils.sh"
    
    source "${SCRIPT_DIR}/adb_damon_control.sh"
    print_success "Loaded adb_damon_control.sh"
    
    source "${SCRIPT_DIR}/adb_workload.sh"
    print_success "Loaded adb_workload.sh"
    
    source "${SCRIPT_DIR}/adb_metric_collector.sh"
    print_success "Loaded adb_metric_collector.sh"
}

# Test 1: ADB Connection
test_adb_connection() {
    print_header "Test 1: ADB Connection"
    
    print_test "Checking if ADB is installed"
    if command -v adb >/dev/null 2>&1; then
        print_success "ADB command found"
    else
        print_error "ADB command not found"
        return 1
    fi
    
    print_test "Checking ADB device connection"
    if adb_check_connection; then
        print_success "ADB device connected"
    else
        print_error "ADB device not connected"
        return 1
    fi
    
    print_test "Listing connected devices"
    adb devices
    
    return 0
}

# Test 2: Root Access
test_root_access() {
    print_header "Test 2: Root Access"
    
    print_test "Checking root access"
    if adb_check_root; then
        print_success "Root access available"
    else
        print_error "Root access not available"
        return 1
    fi
    
    print_test "Executing root command (id)"
    local result
    result=$(adb_root_exec "id")
    echo "$result"
    
    if echo "$result" | grep -q "uid=0"; then
        print_success "Root commands working"
    else
        print_error "Root commands not working"
        return 1
    fi
    
    return 0
}

# Test 3: Device Information
test_device_info() {
    print_header "Test 3: Device Information"
    
    print_test "Getting device information"
    adb_get_device_info
    print_success "Device info retrieved"
    
    return 0
}

# Test 4: DAMON Support
test_damon_support() {
    print_header "Test 4: DAMON Support Verification"
    
    print_test "Checking DAMON configuration"
    local config
    config=$(adb_root_exec "zcat /proc/config.gz 2>/dev/null | grep DAMON")
    
    if [ -n "$config" ]; then
        echo "$config"
        print_success "DAMON config found"
    else
        print_error "DAMON config not found"
        return 1
    fi
    
    print_test "Verifying DAMON support"
    if adb_verify_damon_support; then
        print_success "DAMON support verified"
    else
        print_error "DAMON support verification failed"
        return 1
    fi
    
    print_test "Checking DAMON debugfs files"
    adb_root_exec "ls -la /sys/kernel/debug/damon/" 2>/dev/null
    
    return 0
}

# Test 5: Directory Operations
test_directory_operations() {
    print_header "Test 5: Directory Operations"
    
    print_test "Creating DAMOOS directories"
    if adb_init_damoos_dirs; then
        print_success "DAMOOS directories created"
    else
        print_error "Failed to create DAMOOS directories"
        return 1
    fi
    
    print_test "Verifying directories exist"
    if adb_dir_exists "/data/local/tmp/damoos"; then
        print_success "Main DAMOOS directory exists"
    else
        print_error "Main DAMOOS directory missing"
        return 1
    fi
    
    if adb_dir_exists "/data/local/tmp/damoos/results/rss"; then
        print_success "RSS results directory exists"
    else
        print_error "RSS results directory missing"
        return 1
    fi
    
    print_test "Listing DAMOOS directory structure"
    adb_root_exec "ls -R /data/local/tmp/damoos/"
    
    return 0
}

# Test 6: File Operations
test_file_operations() {
    print_header "Test 6: File Operations"
    
    # Create a test file locally
    local test_file="/tmp/damoos_test_file.txt"
    echo "DAMOOS Test File $(date)" > "$test_file"
    
    print_test "Pushing test file to device"
    if adb_push_file "$test_file" "/data/local/tmp/damoos/test.txt"; then
        print_success "File pushed successfully"
    else
        print_error "Failed to push file"
        return 1
    fi
    
    print_test "Checking if file exists on device"
    if adb_file_exists "/data/local/tmp/damoos/test.txt"; then
        print_success "File exists on device"
    else
        print_error "File does not exist on device"
        return 1
    fi
    
    print_test "Pulling file back from device"
    local pulled_file="/tmp/damoos_test_pulled.txt"
    if adb_pull_file "/data/local/tmp/damoos/test.txt" "$pulled_file"; then
        print_success "File pulled successfully"
    else
        print_error "Failed to pull file"
        return 1
    fi
    
    print_test "Verifying file contents"
    if diff -q "$test_file" "$pulled_file" >/dev/null 2>&1; then
        print_success "File contents match"
    else
        print_error "File contents do not match"
    fi
    
    # Cleanup
    rm -f "$test_file" "$pulled_file"
    adb_root_exec "rm -f /data/local/tmp/damoos/test.txt"
    
    return 0
}

# Test 7: DAMON Control Functions
test_damon_control() {
    print_header "Test 7: DAMON Control Functions"
    
    print_test "Testing unit conversion (time_to_microseconds)"
    local result
    result=$(time_to_microseconds "5s")
    if [ "$result" = "5000000" ]; then
        print_success "5s → 5000000 us (correct)"
    else
        print_error "5s → $result us (expected 5000000)"
    fi
    
    result=$(time_to_microseconds "100ms")
    if [ "$result" = "100000" ]; then
        print_success "100ms → 100000 us (correct)"
    else
        print_error "100ms → $result us (expected 100000)"
    fi
    
    print_test "Testing unit conversion (size_to_bytes)"
    result=$(size_to_bytes "4K")
    if [ "$result" = "4096" ]; then
        print_success "4K → 4096 bytes (correct)"
    else
        print_error "4K → $result bytes (expected 4096)"
    fi
    
    result=$(size_to_bytes "1M")
    if [ "$result" = "1048576" ]; then
        print_success "1M → 1048576 bytes (correct)"
    else
        print_error "1M → $result bytes (expected 1048576)"
    fi
    
    print_test "Initializing DAMON"
    if damon_init; then
        print_success "DAMON initialized"
    else
        print_error "DAMON initialization failed"
        return 1
    fi
    
    print_test "Getting DAMON status"
    local status
    status=$(damon_get_status)
    echo "Current status: $status"
    if [ "$status" = "on" ] || [ "$status" = "off" ]; then
        print_success "DAMON status retrieved: $status"
    else
        print_error "Invalid DAMON status: $status"
    fi
    
    print_test "Getting DAMON configuration"
    damon_get_config
    
    return 0
}

# Test 8: Workload Management (if app is available)
test_workload_management() {
    print_header "Test 8: Workload Management"
    
    print_test "Checking for installed packages"
    local packages
    packages=$(get_running_packages | head -5)
    if [ -n "$packages" ]; then
        echo "Sample running packages:"
        echo "$packages"
        print_success "Package listing works"
    else
        print_skip "No packages found or command failed"
    fi
    
    print_test "Testing package check (com.android.settings)"
    if is_package_installed "com.android.settings"; then
        print_success "Settings app is installed"
        
        print_test "Getting package info"
        get_package_info "com.android.settings"
    else
        print_skip "Settings app not found (this is unusual)"
    fi
    
    # Ask user if they want to test with a real app
    echo ""
    read -p "Do you want to test app launch with a specific package? (y/n): " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        read -p "Enter package name (e.g., com.android.settings): " pkg
        read -p "Enter activity (or press Enter to use monkey): " activity
        
        if [ -n "$pkg" ]; then
            print_test "Starting app: $pkg"
            if start_android_app "$pkg" "$activity"; then
                print_success "App started"
                
                sleep 2
                
                print_test "Getting app PID"
                local pid
                pid=$(get_app_pid "$pkg")
                if [ -n "$pid" ]; then
                    echo "PID: $pid"
                    print_success "PID retrieved"
                    
                    print_test "Checking if app is running"
                    if is_app_running "$pkg"; then
                        print_success "App is running"
                    fi
                    
                    print_test "Getting app memory usage"
                    local mem
                    mem=$(get_app_memory_usage "$pid")
                    echo "Memory usage: ${mem} KB"
                else
                    print_error "Failed to get PID"
                fi
                
                read -p "Stop the app? (y/n): " stop_answer
                if [[ "$stop_answer" =~ ^[Yy]$ ]]; then
                    stop_android_app "$pkg"
                    print_success "App stopped"
                fi
            else
                print_error "Failed to start app"
            fi
        fi
    else
        print_skip "App launch test skipped by user"
    fi
    
    return 0
}

# Test 9: DAMON Advanced (with real PID)
test_damon_advanced() {
    print_header "Test 9: DAMON Advanced Control (Optional)"
    
    echo ""
    read -p "Do you want to test DAMON with a real process? (y/n): " answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        print_skip "DAMON advanced test skipped by user"
        return 0
    fi
    
    read -p "Enter package name to monitor (e.g., com.android.settings): " pkg
    
    if [ -z "$pkg" ]; then
        print_skip "No package provided"
        return 0
    fi
    
    print_test "Starting app: $pkg"
    start_android_app "$pkg" ""
    sleep 3
    
    local pid
    pid=$(get_app_pid "$pkg")
    
    if [ -z "$pid" ]; then
        print_error "Failed to get PID for $pkg"
        return 1
    fi
    
    echo "PID: $pid"
    
    print_test "Setting DAMON target to PID $pid"
    if damon_set_target "$pid"; then
        print_success "DAMON target set"
    else
        print_error "Failed to set DAMON target"
        return 1
    fi
    
    print_test "Setting DAMON attributes"
    if damon_set_attrs 5000 100000 1000000 10 1000; then
        print_success "DAMON attributes set"
    else
        print_error "Failed to set DAMON attributes"
    fi
    
    print_test "Setting DAMON scheme (4K-max, 5s-max, pageout)"
    if damon_set_scheme "4K" "max" "0" "100" "5s" "max" "pageout"; then
        print_success "DAMON scheme set"
    else
        print_error "Failed to set DAMON scheme"
    fi
    
    print_test "Getting DAMON configuration"
    damon_get_config
    
    print_test "Starting DAMON monitoring"
    if damon_start; then
        print_success "DAMON started"
        
        echo "DAMON is now monitoring PID $pid for 10 seconds..."
        sleep 10
        
        print_test "Stopping DAMON monitoring"
        damon_stop
        print_success "DAMON stopped"
    else
        print_error "Failed to start DAMON"
    fi
    
    read -p "Stop the app? (y/n): " stop_answer
    if [[ "$stop_answer" =~ ^[Yy]$ ]]; then
        stop_android_app "$pkg"
        print_success "App stopped"
    fi
    
    return 0
}

# Main test suite
main() {
    print_header "DAMOOS ADB Interface Test Suite (Phase 1)"
    echo "This script will test all components of the ADB interface layer."
    echo ""
    
    # Source modules
    source_modules
    
    # Run tests
    test_adb_connection || { echo "Critical: ADB connection failed. Cannot continue."; exit 1; }
    test_root_access || { echo "Critical: Root access failed. Cannot continue."; exit 1; }
    test_device_info
    test_damon_support || { echo "Warning: DAMON not supported on this device."; }
    test_directory_operations
    test_file_operations
    test_damon_control
    test_workload_management
    test_damon_advanced
    
    # Summary
    print_header "Test Summary"
    echo -e "${GREEN}Passed:  $TESTS_PASSED${NC}"
    echo -e "${RED}Failed:  $TESTS_FAILED${NC}"
    echo -e "${YELLOW}Skipped: $TESTS_SKIPPED${NC}"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed! ADB interface is working correctly.${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed. Please review the output above.${NC}"
        return 1
    fi
}

# Run main
main "$@"
