
# 📊 Generation vs Eval Summary 对比报告

**生成时间**: 2025-11-05 19:19:48

---

## 数据一致性状态

✅ **数据一致性**: 通过
- 所有 eval_summary.json 中的任务都在 generation.json 中
- 没有孤立的评估任务

---

## 基本统计

| 文件 | 任务数 |
|------|--------|
| generation.json | 141 |
| eval_summary.json | 99 |
| 两者共有 | 99 |
| 只在 generation | 42 |
| 只在 eval | 0 |

---

## 🔧 修改过的任务状态分析

修改过的17个任务（有 .bak 文件）分布：

### ✅ 在 generation 中且有成功 baseline (12个)

1. `feedback_controller_design` - n=1390, baseline=18.4ms - ⏳ 未评估
2. `job_shop_scheduling` - n=19, baseline=77.9ms - ⏳ 未评估
3. `max_clique_cpsat` - n=9, baseline=23.4ms - ⏳ 未评估
4. `max_common_subgraph` - n=4, baseline=82.3ms - ⏳ 未评估
5. `max_weighted_independent_set` - n=57, baseline=33.3ms - ⏳ 未评估
6. `min_dominating_set` - n=14, baseline=100.1ms - ⏳ 未评估
7. `minimum_volume_ellipsoid` - n=500, baseline=76.5ms - ⏳ 未评估
8. `multi_dim_knapsack` - n=23, baseline=43.1ms - ⏳ 未评估
9. `queens_with_obstacles` - n=12, baseline=62.5ms - ⏳ 未评估
10. `set_cover_conflicts` - n=61, baseline=40.9ms - ⏳ 未评估
11. `tsp` - n=34, baseline=83.4ms - ⏳ 未评估
12. `vehicle_routing` - n=12, baseline=92.3ms - ⏳ 未评估


### ❌ 完全缺失 (5个)

这些任务在 generation 和 eval 中都没有：

1. `graph_coloring_assign` - 未生成数据或评估失败
2. `kd_tree` - 未生成数据或评估失败
3. `kmeans` - 未生成数据或评估失败
4. `rectanglepacking` - 未生成数据或评估失败
5. `spectral_clustering` - 未生成数据或评估失败


---

## 📊 Eval Summary 质量分析

eval_summary.json 中的99个任务质量分布：


| 状态 | 数量 | 占比 |
|------|------|------|
| ✅ 完全成功 (100%) | 63 | 63.6% |
| ⚠️ 部分成功 (>0%, <100%) | 8 | 8.1% |
| ❌ 完全失败 (0%) | 28 | 28.3% |

### 部分成功的任务详情

- `ode_fitzhughnagumo`: 90% (9/10)
- `fft_convolution`: 90% (9/10)
- `pde_burgers1d`: 90% (9/10)
- `least_squares`: 80% (8/10)
- `ode_nbodyproblem`: 60% (6/10)
- `pde_heat1d`: 50% (5/10)
- `max_flow_min_cost`: 50% (5/10)
- `kernel_density_estimation`: 40% (4/10)


---

## 🎯 下一步行动建议

### 1. 对修改过的12个任务运行 test evaluation

这些任务在 generation 中有成功的 baseline，需要运行测试集评估：

```bash
cd /data/zq/evolve
source "$(conda info --base)/etc/profile.d/conda.sh" && conda activate env
nohup python scripts/batch_generate_test_baselines.py \
  --tasks \
    feedback_controller_design \
    job_shop_scheduling \
    max_clique_cpsat \
    max_common_subgraph \
    max_weighted_independent_set \
    min_dominating_set \
    minimum_volume_ellipsoid \
    multi_dim_knapsack \
    queens_with_obstacles \
    set_cover_conflicts \
    tsp \
    vehicle_routing \
  --data-dir AlgoTune/data \
  --output reports/test_baseline.json \
  --num-runs 10 \
  --timeout 600 \
  --skip-existing > logs/test_eval_12modified.log 2>&1 &
```

### 2. 调查完全缺失的5个任务

这些任务需要检查为什么没有生成数据：
- graph_coloring_assign
- kd_tree
- kmeans
- rectanglepacking
- spectral_clustering

---

**报告生成**: 2025-11-05 19:19:48
