#!/bin/bash

# Helper script for simple_rl_adapter_android.py
# Sources all necessary adb_interface scripts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADB_INTERFACE_DIR="$SCRIPT_DIR/../../../adb_interface"

# Source all necessary scripts
source "$ADB_INTERFACE_DIR/adb_utils.sh"
source "$ADB_INTERFACE_DIR/adb_workload.sh"
source "$ADB_INTERFACE_DIR/adb_metric_collector.sh"
source "$ADB_INTERFACE_DIR/adb_damon_control.sh"

# Execute the command passed as arguments
"$@"
