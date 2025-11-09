#!/bin/bash

set +e

source /opt/mambaforge/etc/profile.d/conda.sh
conda activate env

SCRIPT_DIR="/data/zq/evolve/AlgoTune/scripts"
LOG_DIR="/data/zq/evolve/logs"
TARGET_TIME_MS=100
TASK_TIMEOUT=$((4 * 3600))  # 4 hours per task

TASKS=(
  "capacitated_facility_location"
  "convex_hull"
  "cyclic_independent_set"
  "discrete_log"
  "dynamic_assortment_planning"
  "edge_expansion"
  "integer_factorization"
  "max_independent_set_cpsat"
)

mkdir -p "$LOG_DIR"
MAIN_LOG="$LOG_DIR/retry_timeout_$(date +%Y%m%d_%H%M%S).log"
SUCCESS_LOG="$LOG_DIR/retry_success.log"
TIMEOUT_LOG="$LOG_DIR/retry_timeouts.log"

echo "========================================" | tee -a "$MAIN_LOG"
echo "🚀 重新尝试超时任务 (单任务超时: $((TASK_TIMEOUT/3600)) 小时)" | tee -a "$MAIN_LOG"
echo "时间: $(date)" | tee -a "$MAIN_LOG"
echo "日志: $MAIN_LOG" | tee -a "$MAIN_LOG"
echo "========================================" | tee -a "$MAIN_LOG"
echo "" | tee -a "$MAIN_LOG"

cd /data/zq/evolve/AlgoTune

SUCCESS_COUNT=0
TIMEOUT_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

total=${#TASKS[@]}
for idx in "${!TASKS[@]}"; do
    TASK=${TASKS[$idx]}
    num=$((idx + 1))
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$MAIN_LOG"
    echo "[$num/$total] 🔄 开始任务: $TASK" | tee -a "$MAIN_LOG"
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

    if [ $EXIT_CODE -eq 0 ]; then
        echo "✅ [$num/$total] '$TASK' 成功完成 (用时: ${DURATION}秒)" | tee -a "$MAIN_LOG"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $TASK - SUCCESS (${DURATION}s)" >> "$SUCCESS_LOG"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    elif [ $EXIT_CODE -eq 124 ]; then
        echo "⏱️ [$num/$total] '$TASK' 超时 (${TASK_TIMEOUT}秒)" | tee -a "$MAIN_LOG"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $TASK - TIMEOUT after ${TASK_TIMEOUT}s" >> "$TIMEOUT_LOG"
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
    else
        if grep -q "already complete" "$MAIN_LOG"; then
            echo "⏭️ [$num/$total] '$TASK' 已完成，跳过" | tee -a "$MAIN_LOG"
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        else
            echo "❌ [$num/$total] '$TASK' 失败 (退出码: $EXIT_CODE, 用时: ${DURATION}秒)" | tee -a "$MAIN_LOG"
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    fi

    echo "" | tee -a "$MAIN_LOG"
    echo "📊 当前统计: ✅ $SUCCESS_COUNT | ⏱️ $TIMEOUT_COUNT | ❌ $FAILED_COUNT | ⏭️ $SKIPPED_COUNT" | tee -a "$MAIN_LOG"
    echo "" | tee -a "$MAIN_LOG"
done

echo "========================================" | tee -a "$MAIN_LOG"
echo "🎉 任务重试完成" | tee -a "$MAIN_LOG"
echo "时间: $(date)" | tee -a "$MAIN_LOG"
echo "总计: $total" | tee -a "$MAIN_LOG"
echo "✅ 成功: $SUCCESS_COUNT" | tee -a "$MAIN_LOG"
echo "⏱️ 超时: $TIMEOUT_COUNT" | tee -a "$MAIN_LOG"
echo "❌ 失败: $FAILED_COUNT" | tee -a "$MAIN_LOG"
echo "⏭️ 跳过: $SKIPPED_COUNT" | tee -a "$MAIN_LOG"
echo "========================================" | tee -a "$MAIN_LOG"
