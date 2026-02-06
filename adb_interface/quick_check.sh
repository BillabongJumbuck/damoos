#!/bin/bash

# Quick environment check before running full tests

echo "========================================="
echo "DAMOOS ADB Interface - Quick Check"
echo "========================================="
echo ""

# Check ADB
echo -n "1. Checking ADB installation... "
if command -v adb >/dev/null 2>&1; then
    echo "✓ OK"
    adb version | head -1
else
    echo "✗ FAILED - ADB not found"
    echo "   Please install: sudo apt install adb"
    exit 1
fi

echo ""

# Check ADB connection
echo -n "2. Checking ADB device connection... "
devices=$(adb devices 2>/dev/null | grep -w "device" | grep -v "List of devices")
if [ -n "$devices" ]; then
    echo "✓ OK"
    echo "$devices"
else
    echo "✗ FAILED - No device connected"
    echo "   Please connect your Android device with USB debugging enabled"
    exit 1
fi

echo ""

# Check root
echo -n "3. Checking root access... "
root_check=$(adb shell "su -c 'id'" 2>/dev/null | grep "uid=0")
if [ -n "$root_check" ]; then
    echo "✓ OK"
else
    echo "✗ FAILED - No root access"
    echo "   Please ensure your device is rooted and grant ADB root permission"
    exit 1
fi

echo ""

# Check DAMON
echo -n "4. Checking DAMON kernel support... "
damon_config=$(adb shell "su -c 'zcat /proc/config.gz 2>/dev/null | grep CONFIG_DAMON=y'" | tr -d '\r\n')
if [ -n "$damon_config" ]; then
    echo "✓ OK"
    adb shell "su -c 'zcat /proc/config.gz 2>/dev/null | grep DAMON'" | tr -d '\r'
else
    echo "✗ FAILED - DAMON not enabled in kernel"
    echo "   Your device needs a kernel with DAMON support"
    exit 1
fi

echo ""

# Check debugfs
echo -n "5. Checking DAMON debugfs... "
debugfs_check=$(adb shell "su -c 'ls /sys/kernel/debug/damon/monitor_on 2>/dev/null'" | tr -d '\r\n')
if [ -n "$debugfs_check" ]; then
    echo "✓ OK"
    echo "   Available files:"
    adb shell "su -c 'ls /sys/kernel/debug/damon/'" | tr -d '\r' | sed 's/^/   - /'
else
    echo "✗ FAILED - DAMON debugfs not accessible"
    echo "   Please check if debugfs is mounted"
    exit 1
fi

echo ""
echo "========================================="
echo "✓ All checks passed!"
echo "========================================="
echo ""
echo "Your device is ready for DAMOOS testing."
echo ""
echo "Next steps:"
echo "  1. Read the test guide: less TEST_GUIDE.md"
echo "  2. Run full test suite: ./test_adb_interface.sh"
echo ""
