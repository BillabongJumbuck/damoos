# Simple RL Adapter - Android版本

## 简介

**simple_rl_adapter_android.py** - 使用 Q-Learning 强化学习算法为 Android 应用自动找出最佳 DAMON 方案。

### 算法原理

- **算法**: 表格式 Q-Learning（Tabular Q-Learning）
- **状态空间**: 21个状态（基于RSS开销：0%~-100%，每5%一档）
- **动作空间**: 30个动作（6种min_age × 5种min_size组合）
  - min_age: 3s, 5s, 7s, 9s, 11s, 13s
  - min_size: 4KB, 8KB, 12KB, 16KB, 20KB
- **奖励函数**: `score = -(rss_overhead×0.5 + runtime_overhead×0.5)`

### 优势

✅ **智能学习**: 越跑越聪明，自动探索最优方案  
✅ **快速收敛**: 通常20-30次迭代即可找到好方案  
✅ **适应性强**: 可学习不同应用的特性  
✅ **无需手动调参**: 自动探索参数空间

## 使用方法

### 基础用法

```bash
cd /home/qjm/Desktop/damoos/scheme_adapters/simple_rl_adapter

# 对抖音进行优化（使用默认参数）
python3 simple_rl_adapter_android.py douyin

# 对微信进行优化
python3 simple_rl_adapter_android.py wechat

# 对淘宝进行优化
python3 simple_rl_adapter_android.py taobao
```

### 高级参数

```bash
# 快速测试（10次迭代）
python3 simple_rl_adapter_android.py douyin -n 10

# 深度训练（100次迭代）
python3 simple_rl_adapter_android.py douyin -n 100

# 调整学习率
python3 simple_rl_adapter_android.py douyin --learning_rate 0.3

# 调整探索率（更多随机探索）
python3 simple_rl_adapter_android.py douyin --epsilon 0.3

# 所有参数组合
python3 simple_rl_adapter_android.py douyin \
  --num_iterations 50 \
  --learning_rate 0.2 \
  --epsilon 0.2 \
  --discount 0.9
```

### 参数说明

| 参数 | 简写 | 默认值 | 说明 |
|------|------|--------|------|
| --num_iterations | -n | 50 | 训练迭代次数 |
| --learning_rate | -lr | 0.2 | 学习率（0-1） |
| --epsilon | -e | 0.2 | 探索率（0-1，越大越随机） |
| --discount | -d | 0.9 | 折扣因子（0-1） |

## 工作流程

### 阶段 1: 基线测试（Baseline）

```
[1/3] 启动应用 → 收集30s数据 → 停止应用
[2/3] 启动应用 → 收集30s数据 → 停止应用
[3/3] 启动应用 → 收集30s数据 → 停止应用
→ 计算平均 RSS 和 Runtime
```

### 阶段 2: Q-Learning 训练

```
For iteration 1 to N:
  1. 启动应用（reset环境）
  2. 根据 ε-greedy 策略选择动作
     - 以概率 ε 随机探索新动作
     - 以概率 (1-ε) 选择当前最优动作
  3. 应用 DAMON scheme
  4. 收集30s性能数据
  5. 计算奖励值
  6. 更新 Q-Table
  7. 停止应用
```

### 阶段 3: 最终评估

```
运行5次评估测试（每次都用最优动作）
→ 计算平均奖励
→ 输出最佳方案
```

## 输出结果

### 训练过程输出

```
Iteration 15/50
Started douyin, PID: 8123
  Testing scheme: min_size=12K, min_age=7s (action 14)
    Runtime: 30.12s (overhead: +0.40%)
    RSS: 1185432KB (overhead: -1.51%)
    Score: 0.56
  → Iteration 15 reward: 0.56
```

### 最终结果

```
Average Evaluation Reward: 2.34

Best DAMON scheme found:
  min_size: 8K
  min_age: 5s
  action: pageout
  Expected improvement: 2.34%
```

### Q-values 文件

训练完成后，Q-Table 保存在：
```
/home/qjm/Desktop/damoos/results/simple_rl_android/qvalue-{app_name}.txt
```

可以复用这个文件进行快速评估，无需重新训练。

## 时间估算

| 迭代次数 | 预计耗时 | 适用场景 |
|---------|---------|---------|
| 10 | ~15分钟 | 快速测试 |
| 30 | ~45分钟 | 一般优化 |
| 50 | ~75分钟 | 推荐配置 |
| 100 | ~150分钟 | 深度优化 |

