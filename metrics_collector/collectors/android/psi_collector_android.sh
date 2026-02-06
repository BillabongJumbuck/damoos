#!/system/bin/sh

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: GPL-2.0

# PSI (Pressure Stall Information) collector for Android
# Collects memory pressure metrics every second
# PSI provides more accurate pressure information than traditional swap metrics

PID=$1

if [ -z "$PID" ]; then
    echo "Usage: $0 <pid>"
    exit 1
fi

# Results directory
RESULTS_DIR="/data/local/tmp/damoos/results/psi"
OUTPUT_FILE="${RESULTS_DIR}/${PID}.stat"

# Ensure results directory exists
mkdir -p "$RESULTS_DIR"

# Clear any existing file
> "$OUTPUT_FILE"

echo "PSI Collector started for PID: $PID"
echo "Output: $OUTPUT_FILE"

# PSI file location
PSI_FILE="/proc/pressure/memory"

# Check if PSI is available
if [ ! -r "$PSI_FILE" ]; then
    echo "Error: PSI not available at $PSI_FILE"
    echo "PSI requires kernel 4.20+ with CONFIG_PSI=y"
    exit 1
fi

# Header: Timestamp Some_avg10 Some_avg60 Some_avg300 Some_total Full_avg10 Full_avg60 Full_avg300 Full_total
echo "timestamp some_avg10 some_avg60 some_avg300 some_total full_avg10 full_avg60 full_avg300 full_total" > "$OUTPUT_FILE"

# Collect PSI every second while process is running
while kill -0 "$PID" 2>/dev/null; do
    TIMESTAMP=$(date +%s)
    
    # Parse PSI memory file
    # Format:
    # some avg10=0.00 avg60=0.00 avg300=0.00 total=123456
    # full avg10=0.00 avg60=0.00 avg300=0.00 total=789012
    
    PSI_DATA=$(cat "$PSI_FILE")
    
    # Extract 'some' line values
    SOME_LINE=$(echo "$PSI_DATA" | grep "^some")
    SOME_AVG10=$(echo "$SOME_LINE" | sed -n 's/.*avg10=\([0-9.]*\).*/\1/p')
    SOME_AVG60=$(echo "$SOME_LINE" | sed -n 's/.*avg60=\([0-9.]*\).*/\1/p')
    SOME_AVG300=$(echo "$SOME_LINE" | sed -n 's/.*avg300=\([0-9.]*\).*/\1/p')
    SOME_TOTAL=$(echo "$SOME_LINE" | sed -n 's/.*total=\([0-9]*\).*/\1/p')
    
    # Extract 'full' line values
    FULL_LINE=$(echo "$PSI_DATA" | grep "^full")
    FULL_AVG10=$(echo "$FULL_LINE" | sed -n 's/.*avg10=\([0-9.]*\).*/\1/p')
    FULL_AVG60=$(echo "$FULL_LINE" | sed -n 's/.*avg60=\([0-9.]*\).*/\1/p')
    FULL_AVG300=$(echo "$FULL_LINE" | sed -n 's/.*avg300=\([0-9.]*\).*/\1/p')
    FULL_TOTAL=$(echo "$FULL_LINE" | sed -n 's/.*total=\([0-9]*\).*/\1/p')
    
    # Write to output file
    echo "$TIMESTAMP $SOME_AVG10 $SOME_AVG60 $SOME_AVG300 $SOME_TOTAL $FULL_AVG10 $FULL_AVG60 $FULL_AVG300 $FULL_TOTAL" >> "$OUTPUT_FILE"
    
    sleep 1
done

echo "PSI Collector stopped (process $PID terminated)"
