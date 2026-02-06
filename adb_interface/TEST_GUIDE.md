# Phase 1 测试指南

## 测试前准备

### 1. 确保 ADB 已安装
```bash
# 检查 ADB 是否安装
adb version

# 如果未安装，Linux 上可以这样安装：
sudo apt install adb

# 或者下载 Android SDK Platform Tools
```

### 2. 连接 Android 设备

#### USB 连接（推荐）：
```bash
# 在设备上启用开发者选项和 USB 调试
# 连接 USB 线后，检查连接：
adb devices
```

#### WiFi 连接（可选）：
```bash
# 首先通过 USB 连接设备
adb tcpip 5555

# 获取设备 IP 地址（在设备的设置中查看）
# 假设设备 IP 为 192.168.1.100
adb connect 192.168.1.100:5555

# 断开 USB，通过 WiFi 检查连接
adb devices
```

### 3. 确保 Root 权限
```bash
# 测试 root 访问
adb shell "su -c 'id'"

# 应该输出类似：uid=0(root) gid=0(root) ...
```

### 4. 验证 DAMON 支持
```bash
# 检查 DAMON 配置
adb shell "su -c 'zcat /proc/config.gz | grep DAMON'"

# 应该看到：
# CONFIG_DAMON=y
# CONFIG_DAMON_VADDR=y
# CONFIG_DAMON_DBGFS=y
# 等等

# 检查 debugfs
adb shell "su -c 'ls /sys/kernel/debug/damon/'"

# 应该列出：attrs, monitor_on, schemes, target_ids 等
```

## 运行测试

### 完整测试（推荐）
```bash
cd /home/qjm/Desktop/damoos/adb_interface
./test_adb_interface.sh
```

测试脚本会自动运行所有测试，包括：
1. ✅ ADB 连接测试
2. ✅ Root 权限测试
3. ✅ 设备信息获取
4. ✅ DAMON 支持验证
5. ✅ 目录操作测试
6. ✅ 文件操作测试（push/pull）
7. ✅ DAMON 控制功能测试
8. ✅ 工作负载管理测试（可选）
9. ✅ DAMON 高级控制测试（可选）

### 交互式测试

测试脚本会在某些步骤询问你：

**测试 8: 工作负载管理**
- 会询问是否要测试启动应用
- 可以输入任何已安装的应用包名
- 推荐测试：`com.android.settings`（系统设置）

**测试 9: DAMON 高级控制**
- 会询问是否要用真实进程测试 DAMON
- 这会实际启动 DAMON 监控一个应用
- 推荐测试：`com.android.settings` 或其他轻量应用

## 测试输出解释

### 成功输出示例
```
✓ ADB device connected
✓ Root access available
✓ DAMON support verified
✓ DAMOOS directories created
✓ File pushed successfully
```

### 测试结果
```
========================================
Test Summary
========================================
Passed:  25
Failed:  0
Skipped: 2

✓ All tests passed! ADB interface is working correctly.
```

## 常见问题排查

### 问题 1: "ADB device not connected"
**解决方案：**
```bash
# 重启 ADB 服务
adb kill-server
adb start-server

# 检查设备
adb devices

# 如果看不到设备，检查：
# - USB 线是否连接良好
# - 设备上是否启用了 USB 调试
# - 是否授权了电脑（设备上应该弹出授权对话框）
```

### 问题 2: "Root access not available"
**解决方案：**
```bash
# 确保设备已 root
# 在设备上安装 Magisk 或其他 root 方案

# 测试 shell root
adb shell
su
# 应该切换到 root (#) 提示符

# 如果提示权限请求，在设备上授权
```

### 问题 3: "DAMON debugfs not found"
**解决方案：**
```bash
# 检查 debugfs 是否挂载
adb shell "su -c 'mount | grep debugfs'"

# 如果未挂载，尝试挂载：
adb shell "su -c 'mount -t debugfs none /sys/kernel/debug'"

# 如果 DAMON 不可用，说明内核不支持
# 需要使用支持 DAMON 的内核（Linux 5.10+）
```

