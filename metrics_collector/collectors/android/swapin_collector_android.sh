#!/system/bin/sh

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: GPL-2.0

# Swapin collector for Android
# Collects system-wide swap-in statistics while process is running

PID=$1

if [ -z "$PID" ]; then
    echo "Usage: $0 <pid>"
    exit 1
fi

# Results directory
RESULTS_DIR="/data/local/tmp/damoos/results/swapin"
OUTPUT_FILE="${RESULTS_DIR}/${PID}.stat"

# Ensure results directory exists
mkdir -p "$RESULTS_DIR"

# Clear any existing file
> "$OUTPUT_FILE"

echo "Swapin Collector started for PID: $PID"
echo "Output: $OUTPUT_FILE"

# Collect swapin statistics every second while process is running
while kill -0 "$PID" 2>/dev/null; do
    # Get pswpin from /proc/vmstat (pages swapped in)
    SWAPIN=$(grep "^pswpin " /proc/vmstat 2>/dev/null | awk '{print $2}')
    
    # If we couldn't get the value, try alternative
    if [ -z "$SWAPIN" ]; then
        SWAPIN=$(cat /proc/vmstat 2>/dev/null | grep pswpin | awk '{print $2}')
    fi
    
    # Write value (or 0 if not available)
    if [ -n "$SWAPIN" ]; then
        echo "$SWAPIN" >> "$OUTPUT_FILE"
    else
        echo "0" >> "$OUTPUT_FILE"
    fi
    
    sleep 1
done

echo "Swapin Collector finished for PID: $PID"
echo "Collected $(wc -l < "$OUTPUT_FILE") samples"
