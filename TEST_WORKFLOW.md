# DAMOOS Android 移植测试工作流

## 测试前准备

1. **确保手机连接并授权**
```bash
adb devices
# 应该显示您的设备并且状态为 "device"
```

2. **确认 root 权限**
```bash
adb shell su -c "id"
# 应该显示 uid=0(root)
```

3. **检查 DAMON 支持**
```bash
adb shell su -c "ls -la /sys/kernel/debug/damon/"
# 应该显示 monitor_on, target_ids, attrs, schemes 等文件
```

4. **检查 PSI 支持**
```bash
adb shell su -c "cat /proc/pressure/memory"
# 应该显示 some 和 full 的压力数据
```

---

## 测试级别 1: 单独组件测试（快速验证）

### 1.1 测试 PSI 收集器（新功能）

**测试脚本**: `test_psi_collector.sh`  
**时长**: ~15 秒  
**应用**: com.android.settings（系统设置）

```bash
cd /home/qjm/Desktop/damoos
./test_psi_collector.sh
```

**验证点**:
- ✓ ADB 连接正常
- ✓ Root 权限可用
- ✓ PSI 功能支持
- ✓ 脚本成功推送到设备
- ✓ 应用成功启动并获取 PID
- ✓ PSI 数据成功收集（9 列格式）
- ✓ 数据成功拉取到 PC

**预期输出**:
```
========================================
PSI Collector Test PASSED
========================================
PSI data saved to: /home/qjm/Desktop/damoos/results/psi/<PID>.stat
```

---

## 测试级别 2: 集成测试（完整工作流）

### 2.1 基础集成测试

**测试脚本**: `test_android_integration.sh`  
**时长**: ~15 秒  
**应用**: com.android.settings（轻量级）

```bash
cd /home/qjm/Desktop/damoos
./test_android_integration.sh com.android.settings 10
```

**验证点**:
- ✓ 所有 Phase 1-3 的功能集成
- ✓ 4 个 metric collectors 同时运行（rss, runtime, swapin, swapout）
- ✓ 数据文件生成并拉取成功
- ✓ 清理功能正常

**预期输出**:
```
========================================
Integration Test PASSED
========================================
```

### 2.2 实际应用测试（您手机上的应用）

**推荐测试顺序**（从轻到重）:

#### 测试 1: 浏览器应用（中等负载）
```bash
./test_android_integration.sh com.quark.browser 20
```

#### 测试 2: 社交应用（常驻内存）
```bash
./test_android_integration.sh com.tencent.mm 30
```

#### 测试 3: 视频应用（突发内存访问）
```bash
./test_android_integration.sh com.ss.android.ugc.aweme 30
```

#### 测试 4: 电商应用（图片密集）
```bash
./test_android_integration.sh com.taobao.taobao 30
```

---

## 测试级别 3: 完整优化工作流（即将进行 Phase 4）

### 3.1 使用 simple_adapter 测试优化

**目标**: 验证完整的"收集数据 → 优化方案 → 应用方案"流程

```bash
cd /home/qjm/Desktop/damoos

# 选择一个测试应用
TEST_APP="douyin"  # 或 wechat, quark, taobao 等

# 运行 simple_adapter（会测试多个 DAMON 方案）
cd scheme_adapters/simple_adapter
bash simple_adapter.sh "$TEST_APP" rss
```

**这个测试会**:
1. 读取 workload_directory.txt 中的抖音配置
2. 检测到 `@@@ANDROID@@@` 标记
3. 使用 ADB 启动抖音
4. 测试多个 DAMON 方案（不同的 min_size, min_age 参数）
5. 每个方案收集 RSS metric
6. 找出最优方案

**预期输出**:
```
Testing scheme 1/N: min_size=4K, min_age=5s
  → RSS: XXX KB
Testing scheme 2/N: min_size=16K, min_age=10s
  → RSS: YYY KB
...
Best scheme: min_size=XX, min_age=YY (RSS reduced by Z%)
```

---

## 测试级别 4: 带 PSI 的优化测试

