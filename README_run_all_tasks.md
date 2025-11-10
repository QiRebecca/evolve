# 批量运行所有AlgoTune Tasks脚本说明

## 功能特性

### 1. ✅ 超时跳过
- **超时时间**: 每个task默认2小时（可在脚本中修改`TIMEOUT_HOURS`）
- **超时处理**: 超时后自动跳过，继续下一个task
- **超时记录**: 超时的tasks会被记录到失败列表和状态文件

### 2. ✅ 断点重连
- **自动检测**: 通过检查`best_program.py`是否存在判断task是否已完成
- **状态保存**: 运行状态实时保存到`logs/run_state.json`
- **智能跳过**: 重新运行时会自动跳过已完成的tasks

### 3. ✅ 状态管理
- **状态文件**: `logs/run_state.json`
- **记录内容**: 
  - `completed`: 已完成的tasks列表
  - `failed`: 失败的tasks列表
  - `success`: 成功数量
  - `failed_count`: 失败数量
  - `timeout`: 超时数量
  - `skipped`: 跳过数量

## 使用方法

### 首次运行
```bash
cd /data/zq/evolve
bash run_all_tasks.sh
```

### 后台运行（推荐）
```bash
cd /data/zq/evolve
nohup bash run_all_tasks.sh > run_all_tasks.log 2>&1 &
```

### 中断后恢复
如果脚本中断，直接重新运行即可：
```bash
bash run_all_tasks.sh
```
脚本会自动检测并跳过已完成的tasks。

### 查看进度
```bash
# 查看实时日志
tail -f run_all_tasks.log

# 查看状态文件
cat logs/run_state.json | python3 -m json.tool

# 查看某个task的日志
tail -f logs/<task_name>.log
```

## 配置参数

在脚本中可以修改以下参数：

```bash
TIMEOUT_HOURS=2          # 每个task的超时时间（小时）
ITERATIONS=5             # OpenEvolve迭代次数
ALGO_TUNE_NUM_RUNS=5     # 每个问题运行的次数
```

## 输出结构

```
openevolve/result/
├── <task_name>/
│   ├── best_program.py      # 最佳程序（用于判断是否完成）
│   ├── best_program_info.json
│   └── ...
└── ...

logs/
├── run_state.json           # 运行状态
├── <task_name>.log          # 每个task的日志
└── ...
```

## 注意事项

1. **超时设置**: 根据task的复杂度调整`TIMEOUT_HOURS`，简单task可能只需要30分钟，复杂task可能需要更长时间
2. **磁盘空间**: 确保有足够的磁盘空间存储结果和日志
3. **资源监控**: 长时间运行建议监控CPU和内存使用情况
4. **日志清理**: 定期清理旧日志文件以节省空间

## 故障排查

### 如果某个task一直超时
- 检查该task的日志：`cat logs/<task_name>.log`
- 考虑增加该task的超时时间或单独运行

### 如果状态文件损坏
- 删除状态文件：`rm logs/run_state.json`
- 脚本会重新开始，但会通过检查`best_program.py`跳过已完成的tasks

### 如果脚本意外退出
- 直接重新运行脚本即可，会自动从断点继续

