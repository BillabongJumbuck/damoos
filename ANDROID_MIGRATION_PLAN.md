# DAMOOS Android 移植计划

## 项目概述

将 DAMOOS 从单机 Linux 架构迁移到 PC-Android 分布式架构，实现：
- **Android 端**：运行工作负载（如原神）、收集性能指标、应用 DAMON 方案
- **PC 端**：运行 Scheme Adapters 优化算法、通过 ADB 远程控制
- **通信**：通过 ADB 命令实现双向控制和数据传输

## 目标设备环境

### Android 设备信息
- **内核版本**：Linux 5.10
- **DAMON 版本**：较老版本（debugfs 接口）
- **DAMON 配置**：
  ```
  CONFIG_DAMON=y
  CONFIG_DAMON_VADDR=y          # 支持进程虚拟地址监控 ✅
  CONFIG_DAMON_PADDR=y          # 支持物理地址监控 ✅
  CONFIG_DAMON_DBGFS=y          # debugfs 接口 ✅
  CONFIG_DAMON_RECLAIM=y        # 内存回收支持 ✅
  ```

### DAMON 接口特点
- **控制接口**：`/sys/kernel/debug/damon/` (debugfs)
- **不支持动态修改**：必须停止 DAMON → 修改配置 → 重新启动
- **工作目录**：`/data/local/tmp`（Android 可写区域）

### 接口限制的影响
✅ **无本质影响**：DAMOOS 采用迭代测试方式，每次测试都会：
1. 停止 DAMON
2. 修改 scheme 参数
3. 启动新的工作负载
4. 启动 DAMON 监控
5. 收集完成后停止

这与老版本 DAMON 的限制完全兼容！

## 系统架构

```
┌─────────────────────────────────────────────────┐
│               PC 端 (Control Host)              │
├─────────────────────────────────────────────────┤
│  • Scheme Adapters (算法优化层)                  │
│    - simple_adapter                             │
│    - simple_rl_adapter                          │
│    - polyfit_adapter                            │
│    - pso_adapter                                │
│    - multiD_polyfit_adapter                     │
│                                                 │
│  • Frontend (控制层)                             │
│    - run_workloads.sh (启动 Android 工作负载)   │
│    - get_metric.sh (拉取指标数据)               │
│    - wait_for_* (同步等待脚本)                  │
│    - cleanup.sh (清理资源)                      │
│                                                 │
│  • ADB Interface (新增通信层)                    │
│    - adb_damon_control.sh (DAMON debugfs 控制)  │
│    - adb_metric_collector.sh (远程指标收集)     │
│    - adb_workload.sh (应用管理)                 │
│    - adb_utils.sh (ADB 工具函数)                │
└──────────────────┬──────────────────────────────┘
                   │
                   │ ADB Protocol
                   │ • adb shell (执行命令)
                   │ • adb push (推送脚本)
                   │ • adb pull (拉取数据)
                   │
                   ▼
┌─────────────────────────────────────────────────┐
│          Android 设备 (Target Device)           │
├─────────────────────────────────────────────────┤
│  • 工作负载 (Workloads)                          │
│    - 原神等应用                                  │
│    - 通过包名/Activity 启动                      │
│                                                 │
│  • Metrics Collectors (指标收集器)               │
│    - rss_collector.sh (常驻内存)                │
│    - runtime_collector.sh (运行时间)            │
│    - swapin_collector.sh (换入次数)             │
│    - swapout_collector.sh (换出次数)            │
│                                                 │
│  • DAMON Control (debugfs 接口)                 │
│    - /sys/kernel/debug/damon/monitor_on         │
│    - /sys/kernel/debug/damon/target_ids         │
│    - /sys/kernel/debug/damon/schemes            │
│    - /sys/kernel/debug/damon/attrs              │
│                                                 │
│  • 工作目录                                      │
│    - /data/local/tmp/damoos/ (脚本和数据)       │
│    - /data/local/tmp/damoos/results/ (结果)     │
└─────────────────────────────────────────────────┘
```

## 实施计划

### Phase 1: ADB 接口层（新建组件）

创建 `adb_interface/` 目录，实现 Android 设备的远程控制。

#### 1.1 ADB 工具函数 (`adb_interface/adb_utils.sh`)
```bash
功能：
- adb_check_connection()      # 检查 ADB 连接状态
- adb_check_root()             # 检查 root 权限
- adb_push_scripts()           # 批量推送脚本到设备
- adb_ensure_directory()       # 确保远程目录存在
- adb_get_pid()                # 获取应用 PID
- adb_kill_process()           # 结束进程
- adb_file_exists()            # 检查远程文件是否存在
```

