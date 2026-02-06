# Android Metric Collectors

These scripts run on Android devices to collect performance metrics.

## Scripts

### 1. rss_collector_android.sh
Collects Residential Set Size (RSS) memory usage of a process.

**Data Source:** `/proc/<pid>/status` (VmRSS field)  
**Update Interval:** 1 second  
**Output:** One RSS value (in KB) per line

### 2. runtime_collector_android.sh
Measures how long a process runs.

**Method:** Records start time, waits for process to finish, calculates duration  
**Output:** Single value - total runtime in seconds

### 3. swapin_collector_android.sh
Collects system-wide swap-in statistics.

**Data Source:** `/proc/vmstat` (pswpin field)  
**Update Interval:** 1 second  
**Output:** Cumulative number of pages swapped in, one value per second

### 4. swapout_collector_android.sh
Collects system-wide swap-out statistics.

**Data Source:** `/proc/vmstat` (pswpout field)  
**Update Interval:** 1 second  
**Output:** Cumulative number of pages swapped out, one value per second

### 5. psi_collector_android.sh
Collects memory Pressure Stall Information (PSI) metrics.

**Data Source:** `/proc/pressure/memory`  
**Update Interval:** 1 second  
**Output:** 9 columns per line (timestamp, some_avg10, some_avg60, some_avg300, some_total, full_avg10, full_avg60, full_avg300, full_total)

**PSI Metrics Explained:**
- **some**: Percentage of time at least one task was stalled on memory
- **full**: Percentage of time all non-idle tasks were stalled on memory  
- **avg10/60/300**: 10-second, 60-second, 300-second moving averages
- **total**: Total stall time in microseconds since boot

PSI provides more accurate memory pressure information than traditional swap metrics, especially useful for evaluating DAMON optimization effectiveness.

**Requirements:** Kernel 4.20+ with `CONFIG_PSI=y` (Android 10+ devices typically support this)

## Usage

These scripts are automatically pushed to `/data/local/tmp/damoos/scripts/` and executed remotely via ADB.

**Manual execution (for testing):**
```bash
# On Android device (via adb shell with root)
adb shell
su
cd /data/local/tmp/damoos/scripts

# Start a collector
./rss_collector_android.sh <pid> &

# Check output
cat /data/local/tmp/damoos/results/rss/<pid>.stat
```

## Output Location

All collectors write to:
```
/data/local/tmp/damoos/results/<metric>/<pid>.stat
```

Examples:
- `/data/local/tmp/damoos/results/rss/12345.stat`
- `/data/local/tmp/damoos/results/runtime/12345.stat`
- `/data/local/tmp/damoos/results/swapin/12345.stat`
- `/data/local/tmp/damoos/results/swapout/12345.stat`
- `/data/local/tmp/damoos/results/psi/12345.stat`

## Requirements

- **Shell:** `/system/bin/sh` (Android's default shell)
- **Permissions:** Root access required
- **Kernel:** Access to `/proc` filesystem

## Notes

### RSS Collector
- Uses multiple fallback methods to get RSS on different Android versions
- First tries `/proc/<pid>/status` (most reliable)
- Falls back to `ps` command if needed
- Writes "0" if process is not accessible

### Runtime Collector
- Uses `date +%s` (may have 1-second precision on some devices)
- Waits synchronously for process to finish
- Suitable for short-to-medium length workloads

### Swap Collectors
- Collects **system-wide** statistics (not per-process)
- Values are cumulative counters
- Use `get_diff_stat.sh` to get the difference o

### PSI Collector
- Requires kernel support: 4.20+ with `CONFIG_PSI=y`
- Provides real-time memory pressure metrics
- **some**: At least one task stalled (light pressure)
- **full**: All tasks stalled (severe pressure)
- More accurate than swap metrics for measuring memory contention
- Useful for evaluating if DAMON schemes reduce memory pressurever time
- May return "0" on devices without swap enabled

## Android Compatibility

These scripts are designed to work on:
- Android 5.0+ (API 21+)
- Kernel 3.18+ (better with 4.4+)
- POSIX-compliant busybox (if available)

Shell compatibility notes:
- Uses `#!/system/bin/sh` shebang
- Avoids bash-specific features
- Uses POSIX standard commands only

## Testing

Test individual collectors:
```bash
# From PC, push and test
adb push rss_collector_android.sh /data/local/tmp/
adb shell "su -c 'chmod 755 /data/local/tmp/rss_collector_android.sh'"

# Get PID of an app (e.g., Settings)
PID=$(adb shell "pidof com.android.settings")

# Run collector
adb shell "su -c '/data/local/tmp/rss_collector_android.sh $PID'" &

# Wait a bit
sleep 10

# Check output
adb shell "su -c 'cat /data/local/tmp/damoos/results/rss/${PID}.stat'"
```

## Troubleshooting

### "Permission denied"
- Ensure root access: `adb shell "su -c 'id'"`
- Check script permissions: `chmod 755 *.sh`

### "No such file or directory" 
- Ensure directories exist: `mkdir -p /data/local/tmp/damoos/results/{rss,runtime,swapin,swapout}`

### Empty output files
- Check if process is running: `ps -p <pid>`
- Verify `/proc` access: `ls -l /proc/<pid>/status`

### Swap collectors return all zeros
- Check if swap is enabled: `cat /proc/swaps`
- If no swap, these metrics won't be useful
