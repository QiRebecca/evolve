#!/bin/bash
set +e

source /opt/mambaforge/etc/profile.d/conda.sh
conda activate env

# 限制OpenMP线程数，解决libgomp问题
export OMP_NUM_THREADS=8
export MKL_NUM_THREADS=8
export OPENBLAS_NUM_THREADS=8

SCRIPT_DIR="/data/zq/evolve/AlgoTune/scripts"
LOG_DIR="/data/zq/evolve/logs"
TARGET_TIME_MS=100
TASK_TIMEOUT=$((4 * 3600))

TASKS=(
  "feedback_controller_design"
  "graph_coloring_assign"
  "job_shop_scheduling"
  "kd_tree"
  "kmeans"
  "max_clique_cpsat"
  "max_common_subgraph"
  "max_weighted_independent_set"
  "min_dominating_set"
  "minimum_volume_ellipsoid"
  "multi_dim_knapsack"
  "queens_with_obstacles"
  "rectanglepacking"
  "set_cover_conflicts"
  "spectral_clustering"
  "tsp"
  "vehicle_routing"
)

mkdir -p "$LOG_DIR"
MAIN_LOG="$LOG_DIR/fixed17_$(date +%Y%m%d_%H%M%S).log"
SUCCESS_LOG="$LOG_DIR/fixed17_success.log"
TIMEOUT_LOG="$LOG_DIR/fixed17_timeout.log"

echo "========================================" | tee -a "$MAIN_LOG"
echo "🚀 运行修复后的17个任务" | tee -a "$MAIN_LOG"
echo "时间: $(date)" | tee -a "$MAIN_LOG"
echo "修改:" | tee -a "$MAIN_LOG"
echo "  • 12个OR-Tools任务: num_workers=24" | tee -a "$MAIN_LOG"
echo "  • 2个CVXPY任务: solver=ECOS" | tee -a "$MAIN_LOG"
echo "  • 环境变量: OMP_NUM_THREADS=8" | tee -a "$MAIN_LOG"
echo "超时: 4小时/任务" | tee -a "$MAIN_LOG"
echo "========================================" | tee -a "$MAIN_LOG"
echo "" | tee -a "$MAIN_LOG"

cd /data/zq/evolve/AlgoTune

SUCCESS_COUNT=0
TIMEOUT_COUNT=0
FAILED_COUNT=0

total=${#TASKS[@]}
for idx in "${!TASKS[@]}"; do
    TASK=${TASKS[$idx]}
    num=$((idx + 1))
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$MAIN_LOG"
    echo "[$num/$total] 🔄 $TASK" | tee -a "$MAIN_LOG"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$MAIN_LOG"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$MAIN_LOG"

    START=$(date +%s)
    timeout ${TASK_TIMEOUT}s python3 "$SCRIPT_DIR/submit_generate_python.py" \
        --target-time-ms $TARGET_TIME_MS \
        --standalone \
        --sequential \
        --tasks "$TASK" \
        2>&1 | tee -a "$MAIN_LOG"

    EXIT_CODE=${PIPESTATUS[0]}
    END=$(date +%s)
    DURATION=$((END - START))

    echo "" | tee -a "$MAIN_LOG"

    # 任务完成后清理，防止线程累积
    echo "🧹 清理进程..." | tee -a "$MAIN_LOG"
    pkill -9 -f "submit_generate_python.py" 2>/dev/null
    sleep 5
    echo "" | tee -a "$MAIN_LOG"

    if [ $EXIT_CODE -eq 0 ]; then
        echo "✅ [$num/$total] '$TASK' 成功 (${DURATION}秒)" | tee -a "$MAIN_LOG"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $TASK - SUCCESS (${DURATION}s)" >> "$SUCCESS_LOG"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    elif [ $EXIT_CODE -eq 124 ] || [ $EXIT_CODE -eq 137 ]; then
        echo "⏱️ [$num/$total] '$TASK' 超时 (${DURATION}秒)" | tee -a "$MAIN_LOG"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $TASK - TIMEOUT" >> "$TIMEOUT_LOG"
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
    else
        echo "❌ [$num/$total] '$TASK' 失败 (退出码: $EXIT_CODE, ${DURATION}秒)" | tee -a "$MAIN_LOG"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi

    echo "📊 统计: ✅ $SUCCESS_COUNT | ⏱️ $TIMEOUT_COUNT | ❌ $FAILED_COUNT" | tee -a "$MAIN_LOG"
    echo "" | tee -a "$MAIN_LOG"
done

echo "========================================" | tee -a "$MAIN_LOG"
echo "🎉 完成" | tee -a "$MAIN_LOG"
echo "✅ 成功: $SUCCESS_COUNT | ⏱️ 超时: $TIMEOUT_COUNT | ❌ 失败: $FAILED_COUNT" | tee -a "$MAIN_LOG"
echo "========================================" | tee -a "$MAIN_LOG"