#### 1.2 DAMON 控制接口 (`adb_interface/adb_damon_control.sh`)
```bash
功能：适配 debugfs 接口
- damon_init()                 # 初始化 DAMON
- damon_set_target(pid)        # 设置监控目标进程
- damon_set_attrs(...)         # 设置采样参数
- damon_set_scheme(...)        # 配置 DAMOS scheme
- damon_start()                # 启动监控（echo on）
- damon_stop()                 # 停止监控（echo off）
- damon_get_status()           # 查询状态

参数示例：
scheme 格式 (debugfs)：
  min_sz max_sz min_acc max_acc min_age max_age action
  例：4096 max 0 100 5000000 max pageout
```

#### 1.3 工作负载管理 (`adb_interface/adb_workload.sh`)
```bash
功能：
- start_android_app(pkg, activity)   # 启动应用
- stop_android_app(pkg)              # 停止应用
- wait_for_app_ready(pkg)            # 等待应用完全启动
- get_app_pid(pkg)                   # 获取应用主进程 PID
- is_app_running(pkg)                # 检查应用是否运行

支持的启动方式：
- am start -n com.miHoYo.Yuanshen/.MainActivity
- monkey -p com.miHoYo.Yuanshen 1
```

#### 1.4 远程指标收集 (`adb_interface/adb_metric_collector.sh`)
```bash
功能：
- start_remote_collector(metric, pid)    # 在 Android 启动收集器
- stop_remote_collector(metric, pid)     # 停止收集器
- pull_metric_data(metric, pid)          # 拉取指标数据到 PC
- cleanup_remote_data()                  # 清理远程临时文件
```

---

### Phase 2: Frontend 层改造（修改现有组件）

#### 2.1 修改 `frontend/metric_directory.txt`
```diff
  metric_name-localORhost
  rss-local
+ rss-android
  swapout-local
+ swapout-android
  swapin-local
+ swapin-android
  runtime-local
+ runtime-android
```

#### 2.2 修改 `frontend/workload_directory.txt`
```diff
+ # Android Workloads Format:
+ # ShortName@@@PackageName@@@StartCommand
+ 
+ # 示例：原神
+ genshin@@@com.miHoYo.Yuanshen@@@am start -n com.miHoYo.Yuanshen/.MainActivity
+ 
+ # 示例：其他应用
+ chrome@@@com.android.chrome@@@am start -n com.android.chrome/com.google.android.apps.chrome.Main
```

#### 2.3 修改 `frontend/run_workloads.sh`
```bash
核心改动：
1. 检测工作负载类型（本地 vs Android）
2. 如果是 Android 应用：
   - 调用 adb_workload.sh 启动应用
   - 通过 ADB 获取 PID
   - 调用 adb_metric_collector.sh 启动远程收集器
3. 如果是本地应用：
   - 保持原有逻辑

伪代码：
if [[ $command == am\ start* ]] || [[ $command == monkey* ]]; then
    # Android workload
    source "$DAMOOS/adb_interface/adb_workload.sh"
    start_android_app ...
    pid=$(get_app_pid ...)
    # 启动远程 metric collectors
else
    # Local workload (原有逻辑)
    eval "$command"
    pid=$(pidof "$workload")
fi
```

#### 2.4 修改 `frontend/get_metric.sh`
```bash
核心改动：
1. 检查 metric_directory.txt 中的类型
2. 如果是 android 类型：
   - 调用 adb_metric_collector.sh pull_metric_data
   - 将数据放到本地 results/ 目录
3. 如果是 local 类型：
   - 保持原有逻辑

伪代码：
if [[ "$metric_entry" == "android" ]]; then
    source "$DAMOOS/adb_interface/adb_metric_collector.sh"
    pull_metric_data "$metric_name" "$pid"
elif [[ "$metric_entry" == "local" ]]; then
    # 原有逻辑
fi
```

#### 2.5 修改 `frontend/wait_for_metric_collector.sh`
```bash
核心改动：
- 支持检查远程文件（通过 adb shell test -f）
- 轮询等待 Android 端的 .stat 文件生成
```

#### 2.6 修改 `frontend/cleanup.sh`
```bash
核心改动：
- 添加清理 Android 端数据的逻辑
- 调用 adb_metric_collector.sh cleanup_remote_data
```

---

### Phase 3: Android 端脚本（适配 debugfs）

在 `metrics_collector/collectors/` 下创建 Android 版本，推送到设备。

#### 3.1 RSS Collector (`android/rss_collector_android.sh`)
```bash
#!/system/bin/sh
# 适配 Android 环境

PID=$1
OUTPUT_FILE="/data/local/tmp/damoos/results/rss/${PID}.stat"

while kill -0 $PID 2>/dev/null; do
    # Android 的 ps 命令格式可能不同
    RSS=$(ps -p $PID -o rss= 2>/dev/null || cat /proc/$PID/status | grep VmRSS | awk '{print $2}')
    echo "$RSS" >> "$OUTPUT_FILE"
    sleep 1
done
```

