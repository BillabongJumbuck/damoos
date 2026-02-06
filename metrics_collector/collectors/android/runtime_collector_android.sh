#!/system/bin/sh

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: GPL-2.0

# Runtime collector for Android
# Measures how long a process runs

PID=$1

if [ -z "$PID" ]; then
    echo "Usage: $0 <pid>"
    exit 1
fi

# Results directory
RESULTS_DIR="/data/local/tmp/damoos/results/runtime"
OUTPUT_FILE="${RESULTS_DIR}/${PID}.stat"

# Ensure results directory exists
mkdir -p "$RESULTS_DIR"

echo "Runtime Collector started for PID: $PID"
echo "Output: $OUTPUT_FILE"

# Record start time (seconds since epoch)
# Android may not have 'date +%s%N', so use seconds only
START_TIME=$(date +%s)

# Wait for process to finish
while kill -0 "$PID" 2>/dev/null; do
    sleep 1
done

# Record end time
END_TIME=$(date +%s)

# Calculate runtime in seconds
RUNTIME=$((END_TIME - START_TIME))

# Write runtime to file
echo "$RUNTIME" > "$OUTPUT_FILE"

echo "Runtime Collector finished for PID: $PID"
echo "Runtime: ${RUNTIME} seconds"
