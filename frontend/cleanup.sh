#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: GPL-2.0

# Cleanup the resources created by metric collectors

# Cleanup local metrics collectors
sudo DAMOOS="$DAMOOS" bash "$DAMOOS"/metrics_collector/cleanup.sh

# Cleanup Android/remote metrics collectors
# Check if we have Android metrics configured
has_android=$(grep -c "\-android" "$DAMOOS/frontend/metric_directory.txt" 2>/dev/null || echo 0)

if [ "$has_android" -gt 0 ]; then
	echo "Cleaning up Android metrics collectors..."
	
	# Source ADB modules if available
	if [ -f "$DAMOOS/adb_interface/adb_utils.sh" ]; then
		source "$DAMOOS/adb_interface/adb_utils.sh"
		source "$DAMOOS/adb_interface/adb_metric_collector.sh"
		
		# Check ADB connection before cleaning up
		if adb_check_connection 2>/dev/null; then
			cleanup_remote_data
		else
			echo "Warning: ADB not connected, skipping Android cleanup"
		fi
	fi
fi

# Cleanup results directory for all metric collectors
metrics=$(tail -n +2 "$DAMOOS/frontend/metric_directory.txt")
for metric in $metrics
do
	# Extract metric name (remove -local, -android, -host suffix)
	metric_name=$(echo "$metric" | sed 's|-local||g' | sed 's|-android||g' | sed 's|-host||g')
	
	# Remove result files for this metric
	if [ -d "$DAMOOS/results/$metric_name" ]; then
		sudo rm -f "$DAMOOS/results/$metric_name"/*
	fi
done

echo "Cleanup completed."