### 4.1 同时收集多个 metrics

修改测试以同时收集 RSS 和 PSI:

```bash
# 手动测试多 metric 收集
source adb_interface/adb_utils.sh
source adb_interface/adb_workload.sh
source adb_interface/adb_metric_collector.sh

# 启动应用
start_android_app "com.ss.android.ugc.aweme"
PID=$(get_app_pid "com.ss.android.ugc.aweme")

# 同时启动多个收集器
start_remote_collector "rss" "$PID"
start_remote_collector "psi" "$PID"
start_remote_collector "swapin" "$PID"
start_remote_collector "swapout" "$PID"

# 运行 30 秒
sleep 30

# 拉取所有数据
pull_metric_data "rss" "$PID"
pull_metric_data "psi" "$PID"
pull_metric_data "swapin" "$PID"
pull_metric_data "swapout" "$PID"

# 查看结果
cat results/rss/${PID}.stat | tail -10
cat results/psi/${PID}.stat | tail -10
```

---

## 推荐测试顺序

### 快速验证（5 分钟）
```bash
# 1. 测试 PSI 新功能
./test_psi_collector.sh

# 2. 基础集成测试
./test_android_integration.sh com.android.settings 10
```

### 完整验证（15 分钟）
```bash
# 3. 测试所有您的应用
for app in quark wechat douyin bilibili taobao; do
    echo "Testing $app..."
    ./test_android_integration.sh "com.$(get_package_name $app)" 20
done
```

### 优化工作流验证（Phase 4 准备，30 分钟）
```bash
# 4. 完整优化测试
cd scheme_adapters/simple_adapter
bash simple_adapter.sh "douyin" "rss"
```

---

## 常见问题排查

### 问题 1: ADB 连接失败
```bash
adb kill-server
adb start-server
adb devices
```

### 问题 2: Root 权限问题
```bash
adb shell su -c "whoami"
# 如果失败，在手机 Magisk 中重新授权 ADB shell
```

### 问题 3: PSI 不支持
```bash
# 检查内核版本
adb shell uname -r
# 应该 >= 4.20

# 检查 PSI 配置
adb shell su -c "zcat /proc/config.gz | grep PSI"
# 应该显示 CONFIG_PSI=y
```

### 问题 4: DAMON 文件访问失败
```bash
# 确保 debugfs 已挂载
adb shell su -c "mount | grep debugfs"

# 手动挂载（如果需要）
adb shell su -c "mount -t debugfs none /sys/kernel/debug"
```

### 问题 5: 应用启动失败
```bash
# 验证包名是否正确
adb shell pm list packages | grep <关键词>

# 手动启动测试
adb shell monkey -p com.ss.android.ugc.aweme -c android.intent.category.LAUNCHER 1
```

---

## 测试数据验证

### 检查收集的数据质量

```bash
# RSS 数据（应该有多行，单位 KB）
cat results/rss/<PID>.stat
# 预期: 每行一个数字，表示内存使用量

# PSI 数据（应该有 header + 多行数据）
cat results/psi/<PID>.stat
# 预期: 第一行为 header，后续每行 9 个字段

# Swap 数据（累积计数器）
cat results/swapin/<PID>.stat
# 预期: 递增的数字序列

# Runtime 数据（单个值）
cat results/runtime/<PID>.stat
# 预期: 一个整数，表示运行时长（秒）
```

---

## 下一步

测试通过后，可以继续:

1. **Phase 4**: 适配 Scheme Adapters（simple_adapter, polyfit_adapter 等）
2. **Phase 5**: 实现 DAMON 方案应用到 Android
3. **完整优化**: 对您的应用（抖音、淘宝等）进行实际内存优化

---

## 测试检查清单

- [ ] PSI collector 测试通过
- [ ] 基础集成测试通过（Settings）
- [ ] 至少 3 个实际应用测试通过
- [ ] 数据文件格式正确
- [ ] 数据质量合理（无全 0 或异常值）
- [ ] 清理功能正常工作
- [ ] 可以重复运行测试
