#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: GPL-2.0

# Wait for metric collectors to write into the .stat file
# Args: $1 - PID, $2... - metric names

pid="$1"
shift

# Check if we need to wait for Android metrics
metric_directory="$DAMOOS/frontend/metric_directory.txt"
has_android_metrics=false

for metric in "$@"
do
	metric_entry=$(grep "^$metric-" "$metric_directory" | grep -oh "[^-]*$")
	if [[ "$metric_entry" == "android" ]]; then
		has_android_metrics=true
		break
	fi
done

# If Android metrics present, source ADB modules
if [ "$has_android_metrics" = true ]; then
	source "$DAMOOS/adb_interface/adb_utils.sh"
	source "$DAMOOS/adb_interface/adb_metric_collector.sh"
fi

# Wait for each metric
for metric in "$@"
do
	metric_entry=$(grep "^$metric-" "$metric_directory" | grep -oh "[^-]*$")
	
	if [[ "$metric_entry" == "android" ]]; then
		# Wait for remote metric file on Android device
		echo "Waiting for Android metric: $metric (PID: $pid)"
		remote_stat_file="/data/local/tmp/damoos/results/${metric}/${pid}.stat"
		
		# Wait for file to appear on device (timeout 300 seconds)
		timeout=300
		elapsed=0
		while [ $elapsed -lt $timeout ]; do
			if adb_file_exists "$remote_stat_file"; then
				echo "Android metric file ready: $metric"
				break
			fi
			sleep 1
			elapsed=$((elapsed + 1))
			
			# Show progress every 30 seconds
			if [ $((elapsed % 30)) -eq 0 ]; then
				echo "  Still waiting for $metric... (${elapsed}s/${timeout}s)"
			fi
		done
		
		if [ $elapsed -ge $timeout ]; then
			echo "Warning: Timeout waiting for Android metric: $metric"
		fi
		
	elif [[ "$metric_entry" == "local" ]]; then
		# Wait for local metric file
		while [ ! -f "$DAMOOS/metrics_collector/collectors/$metric/$pid.stat" ]
		do
			sleep 0.5
		done
		
	else
		echo "Warning: Unknown metric type for $metric"
	fi
done

echo "All metric collectors finished."
