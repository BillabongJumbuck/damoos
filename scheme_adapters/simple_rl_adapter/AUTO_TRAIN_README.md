# 自动化训练脚本使用说明

## auto_train_douyin.sh

自动化抖音Q-Learning训练脚本，带自动刷屏功能和错误重试。

### 功能特性

✅ **自动训练** - 运行指定轮次的Q-Learning训练  
✅ **自动刷屏** - 每5秒自动上划屏幕，模拟真实刷抖音场景  
✅ **错误重试** - 训练失败自动重启，最多重试10次  
✅ **实时监控** - 显示训练进度和刷屏动作  
✅ **优雅退出** - Ctrl+C安全终止所有进程  

### 快速开始

```bash
cd /home/qjm/Desktop/damoos/scheme_adapters/simple_rl_adapter

# 运行50轮训练（推荐）
./auto_train_douyin.sh

# 或者在后台运行
nohup ./auto_train_douyin.sh > training.log 2>&1 &
```

### 配置参数

编辑脚本可修改以下参数：

```bash
APP_PACKAGE="com.ss.android.ugc.aweme"  # 应用包名
TRAINING_ITERATIONS=50                   # 训练轮次
SWIPE_INTERVAL=5                         # 刷屏间隔（秒）
MAX_ATTEMPTS=10                          # 最大重试次数
```

### 运行示例

```bash
# 标准运行（50轮，约35分钟）
./auto_train_douyin.sh

# 后台运行并记录日志
nohup ./auto_train_douyin.sh > douyin_training_$(date +%Y%m%d_%H%M%S).log 2>&1 &

# 查看后台进程
jobs -l

# 查看实时日志
tail -f douyin_training_*.log
```

### 输出说明

**训练过程中会看到：**
```
[17:20:15] Starting auto-swiper (every 5s)...
[17:20:15] Auto-swiper started (PID: 12345)
[17:20:15] Starting Q-Learning training...

Finding original RSS and refault rate of com.ss.android.ugc.aweme
[17:20:20] ↑ Swiped up
[17:20:25] ↑ Swiped up
...
```

**成功完成后：**
```
╔════════════════════════════════════════════════════════════╗
║              Training Completed Successfully!             ║
╚════════════════════════════════════════════════════════════╝

[17:55:30] Check results at:
  results/simple_rl_android/qvalue-com.ss.android.ugc.aweme.txt
```

### 结果查看

训练完成后，查看Q-Table和最佳方案：

```bash
cat results/simple_rl_android/qvalue-com.ss.android.ugc.aweme.txt
```

### 停止训练

```bash
# 前台运行时：按 Ctrl+C

# 后台运行时：
jobs -l  # 查看任务号
kill %1  # 终止任务1

# 或者直接杀死进程
pkill -f auto_train_douyin.sh
```

### 故障排除

**问题：No ADB device connected**  
解决：`adb devices` 确认设备连接，启用USB调试

**问题：Douyin app not installed**  
解决：检查包名是否正确 `adb shell pm list packages | grep douyin`

**问题：训练反复失败**  
解决：
1. 检查手机存储空间
2. 确认抖音应用可以正常启动
3. 查看详细日志排查具体错误

### 高级用法

**修改为微信训练：**
```bash
# 编辑脚本，修改：
APP_PACKAGE="com.tencent.mm"
TRAINING_ITERATIONS=30
SWIPE_INTERVAL=3  # 微信聊天滚动更快
```

**调整刷屏参数：**
```bash
# 编辑swipe_up()函数中的参数
local y_start=$((height * 80 / 100))  # 起始位置（屏幕80%高度）
local y_end=$((height * 20 / 100))    # 结束位置（屏幕20%高度）
local duration=300                     # 滑动时长（毫秒）
```

### 时间估算

| 轮次 | 预计时间 | 适用场景 |
|-----|---------|---------|
| 10 | 7分钟 | 快速测试 |
| 50 | 35分钟 | 推荐使用 |
| 100 | 70分钟 | 充分训练 |
| 200 | 2.3小时 | 深度优化 |

### 注意事项

⚠️ **训练期间手机会：**
- 每5秒自动上划屏幕
- 反复启动/关闭抖音应用
- 持续30秒运行后重启

⚠️ **建议：**
- 使用测试手机或闲置时段运行
- 保持手机屏幕常亮
- 确保手机电量充足或连接充电器
- 避免在训练期间手动操作手机