#### 3.2 Runtime Collector (`android/runtime_collector_android.sh`)
```bash
#!/system/bin/sh

PID=$1
OUTPUT_FILE="/data/local/tmp/damoos/results/runtime/${PID}.stat"

START_TIME=$(date +%s)

while kill -0 $PID 2>/dev/null; do
    sleep 1
done

END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))
echo "$RUNTIME" > "$OUTPUT_FILE"
```

#### 3.3 Swapin/Swapout Collectors
```bash
# 从 /proc/vmstat 读取
# 适配 Android 的 vmstat 格式
```

---

### Phase 4: Scheme Adapters 适配（可选修改）

大部分 Scheme Adapters **不需要修改**，因为它们通过 Frontend 层交互。

可能需要调整：
- `polyfit_adapter.py` - 确保支持通过 ADB 应用 DAMON scheme
- `simple_adapter.sh` - 可能需要适配工作负载的重启逻辑

---

### Phase 5: DAMON Scheme 应用层

#### 5.1 创建 `adb_interface/damon_scheme_apply.sh`
```bash
功能：将优化算法计算出的 scheme 应用到 Android 设备

apply_scheme_to_android() {
    local min_size=$1
    local max_size=$2
    local min_age=$3
    local max_age=$4
    local action=$5
    
    # 转换参数格式（如 4K → 4096, 5s → 5000000us）
    # 通过 ADB 写入 debugfs
    adb shell "su -c 'echo off > /sys/kernel/debug/damon/monitor_on'"
    adb shell "su -c 'echo \"$scheme_str\" > /sys/kernel/debug/damon/schemes'"
    adb shell "su -c 'echo on > /sys/kernel/debug/damon/monitor_on'"
}
```

---

## 文件结构

```
damoos/
├── adb_interface/              # 新增目录
│   ├── README.md
│   ├── adb_utils.sh           # ADB 工具函数
│   ├── adb_damon_control.sh   # DAMON debugfs 控制
│   ├── adb_workload.sh        # Android 应用管理
│   ├── adb_metric_collector.sh # 远程指标收集
│   └── damon_scheme_apply.sh  # Scheme 应用
│
├── frontend/
│   ├── run_workloads.sh       # 修改：支持 Android
│   ├── get_metric.sh          # 修改：支持 Android
│   ├── wait_for_metric_collector.sh  # 修改
│   ├── cleanup.sh             # 修改
│   ├── metric_directory.txt   # 修改：添加 android 类型
│   └── workload_directory.txt # 修改：添加 Android 应用
│
├── metrics_collector/
│   └── collectors/
│       └── android/           # 新增目录
│           ├── rss_collector_android.sh
│           ├── runtime_collector_android.sh
│           ├── swapin_collector_android.sh
│           └── swapout_collector_android.sh
│
├── scheme_adapters/           # 大部分无需修改
│   ├── simple_adapter/
│   ├── polyfit_adapter/
│   └── ...
│
├── damoos.sh                  # 主入口（可能需要小改）
└── ANDROID_MIGRATION_PLAN.md  # 本文档
```

---

## 实施步骤

### Step 1: 准备工作
- [ ] 确认 ADB 连接正常
- [ ] 确认 Android 设备 root 权限
- [ ] 确认 `/sys/kernel/debug/damon/` 可访问
- [ ] 在 Android 创建工作目录 `/data/local/tmp/damoos/`

### Step 2: 实现 ADB 接口层
- [ ] 创建 `adb_interface/` 目录
- [ ] 实现 `adb_utils.sh`
- [ ] 实现 `adb_damon_control.sh` (debugfs 适配)
- [ ] 实现 `adb_workload.sh`
- [ ] 实现 `adb_metric_collector.sh`
- [ ] 编写测试脚本验证基本功能

### Step 3: 修改 Frontend 层
- [ ] 修改 `metric_directory.txt`
- [ ] 修改 `workload_directory.txt`
- [ ] 修改 `run_workloads.sh`
- [ ] 修改 `get_metric.sh`
- [ ] 修改 `wait_for_metric_collector.sh`
- [ ] 修改 `cleanup.sh`

### Step 4: 创建 Android 端脚本
- [ ] 创建 `metrics_collector/collectors/android/`
- [ ] 实现 Android 版 RSS collector
- [ ] 实现 Android 版 Runtime collector
- [ ] 实现 Android 版 Swapin/Swapout collectors
- [ ] 推送脚本到设备并测试

### Step 5: 集成测试
- [ ] 使用 simple_adapter 测试完整流程
- [ ] 验证指标收集准确性
- [ ] 验证 DAMON scheme 应用效果
- [ ] 测试多次迭代的稳定性

