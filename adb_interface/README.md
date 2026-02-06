# ADB Interface

This directory contains scripts for interacting with Android devices via ADB (Android Debug Bridge).

## Purpose

Enable DAMOOS to run in a distributed PC-Android architecture:
- **PC side**: Run Scheme Adapters optimization algorithms
- **Android side**: Run workloads, collect metrics, apply DAMON schemes
- **Communication**: ADB protocol

## Components

### 1. `adb_utils.sh`
Common ADB utility functions for connection management, file operations, and process control.

**Key Functions:**
- `adb_check_connection()` - Verify ADB device connection
- `adb_check_root()` - Ensure root access
- `adb_push_scripts()` - Push scripts to device
- `adb_ensure_directory()` - Create remote directories
- `adb_get_pid()` - Get process ID by package name
- `adb_file_exists()` - Check if remote file exists

### 2. `adb_damon_control.sh`
Control DAMON via debugfs interface on Android (Linux 5.10 kernel).

**Key Functions:**
- `damon_init()` - Initialize DAMON subsystem
- `damon_set_target(pid)` - Set monitoring target process
- `damon_set_attrs(...)` - Configure sampling parameters
- `damon_set_scheme(...)` - Apply DAMOS scheme
- `damon_start()` - Start monitoring
- `damon_stop()` - Stop monitoring

**Interface:** `/sys/kernel/debug/damon/` (debugfs)

### 3. `adb_workload.sh`
Manage Android applications as workloads.

**Key Functions:**
- `start_android_app(pkg, activity)` - Launch application
- `stop_android_app(pkg)` - Force stop application
- `wait_for_app_ready(pkg)` - Wait for app startup
- `get_app_pid(pkg)` - Get main process PID
- `is_app_running(pkg)` - Check if app is active

### 4. `adb_metric_collector.sh`
Remote metric collection orchestration.

**Key Functions:**
- `start_remote_collector(metric, pid)` - Start collector on Android
- `stop_remote_collector(metric, pid)` - Stop remote collector
- `pull_metric_data(metric, pid)` - Pull data from device to PC
- `cleanup_remote_data()` - Clean up temporary files

## Prerequisites

- ADB installed on PC (`adb devices` should work)
- Android device connected (USB or WiFi)
- Root access on Android device
- DAMON enabled kernel (CONFIG_DAMON_DBGFS=y)
- Debugfs mounted at `/sys/kernel/debug/`

## Usage Example

```bash
# Source the utility functions
source adb_interface/adb_utils.sh

# Check connection
if ! adb_check_connection; then
    echo "ADB not connected!"
    exit 1
fi

# Source DAMON control
source adb_interface/adb_damon_control.sh

# Initialize DAMON
damon_init

# Start an Android app
source adb_interface/adb_workload.sh
start_android_app "com.miHoYo.Yuanshen" ".MainActivity"

# Get PID
pid=$(get_app_pid "com.miHoYo.Yuanshen")

# Set DAMON target
damon_set_target "$pid"

# Configure scheme
damon_set_scheme 4096 max 0 100 5000000 max pageout

# Start monitoring
damon_start

# ... workload runs, metrics collected ...

# Stop monitoring
damon_stop
```

## Android Device Setup

### 1. Enable ADB Debugging
```bash
# On Android device: Settings > Developer Options > USB Debugging
```

### 2. Verify Root Access
```bash
adb shell "su -c 'id'"
# Should output: uid=0(root) gid=0(root) ...
```

### 3. Check DAMON Support
```bash
adb shell "su -c 'zcat /proc/config.gz | grep DAMON'"
# Should show CONFIG_DAMON=y, CONFIG_DAMON_DBGFS=y, etc.
```

### 4. Verify Debugfs Mount
```bash
adb shell "su -c 'ls /sys/kernel/debug/damon/'"
# Should list: attrs, monitor_on, schemes, target_ids, etc.
```

### 5. Create Working Directory
```bash
adb shell "su -c 'mkdir -p /data/local/tmp/damoos/results/{rss,runtime,swapin,swapout}'"
```

## Troubleshooting

### ADB Connection Issues
```bash
# Restart ADB server
adb kill-server
adb start-server

# Check devices
adb devices

# If multiple devices, specify one
export ANDROID_SERIAL=<device_id>
```

### Permission Denied
```bash
# Ensure SELinux is permissive (if needed)
adb shell "su -c 'setenforce 0'"

# Check debugfs permissions
adb shell "su -c 'ls -l /sys/kernel/debug/damon/'"
```

### DAMON Not Available
```bash
# Verify kernel config
adb shell "su -c 'zcat /proc/config.gz | grep DAMON'"

# Check if debugfs is mounted
adb shell "su -c 'mount | grep debugfs'"
```

## Notes

- All remote operations require root (`su -c`)
- Old DAMON version (5.10) uses debugfs, not sysfs
- Must stop DAMON before modifying configuration
- PID changes every time app restarts
- Network ADB may be unstable for long operations