### 问题 4: "Permission denied" 错误
**解决方案：**
```bash
# 检查 SELinux 状态
adb shell "su -c 'getenforce'"

# 如果是 Enforcing，临时设置为 Permissive
adb shell "su -c 'setenforce 0'"

# 注意：这会降低安全性，仅用于测试
```

### 问题 5: "Failed to push file"
**解决方案：**
```bash
# 检查 /data/local/tmp 是否可写
adb shell "su -c 'ls -ld /data/local/tmp'"

# 确保有足够空间
adb shell "su -c 'df -h /data'"

# 手动创建目录
adb shell "su -c 'mkdir -p /data/local/tmp/damoos'"
```

## 手动测试单个组件

### 测试 ADB Utils
```bash
source adb_interface/adb_utils.sh

# 检查连接
adb_check_connection
adb_check_root

# 获取设备信息
adb_get_device_info

# 初始化目录
adb_init_damoos_dirs

# 验证 DAMON
adb_verify_damon_support
```

### 测试 DAMON Control
```bash
source adb_interface/adb_utils.sh
source adb_interface/adb_damon_control.sh

# 初始化 DAMON
damon_init

# 查看配置
damon_get_config

# 查看状态
damon_get_status

# 单位转换测试
time_to_microseconds "5s"    # 应输出 5000000
size_to_bytes "4K"           # 应输出 4096
```

### 测试 Workload Management
```bash
source adb_interface/adb_utils.sh
source adb_interface/adb_workload.sh

# 检查包是否安装
is_package_installed "com.android.settings"

# 获取包信息
get_package_info "com.android.settings"

# 启动应用
start_android_app "com.android.settings" ""

# 获取 PID
get_app_pid "com.android.settings"

# 停止应用
stop_android_app "com.android.settings"
```

### 测试完整 DAMON 流程
```bash
source adb_interface/adb_utils.sh
source adb_interface/adb_damon_control.sh
source adb_interface/adb_workload.sh

# 1. 启动应用
start_android_app "com.android.settings" ""
sleep 3

# 2. 获取 PID
PID=$(get_app_pid "com.android.settings")
echo "PID: $PID"

# 3. 配置并启动 DAMON
damon_apply_and_start "$PID" "4K" "max" "5s" "max" "pageout"

# 4. 监控 10 秒
echo "Monitoring for 10 seconds..."
sleep 10

# 5. 停止 DAMON
damon_stop

# 6. 停止应用
stop_android_app "com.android.settings"

echo "Test complete!"
```

## 下一步

如果所有测试通过：
- ✅ Phase 1 完成！
- ➡️ 可以继续 Phase 2：修改 Frontend 层支持 Android

如果有测试失败：
- 🔍 查看具体错误信息
- 📖 参考上面的问题排查部分
- ❓ 检查设备环境是否满足要求

## 日志和调试

### 启用详细日志
```bash
# 设置 ADB 日志级别
export ADB_TRACE=all

# 运行测试
./test_adb_interface.sh
```

### 查看 DAMON 日志
```bash
# 查看内核日志中的 DAMON 信息
adb shell "su -c 'dmesg | grep -i damon'"

# 查看 DAMON 状态
adb shell "su -c 'cat /sys/kernel/debug/damon/monitor_on'"
```

## 测试清理

测试完成后，清理临时数据：
```bash
# 清理 Android 设备上的数据
adb shell "su -c 'rm -rf /data/local/tmp/damoos'"

# 停止任何运行的应用
adb shell "am force-stop com.android.settings"

# 停止 DAMON（如果在运行）
adb shell "su -c 'echo off > /sys/kernel/debug/damon/monitor_on'"
```

---

**准备好了吗？运行测试：**
```bash
cd /home/qjm/Desktop/damoos/adb_interface
./test_adb_interface.sh
```
