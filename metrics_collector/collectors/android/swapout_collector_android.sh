#!/system/bin/sh

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: GPL-2.0

# Swapout collector for Android
# Collects system-wide swap-out statistics while process is running

PID=$1

if [ -z "$PID" ]; then
    echo "Usage: $0 <pid>"
    exit 1
fi

# Results directory
RESULTS_DIR="/data/local/tmp/damoos/results/swapout"
OUTPUT_FILE="${RESULTS_DIR}/${PID}.stat"

# Ensure results directory exists
mkdir -p "$RESULTS_DIR"

# Clear any existing file
> "$OUTPUT_FILE"

echo "Swapout Collector started for PID: $PID"
echo "Output: $OUTPUT_FILE"

# Collect swapout statistics every second while process is running
while kill -0 "$PID" 2>/dev/null; do
    # Get pswpout from /proc/vmstat (pages swapped out)
    SWAPOUT=$(grep "^pswpout " /proc/vmstat 2>/dev/null | awk '{print $2}')
    
    # If we couldn't get the value, try alternative
    if [ -z "$SWAPOUT" ]; then
        SWAPOUT=$(cat /proc/vmstat 2>/dev/null | grep pswpout | awk '{print $2}')
    fi
    
    # Write value (or 0 if not available)
    if [ -n "$SWAPOUT" ]; then
        echo "$SWAPOUT" >> "$OUTPUT_FILE"
    else
        echo "0" >> "$OUTPUT_FILE"
    fi
    
    sleep 1
done

echo "Swapout Collector finished for PID: $PID"
echo "Collected $(wc -l < "$OUTPUT_FILE") samples"
