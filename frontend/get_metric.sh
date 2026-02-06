#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: GPL-2.0

# Get the results from collected metrics either from local or remote metric collectors
# Argument1 - pid, Argument2 - Metric Name, Argument3 - Statistic Name (full_avg, partial_avg etc.)

if [[ $# -ne 3 ]] && [[ $# -ne 4 ]]
then
	echo "Usage: $0 <pid> <metric> <stat_name>"
	echo "If stat name is partial_avg, also provide the number of last entries to be considered."
	echo "Metrics:"
	cat "$DAMOOS/frontend/metric_directory.txt"
	exit 1
fi

metric_directory="$DAMOOS/frontend/metric_directory.txt"
metric_entry=$(grep "^$2-" "$metric_directory" | grep -oh "[^-]*$")

if [[ "$metric_entry" == "android" ]]
then
	# Android metric handling - pull data from device
	echo "Pulling metric data from Android device..."
	
	# Source ADB modules
	source "$DAMOOS/adb_interface/adb_utils.sh"
	source "$DAMOOS/adb_interface/adb_metric_collector.sh"
	
	# Pull the metric data from device
	if ! pull_metric_data "$2" "$1"; then
		echo "Error: Failed to pull metric data from Android device"
		exit 1
	fi
	
	# Now process the pulled data locally using the same logic as local metrics
	# The .stat file is now in $DAMOOS/results/$2/$1.stat
	
	if [[ "$3" == "full_avg" ]]
	then
		sudo DAMOOS="$DAMOOS" bash "$DAMOOS"/metrics_collector/get_avg_stat.sh "$1" "$2"
		if [[ $? -ne 0 ]]
		then
			exit 1
		else
			# The avg file is created in collectors directory, move it to results
			if [ -f "$DAMOOS/metrics_collector/collectors/$2/$1.avg" ]; then
				mv "$DAMOOS/metrics_collector/collectors/$2/$1.avg"  "$DAMOOS/results/$2/$1.$3"
			fi
		fi
	elif [[ "$3" == "partial_avg" ]]
	then
		sudo DAMOOS="$DAMOOS" bash "$DAMOOS"/metrics_collector/get_partial_avg_stat.sh "$1" "$2" "$4"
		if [[ $? -ne 0 ]]
		then
			exit 1
		else
			if [ -f "$DAMOOS/metrics_collector/collectors/$2/$1.avg" ]; then
				mv "$DAMOOS/metrics_collector/collectors/$2/$1.avg"  "$DAMOOS/results/$2/$1.$3"
			fi
		fi
	elif [[ "$3" == "diff" ]]
	then
		sudo DAMOOS="$DAMOOS" bash "$DAMOOS"/metrics_collector/get_diff_stat.sh "$1" "$2"
		if [[ $? -ne 0 ]]
		then
			exit 1
		else
			if [ -f "$DAMOOS/metrics_collector/collectors/$2/$1.diff" ]; then
				mv "$DAMOOS/metrics_collector/collectors/$2/$1.diff"  "$DAMOOS/results/$2/$1.$3"
			fi
		fi
	elif [[ "$3" == "stat" ]]
	then
		# For stat, just copy the already-pulled file
		if [ -f "$DAMOOS/results/$2/$1.stat" ]; then
			cp "$DAMOOS/results/$2/$1.stat" "$DAMOOS/results/$2/$1.$3"
		else
			echo "Error: Stat file not found"
			exit 1
		fi
	fi

elif [[ "$metric_entry" == "local" ]]
then
	if [[ "$3" == "full_avg" ]]
	then
		sudo DAMOOS="$DAMOOS" bash "$DAMOOS"/metrics_collector/get_avg_stat.sh "$1" "$2"
		if [[ $? -ne 0 ]]
		then
			exit 1
		else
			mv "$DAMOOS/metrics_collector/collectors/$2/$1.avg"  "$DAMOOS/results/$2/$1.$3"
		fi
	elif [[ "$3" == "partial_avg" ]]
	then
		sudo DAMOOS="$DAMOOS" bash "$DAMOOS"/metrics_collector/get_partial_avg_stat.sh "$1" "$2" "$4"
		if [[ $? -ne 0 ]]
		then
			exit 1
		else
			mv "$DAMOOS/metrics_collector/collectors/$2/$1.avg"  "$DAMOOS/results/$2/$1.$3"
		fi
	elif [[ "$3" == "diff" ]]
	then
		sudo DAMOOS="$DAMOOS" bash "$DAMOOS"/metrics_collector/get_diff_stat.sh "$1" "$2"
		if [[ $? -ne 0 ]]
		then
			exit 1
		else
			mv "$DAMOOS/metrics_collector/collectors/$2/$1.diff"  "$DAMOOS/results/$2/$1.$3"
		fi
	elif [[ "$3" == "stat" ]]
	then
		sudo DAMOOS="$DAMOOS" bash "$DAMOOS"/metrics_collector/get_stat.sh "$1" "$2"
		if [[ $? -ne 0 ]]
		then
			exit 1
		else
			mv "$DAMOOS/metrics_collector/collectors/$2/$1.stat"  "$DAMOOS/results/$2/$1.$3"
		fi
	fi

elif [[ "$metric_entry" == "host" ]]
then
	echo "To be implemented"
	exit 1
else
	echo "Invalid metric name or Invalid entry in metrics directory"
	exit 1
fi
