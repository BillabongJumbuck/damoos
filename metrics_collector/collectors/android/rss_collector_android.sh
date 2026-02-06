#!/system/bin/sh

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: GPL-2.0

# RSS (Residential Set Size) collector for Android
# Collects memory usage of a process every second

PID=$1

if [ -z "$PID" ]; then
    echo "Usage: $0 <pid>"
    exit 1
fi

# Results directory
RESULTS_DIR="/data/local/tmp/damoos/results/rss"
OUTPUT_FILE="${RESULTS_DIR}/${PID}.stat"

# Ensure results directory exists
mkdir -p "$RESULTS_DIR"

# Clear any existing file
> "$OUTPUT_FILE"

echo "RSS Collector started for PID: $PID"
echo "Output: $OUTPUT_FILE"

# Collect RSS every second while process is running
while kill -0 "$PID" 2>/dev/null; do
    # Method 1: Try to get RSS from /proc/PID/status (most reliable)
    RSS=$(grep "VmRSS:" "/proc/${PID}/status" 2>/dev/null | awk '{print $2}')
    
    # Method 2: Fallback to ps command if /proc fails
    if [ -z "$RSS" ] || [ "$RSS" = "0" ]; then
        # Android ps format may vary, try different formats
        RSS=$(ps -p "$PID" -o rss= 2>/dev/null | tr -d ' ' | head -1)
    fi
    
    # Method 3: Another ps format
    if [ -z "$RSS" ] || [ "$RSS" = "0" ]; then
        RSS=$(ps -A | grep "^[^0-9]*${PID} " | awk '{print $5}' | head -1)
    fi
    
    # If we got a value, write it
    if [ -n "$RSS" ] && [ "$RSS" != "0" ]; then
        echo "$RSS" >> "$OUTPUT_FILE"
    else
        # Write 0 if we couldn't get RSS
        echo "0" >> "$OUTPUT_FILE"
    fi
    
    sleep 1
done

echo "RSS Collector finished for PID: $PID"
echo "Collected $(wc -l < "$OUTPUT_FILE") samples"
