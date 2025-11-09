# 当前状况分析与行动计划

生成时间: 2025-11-06 15:20

---

## 📊 当前情况

### 1. 磁盘空间问题
- `/data`: 633G 可用 (92% 使用) ✅ 正常
- `/` (根分区): **100% 满** ❌ 导致bash无法创建临时文件
- 已清理旧的评估进程（2个僵尸进程，运行了74天和8天）

### 2. 评估进度
- `eval_summary.json`: **133个** chatgptoss-20b 任务
- 今天重新评估: **1/7** 完成
  - ✅ `convex_hull`: 10/10 有效（**原以为超时，实际成功！**）
  - ❌ 剩余6个未完成

### 3. 原8个"超时"任务真相

经过实际测试发现：

| 任务 | 诊断结果 | 处理状态 |
|------|---------|---------|
| ✅ **convex_hull** | 能正常运行（47秒/问题） | 已完成 10/10 |
| ❌ **convolve_1d** | 数据格式错误 | 未评估 |
| ❌ **correlate_1d** | 数据格式错误 | 未评估 |
| ❌ **qp** | 数据格式错误 | 未评估 |
| ❌ **minimum_volume_ellipsoid** | 数据格式错误 | 未评估 |
| ❌ **vectorized_newton** | 语法错误（乱码） | 未评估 |
| ❓ **feedback_controller_design** | 单个问题0.00s（误报） | 未评估 |
| ⏱️ **min_dominating_set** | 真的很慢（60s+/问题） | 未评估 |
| ⏱️ **integer_factorization** | 真的很慢/卡住 | 未评估 |

---

## 🗑️ 需要清理的

### 已清理 ✅
1. 旧的僵尸评估进程（2个，PID: 2310918, 2373585）
2. /tmp下的临时文件

### 需要保留 ✓
1. `eval_summary.json` - 主要结果文件
2. `generation.json` - 任务元数据
3. `test_baseline.json` - 基准数据
4. `AlgoTune/results/chatgptoss-20b/*/solver.py` - 所有solver代码（评测对象）

---

## 📋 下一步计划

### 方案A：快速完成（推荐）

**目标**: 正确记录剩余6个任务的失败/成功状态

```bash
cd /data/zq/evolve
source "$(conda info --base)/etc/profile.d/conda.sh" && conda activate env

# 依次评估，不设置timeout（让脚本自然失败或成功）
tasks="convolve_1d correlate_1d qp minimum_volume_ellipsoid vectorized_newton feedback_controller_design"

for task in $tasks; do
    echo "评估: $task"
    python scripts/save_eval_to_summary.py \
        --task $task \
        --model chatgptoss-20b \
        --solver AlgoTune/results/chatgptoss-20b/$task/solver.py \
        --generation-file reports/generation.json \
        --summary-file results/eval_summary.json \
        --num-runs 10
    echo "完成: $task"
done
```

**预计时间**: 5-15分钟
- 5个数据格式错误：立即失败（<10秒）
- 1个feedback_controller_design：应该成功（<1分钟）

**预期结果**:
- 成功: 34/42 (81%)
  - 33（之前成功）+ 1（convex_hull）+ 1（feedback_controller_design）= 35
- 失败: 6个（记录错误原因）
- 超时: 2个（min_dominating_set, integer_factorization）

---

### 方案B：尝试min_dominating_set（可选，需1小时）

在方案A完成后，如果想提高成功率：

```bash
# 后台运行，限时3600秒
nohup timeout 3600 python scripts/save_eval_to_summary.py \
    --task min_dominating_set \
    --model chatgptoss-20b \
    --solver AlgoTune/results/chatgptoss-20b/min_dominating_set/solver.py \
    --generation-file reports/generation.json \
    --summary-file results/eval_summary.json \
    --num-runs 10 \
    > logs/eval_min_dominating_set_$(date +%Y%m%d_%H%M%S).log 2>&1 &
```

**可能结果**: 成功率提升到 35/42 (83.3%) 或超时

---

### 方案C：放弃

**不再尝试**:
- `integer_factorization` - 有 `while True` 无限循环风险

**最终状态**:
- 该任务保持"timeout"状态
- 在报告中注明原因："Pollard's Rho algorithm too slow for difficult instances"

---

## 🎯 推荐执行顺序

1. ✅ **立即执行方案A**（5-15分钟）
2. ⏸️ **观察结果**
3. 🔄 **可选执行方案B**（1小时，后台运行）
4. ❌ **确认放弃integer_factorization**

---

## 📈 最终预期结果

| 状态 | 数量 | 任务列表 |
|------|------|---------|
| ✅ 成功 | 34-35 | 包括convex_hull, feedback_controller_design, 可能包括min_dominating_set |
| ❌ 失败 | 6 | convolve_1d, correlate_1d, qp, minimum_volume_ellipsoid, vectorized_newton, 可能还有min_dominating_set |
| ⏱️ 超时 | 1-2 | integer_factorization, 可能包括min_dominating_set |

**成功率**: 81.0% - 83.3%

---

## ⚠️ 注意事项

1. **solver.py 不能修改** - 这是评测对象
2. **失败是正常的** - LLM生成的代码有质量问题
3. **记录失败原因** - eval_summary.json会自动记录错误信息
4. **超时也是结果** - 说明算法效率问题

---

**准备好了吗？执行方案A！** 🚀

