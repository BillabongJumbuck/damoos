#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: GPL-2.0

# Run the workloads using command in workload directory.
# Argument1 - Workload Name, Argument2 to ArgumentN - Metric Name
# Stores the pid of the workload in results/pid file.
# Workload should be registered in the workload_directory.

if [[ $# -eq 0 ]]
then
	echo "Usage: $0 <workload name> [metric1] [metric2] ... [metricN]"
fi

workload_directory="$DAMOOS/frontend/workload_directory.txt"

# Parse workload entry from directory
workload_entry=$(grep "^$1@@@" "$workload_directory")
if [ -z "$workload_entry" ]; then
	echo "Error: Workload '$1' not found in workload directory"
	exit 1
fi

# Check if this is an Android workload
if echo "$workload_entry" | grep -q "@@@ANDROID@@@"; then
	# Android workload handling
	echo "Detected Android workload: $1"
	
	# Source ADB interface modules
	source "$DAMOOS/adb_interface/adb_utils.sh"
	source "$DAMOOS/adb_interface/adb_workload.sh"
	source "$DAMOOS/adb_interface/adb_metric_collector.sh"
	
	# Check ADB connection
	if ! adb_check_connection; then
		echo "Error: ADB connection failed"
		exit 1
	fi
	
	if ! adb_check_root; then
		echo "Error: Root access required"
		exit 1
	fi
	
	# Parse Android workload entry: ShortName@@@PackageName@@@ANDROID@@@Command
	package=$(echo "$workload_entry" | cut -d'@' -f4)
	command=$(echo "$workload_entry" | cut -d'@' -f6-)
	
	echo "Package: $package"
	echo "Command: $command"
	
	# Stop app first to ensure clean start
	stop_android_app "$package" >/dev/null 2>&1
	sleep 1
	
	# Execute the ADB command (via shell)
	echo "Starting Android app..."
	adb shell "$command" >/dev/null 2>&1 &
	
	# Wait for app to start and get PID
	sleep 3
	
	pid=$(get_app_pid "$package")
	retry_count=0
	while [[ -z $pid ]] && [[ $retry_count -lt 10 ]]; do
		sleep 1
		pid=$(get_app_pid "$package")
		retry_count=$((retry_count + 1))
	done
	
	if [[ -z $pid ]]; then
		echo "Error: Failed to get PID for package $package"
		echo "App may not have started successfully"
		exit 1
	fi
	
	echo "Android app started successfully (PID: $pid)"
	
	# Start metric collectors on Android device
	for (( metric=2; metric<=$#; metric++))
	do
		eval "name=\${$metric}"
		metric_directory="$DAMOOS/frontend/metric_directory.txt"
		metric_entry=$(grep "^$name-" "$metric_directory" | grep -oh "[^-]*$")
	
		if [[ "$metric_entry" == "android" ]]
		then
			echo "Starting remote collector: $name"
			start_remote_collector "$name" "$pid"
		elif [[ "$metric_entry" == "local" ]]
		then
			# Local collectors still run on PC
			DAMOOS="$DAMOOS" bash "$DAMOOS"/metrics_collector/collect_metric.sh "$name" "$pid" &
		elif [[ "$metric_entry" == "host" ]]
		then
			echo "Host metrics not yet implemented for Android workloads"
		else
			echo "Invalid metric name or Invalid entry in metric directory"
			exit 1
		fi	
	done
	
	# Store PID
	echo "$pid" > "$DAMOOS"/results/pid

else
	# Local workload handling (original behavior)
	command=$(echo "$workload_entry" | grep -oh "[^@@@]*$")
	
	if ! eval "$command"
	then
		echo "Unable to run the workload. Please check the corresponding command."
		exit 1
	fi
	
	workload=$(echo "$workload_entry" | grep -oh -e '@@@.*@@@' | grep -oh -e "[^@@@]*")

	pid=$(pidof "$workload")
	while [[ -z $pid ]]
	do
		pid=$(pidof "$workload")
		sleep 1
	done

	# Check if the workload is already running, in that case pidof may return more than one pids
	if [[ $pid =~ ^[0-9]+$ ]]
	then
		for (( metric=2; metric<=$#; metric++))
		do
			eval "name=\${$metric}"
			metric_directory="$DAMOOS/frontend/metric_directory.txt"
			metric_entry=$(grep "^$name-" "$metric_directory" | grep -oh "[^-]*$")
		
			if [[ "$metric_entry" == "local" ]]
			then
				DAMOOS="$DAMOOS" bash "$DAMOOS"/metrics_collector/collect_metric.sh "$name" "$pid" &
			elif [[ "$metric_entry" == "host" ]]
			then
				echo "To be implemented"
				exit 1
			elif [[ "$metric_entry" == "android" ]]
			then
				echo "Error: Cannot use android metrics with local workload"
				exit 1
			else
				echo "Invalid metric name or Invalid entry in metric directory"
				exit 1
			fi	
		done
		echo "$pid" > "$DAMOOS"/results/pid

	else
		echo "Multiple $workload workloads are running, please kill or wait for them to finish"
		exit 1
	fi
fi