*每次迭代约1.5分钟（30s运行 + 启停应用 + DAMON操作）*

## 与 simple_adapter 对比

| 特性 | simple_adapter | simple_rl_adapter |
|------|----------------|-------------------|
| 算法 | 暴力搜索 | Q-Learning |
| 搜索策略 | 遍历所有组合 | 智能探索 |
| 迭代次数 | 固定60次 (20配置×3次) | 可配置（推荐50次） |
| 收敛速度 | 线性 | 指数级 |
| 适应性 | 静态 | 动态学习 |
| 可复用性 | 低 | 高（Q-Table可复用） |

## 最佳实践

### 1. 首次优化新应用

```bash
# 使用默认参数
python3 simple_rl_adapter_android.py your_app
```

### 2. 快速验证

```bash
# 10次迭代快速测试
python3 simple_rl_adapter_android.py your_app -n 10
```

### 3. 生产环境优化

```bash
# 100次深度训练
python3 simple_rl_adapter_android.py your_app -n 100 -lr 0.15 -e 0.1
```

### 4. 调试模式

```bash
# 高探索率，观察更多方案
python3 simple_rl_adapter_android.py your_app -n 20 -e 0.5
```

## 注意事项

⚠️ **电池电量**: 确保手机电量充足（>50%）  
⚠️ **测试时长**: 50次迭代约需75分钟  
⚠️ **网络连接**: 保持 ADB 连接稳定  
⚠️ **应用状态**: 测试期间请勿手动操作手机  

## 故障排查

### Q: 训练很慢，如何加速？

A: 减少迭代次数 `-n 20` 或缩短测试时间（修改代码中的 sleep(30)）

### Q: 奖励值总是负数？

A: 正常现象。负数表示开销，越接近0越好，正数表示性能提升。

### Q: 如何复用已训练的 Q-Table？

A: 暂不支持，但可以参考 qvalue-{app}.txt 文件中的最优动作。

### Q: 如何选择最佳参数？

A: 
- epsilon: 训练初期用0.3（多探索），后期用0.1（多利用）
- learning_rate: 一般用0.2，数据噪音大时用0.1
- num_iterations: 至少30次，推荐50次

## 示例

### 优化抖音（推荐配置）

```bash
cd /home/qjm/Desktop/damoos/scheme_adapters/simple_rl_adapter
python3 simple_rl_adapter_android.py douyin -n 50
```

输出示例：
```
Original RSS: 1203705 KB
Original Runtime: 30.00 seconds

Iteration 1/50
  Testing scheme: min_size=8K, min_age=5s (action 6)
    Score: -2.15

...

Iteration 50/50
  Testing scheme: min_size=4K, min_age=9s (action 15)
    Score: 1.87

Average Evaluation Reward: 2.34

Best DAMON scheme found:
  min_size: 8K
  min_age: 5s
  action: pageout
  Expected improvement: 2.34%
```

### 快速测试微信

```bash
python3 simple_rl_adapter_android.py wechat -n 10 -e 0.4
```

## 技术细节

### Q-Learning 公式

```
Q(s,a) ← Q(s,a) + α[r + γ·max(Q(s',a')) - Q(s,a)]

其中:
- s: 当前状态（RSS开销区间）
- a: 动作（DAMON方案）
- r: 即时奖励（性能提升）
- s': 下一状态
- α: 学习率（0.2）
- γ: 折扣因子（0.9）
```

### 状态编码

```
state_index = min(int(-(rss_overhead / 5)), 19)

示例:
- rss_overhead = -2.3%  → state 0
- rss_overhead = -7.8%  → state 1
- rss_overhead = -23.1% → state 4
- rss_overhead = +5.0%  → state 20
```

### 动作编码

```
action = age_idx * 5 + size_idx

示例:
- action 0  = min_age=3s, min_size=4KB
- action 14 = min_age=7s, min_size=12KB
- action 29 = min_age=13s, min_size=20KB
```

## 未来改进

- [ ] 支持加载已有 Q-Table 继续训练
- [ ] 支持多指标权重自定义
- [ ] 支持增量学习（online learning）
- [ ] 添加早停策略（early stopping）
- [ ] 可视化 Q-Table 热力图

## 相关文件

- `simple_rl_adapter_android.py` - Android版本主程序
- `simple_rl_adapter.py` - 原始Linux版本
- `requirements.txt` - Python依赖
- `README.md` - 原始文档

## 作者

Original: Amazon DAMOOS Team  
Android Port: DAMOOS Android Migration Project
