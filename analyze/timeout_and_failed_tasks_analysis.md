# 超时和失败任务详细分析报告

生成时间: 2025-11-06

## 概述

42个任务评估完成情况:
- ✅ **成功**: 33/42 (78.6%)
- ⏱️ **超时**: 8/42 (19.0%) - 超过900秒
- ❌ **失败**: 1/42 (2.4%)

---

## ❌ 失败任务：vectorized_newton

### 错误类型
**语法错误** - solver.py 第12行包含无效Unicode字符

### 详细错误信息
```
SyntaxError: invalid character '…' (U+2026)
```

### 根本原因
LLM生成的代码在第12行包含大量乱码和省略号字符（…），导致Python解析器无法解析该文件。

**问题代码片段**（第12行）:
```python
def func(self, x, a0, a1, a2, a3, a..??...??????????????????????????..?????..??..
```

### 解决方案
1. **重新生成**: 使用 `--force` 重新生成该任务的solver.py
2. **手动修复**: 查看 `raw_model_output.txt`，手动提取正确的代码
3. **备用方案**: 参考baseline实现，编写正确的vectorized Newton-Raphson solver

### 评估状态
- 未添加到 eval_summary.json
- 需要修复后重新评估

---

## ⏱️ 超时任务分析（8个任务）

所有超时任务均超过900秒（15分钟）timeout限制。

### 1. convex_hull

**算法**: Monotone Chain Algorithm (Graham Scan变体)

**性能问题**:
- **索引错误** (第32、44行):
  ```python
  while len(lower_idx) >= 2:
      o = sorted_points[lower_idx[-2]]  # ❌ 错误！
      a = sorted_points[lower_idx[-1]]  # ❌ 错误！
  ```
  `lower_idx` 存储的是**原始索引**，不是 `sorted_points` 的索引！
  
- **后果**: 
  - 数组越界导致IndexError
  - 或者访问错误的点导致无限循环

**正确做法**:
应该使用 `sorted_points` 的位置索引，或者重新设计数据结构。

**超时原因**: 索引错误导致无限循环或崩溃

---

### 2. integer_factorization

**算法**: Pollard's Rho with Brent's Cycle Detection + SymPy素性测试

**性能问题**:
- **无限循环风险** (第46-69行):
  ```python
  while True:  # ❌ 无终止条件！
      c = rng.randrange(1, n)
      # ... Pollard's Rho算法
      if d == n:
          continue  # 重试
      return d
  ```
  
- **大素数分解慢**: 对于数百位的大素数乘积，Pollard's Rho可能需要指数级时间
- **SymPy primality test**: `sympy.isprime()` 对大数很慢

**超时原因**: 
1. 对于困难实例（两个接近的大素数），Pollard's Rho效率极低
2. 缺少超时或迭代次数限制
3. 递归调用 `_factor()` 可能导致深度递归

**建议**: 添加最大迭代次数限制，或使用更高效的分解算法

---

### 3. min_dominating_set

**算法**: OR-Tools CP-SAT求解器

**性能问题**:
- **无时间限制** (第35行):
  ```python
  # No explicit time limit; solver will run until optimality is proven
  ```
  
- **NP-hard问题**: 最小支配集是NP-hard，对于大规模图可能需要指数时间

**超时原因**: 
CP-SAT求解器在困难实例上可能运行数小时甚至数天才能证明最优性

**解决方案**: 
添加时间限制参数:
```python
solver.parameters.max_time_in_seconds = 300  # 5分钟限制
```

---

### 4. feedback_controller_design

**算法**: 离散时间LQR控制器设计

**性能问题**:
- **低效的矩阵幂计算** (第38-39行):
  ```python
  for i in range(1, n):
      ctrb = np.hstack((ctrb, np.linalg.matrix_power(A, i) @ B))
  ```
  
- **问题**: `np.linalg.matrix_power(A, i)` 重复计算了A的幂次
- **复杂度**: O(n^4) 而不是 O(n^3)

**超时原因**: 
对于大规模系统（n > 100），重复的矩阵幂计算导致超时

**正确做法**:
```python
A_power = B
for i in range(1, n):
    A_power = A @ A_power  # 增量计算
    ctrb = np.hstack((ctrb, A_power))
```

---

### 5. qp (Quadratic Programming)

**算法**: scipy.optimize.minimize with trust-constr

**性能问题**:
- **迭代次数限制不足** (第79行):
  ```python
  "maxiter": 1000,
  ```
  
- **trust-constr方法慢**: 对于大规模QP问题，trust-constr不是最优选择

**超时原因**: 
1. 对于大规模QP（n > 1000），1000次迭代可能不够
2. trust-constr需要计算Hessian，对大问题很慢

**建议**: 
使用专门的QP求解器（CVXPY + OSQP/ECOS）会更快

---

### 6 & 7. convolve_1d & correlate_1d

**算法**: 直接调用 `np.convolve` / `np.correlate`

**性能问题**:
这两个实现看起来很简单，不应该超时。可能原因：
- **输入数据巨大**: 如果输入数组长度 > 10^7，卷积会很慢
- **多次调用**: correlate_1d循环处理多个pair

**超时原因**: 
测试数据可能包含超大数组，导致NumPy的卷积操作超时

**验证**: 需要检查测试数据的实际大小

---

### 8. minimum_volume_ellipsoid

**算法**: Khachiyan算法（迭代优化）

**性能问题**:
- **迭代上限** (第34行): `max_iter=1000`
- **线性方程求解** (第49行): 
  ```python
  invXQ = np.linalg.solve(X_mat, Q.T)  # 每次迭代
  ```
  
- **收敛慢**: 对于病态问题，Khachiyan算法收敛很慢

**超时原因**: 
1. 1000次迭代可能不够
2. 每次迭代都求解线性方程组，对大规模问题（n > 10000）很慢
3. 第70行的秩检查 `np.linalg.matrix_rank()` 也很慢

**建议**: 
增加迭代限制或使用更快的MVEE算法

---

## 总结与建议

### 失败原因分类

| 原因 | 任务数 | 任务列表 |
|------|--------|----------|
| 🐛 代码生成错误（乱码） | 1 | vectorized_newton |
| 🔄 无限循环/索引错误 | 2 | convex_hull, integer_factorization |
| ⏰ 缺少时间限制 | 1 | min_dominating_set |
| 🐌 算法效率低下 | 3 | feedback_controller_design, qp, minimum_volume_ellipsoid |
| 📦 输入数据过大 | 2 | convolve_1d, correlate_1d |

### 修复优先级

**高优先级**（容易修复）:
1. ✅ **vectorized_newton**: 重新生成代码
2. ✅ **min_dominating_set**: 添加 `max_time_in_seconds` 参数
3. ✅ **feedback_controller_design**: 修复矩阵幂计算

**中优先级**:
4. **convex_hull**: 修复索引逻辑
5. **integer_factorization**: 添加迭代次数限制

**低优先级**（需要算法替换）:
6. **qp**: 考虑使用CVXPY替代scipy
7. **minimum_volume_ellipsoid**: 优化或增加迭代限制
8. **convolve_1d / correlate_1d**: 检查测试数据，可能需要分块处理

### 下一步行动

1. ✅ **立即修复** vectorized_newton 的语法错误
2. 🔧 **批量修复** 3个高优先级任务
3. 📊 **重新评估** 修复后的任务（timeout改为1800s）
4. 📈 **监控** 超时任务的实际运行时间和瓶颈