### Step 6: 适配其他 Adapters
- [ ] 测试 polyfit_adapter
- [ ] 测试 pso_adapter
- [ ] 测试 simple_rl_adapter
- [ ] 根据需要调整参数

---

## 技术细节

### DAMON debugfs 接口参考

```bash
# 1. 停止 DAMON
echo off > /sys/kernel/debug/damon/monitor_on

# 2. 设置目标进程
echo 1234 > /sys/kernel/debug/damon/target_ids

# 3. 设置采样属性 (sample_interval aggr_interval update_interval min_nr_regions max_nr_regions)
echo 5000 100000 1000000 10 1000 > /sys/kernel/debug/damon/attrs

# 4. 设置 scheme
# 格式：min_sz max_sz min_acc max_acc min_age max_age action
# 单位：size(bytes), age(us), acc(0-100)
echo "4096 max 0 100 5000000 max pageout" > /sys/kernel/debug/damon/schemes

# 5. 启动监控
echo on > /sys/kernel/debug/damon/monitor_on

# 6. 查看状态
cat /sys/kernel/debug/damon/monitor_on
```

### ADB 常用命令

```bash
# 检查连接
adb devices

# 执行命令（需要 root）
adb shell "su -c 'command'"

# 推送文件
adb push local_file /data/local/tmp/

# 拉取文件
adb pull /data/local/tmp/file local_path

# 获取应用 PID
adb shell "pidof com.miHoYo.Yuanshen"

# 启动应用
adb shell "am start -n com.miHoYo.Yuanshen/.MainActivity"

# 停止应用
adb shell "am force-stop com.miHoYo.Yuanshen"
```

### 单位转换表

```bash
# 时间单位（DAMON debugfs 使用微秒 us）
5s  → 5000000 us
10s → 10000000 us
60s → 60000000 us

# 大小单位（DAMON debugfs 使用字节）
4K  → 4096 bytes
8K  → 8192 bytes
1M  → 1048576 bytes

# 访问频率（百分比）
0-100 (保持原值)
```

---

## 预期挑战与解决方案

### 挑战 1: Android 应用启动时间长
**影响**：每次测试需要 30-60 秒启动应用  
**解决**：
- 优化启动流程，使用 saved state
- 减少单次测试时长，增加迭代次数
- 使用预热启动（keep app in memory）

### 挑战 2: ADB 连接稳定性
**影响**：长时间运行可能断开  
**解决**：
- 添加连接检查和自动重连机制
- 使用 `adb_utils.sh` 中的健壮性检查
- 考虑使用 USB 而非 WiFi ADB

### 挑战 3: Android 进程管理复杂
**影响**：应用可能有多个进程  
**解决**：
- 使用包名获取主进程 PID
- 可扩展为监控进程组
- 处理应用被系统 kill 的情况

### 挑战 4: debugfs 权限问题
**影响**：需要 root 和特定 SELinux 配置  
**解决**：
- 确保设备已 root
- 必要时调整 SELinux 策略（`setenforce 0`）
- 验证 mount 点是否可访问

---

## 成功标准

1. ✅ 能够通过 ADB 在 Android 启动和停止应用
2. ✅ 能够远程收集 RSS、runtime、swapin、swapout 指标
3. ✅ 能够通过 debugfs 控制 DAMON（启动/停止/配置 scheme）
4. ✅ simple_adapter 能完整运行并找到最优 scheme
5. ✅ polyfit_adapter 能完整运行并生成拟合曲线
6. ✅ 最优 scheme 应用后能观察到内存优化效果

---

## 预估工作量

- **Phase 1 (ADB 接口层)**：8-12 小时
- **Phase 2 (Frontend 改造)**：6-8 小时
- **Phase 3 (Android 脚本)**：4-6 小时
- **Phase 4 (Scheme 应用)**：3-4 小时
- **Phase 5 (测试调试)**：10-15 小时

**总计**：31-45 小时

---

## 后续优化方向

1. **性能优化**：
   - 并行测试多个 scheme
   - 缓存复用机制
   - 增量数据传输

2. **功能扩展**：
   - 支持多设备并行测试
   - 实时监控界面
   - 自动化测试报告生成

3. **稳定性增强**：
   - 错误恢复机制
   - 日志系统完善
   - 异常处理加强

4. **GUI 界面**：
   - Web 控制面板
   - 实时图表展示
   - 配置管理界面

---

## 参考资源

- [DAMON Documentation](https://damonitor.github.io)
- [Android Debug Bridge (ADB)](https://developer.android.com/studio/command-line/adb)
- Linux kernel debugfs interface
- Android Activity Manager 命令参考

---

**文档版本**：v1.0  
**创建日期**：2026-02-06  
**最后更新**：2026-02-06
