#!/system/bin/sh

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: GPL-2.0

# Refault collector for Android
# Collects workingset refault rate (pages/second) during process lifetime
# This measures how often evicted pages need to be refaulted back into memory

PID=$1

if [ -z "$PID" ]; then
    echo "Usage: $0 <pid>"
    exit 1
fi

# Results directory
RESULTS_DIR="/data/local/tmp/damoos/results/refault"
OUTPUT_FILE="${RESULTS_DIR}/${PID}.stat"

# Ensure results directory exists
mkdir -p "$RESULTS_DIR"

# Clear any existing file
> "$OUTPUT_FILE"

echo "Refault Collector started for PID: $PID"
echo "Output: $OUTPUT_FILE"

# Get initial refault count (anon + file)
get_total_refaults() {
    ANON=$(grep "workingset_refault_anon" /proc/vmstat | awk '{print $2}')
    FILE=$(grep "workingset_refault_file" /proc/vmstat | awk '{print $2}')
    echo $((ANON + FILE))
}

PREV_REFAULTS=$(get_total_refaults)
PREV_TIME=$(date +%s)

# Collect refault rate every second while process is running
while kill -0 "$PID" 2>/dev/null; do
    sleep 1
    
    CURR_REFAULTS=$(get_total_refaults)
    CURR_TIME=$(date +%s)
    
    TIME_DIFF=$((CURR_TIME - PREV_TIME))
    if [ "$TIME_DIFF" -gt 0 ]; then
        REFAULT_DIFF=$((CURR_REFAULTS - PREV_REFAULTS))
        REFAULT_RATE=$((REFAULT_DIFF / TIME_DIFF))
        
        # Write refault rate (pages/second)
        echo "$REFAULT_RATE" >> "$OUTPUT_FILE"
        
        PREV_REFAULTS=$CURR_REFAULTS
        PREV_TIME=$CURR_TIME
    fi
done

echo "Refault Collector finished for PID: $PID"
echo "Collected $(wc -l < "$OUTPUT_FILE") samples"
