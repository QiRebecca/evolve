#!/bin/bash
set +e

source /opt/mambaforge/etc/profile.d/conda.sh
conda activate env

SCRIPT_DIR="/data/zq/evolve/AlgoTune/scripts"
LOG_DIR="/data/zq/evolve/logs"
TARGET_TIME_MS=100
TASK_TIMEOUT=$((4 * 3600))

TASKS=(
  "discrete_log"
  "dynamic_assortment_planning"
  "max_independent_set_cpsat"
)

mkdir -p "$LOG_DIR"
MAIN_LOG="$LOG_DIR/small_k_$(date +%Y%m%d_%H%M%S).log"
SUCCESS_LOG="$LOG_DIR/small_k_success.log"

echo "========================================" | tee -a "$MAIN_LOG"
echo "🚀 使用小k值重跑3个超时任务" | tee -a "$MAIN_LOG"
echo "时间: $(date)" | tee -a "$MAIN_LOG"
echo "discrete_log: n=30" | tee -a "$MAIN_LOG"
echo "dynamic_assortment_planning: n=20" | tee -a "$MAIN_LOG"
echo "max_independent_set_cpsat: n=15" | tee -a "$MAIN_LOG"
echo "========================================" | tee -a "$MAIN_LOG"
echo "" | tee -a "$MAIN_LOG"

cd /data/zq/evolve/AlgoTune

SUCCESS_COUNT=0
FAILED_COUNT=0

for idx in "${!TASKS[@]}"; do
    TASK=${TASKS[$idx]}
    num=$((idx + 1))
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$MAIN_LOG"
    echo "[$num/3] 🔄 $TASK" | tee -a "$MAIN_LOG"
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
        echo "✅ [$num/3] '$TASK' 成功 (${DURATION}秒)" | tee -a "$MAIN_LOG"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $TASK - SUCCESS (${DURATION}s)" >> "$SUCCESS_LOG"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "❌ [$num/3] '$TASK' 失败 (退出码: $EXIT_CODE, ${DURATION}秒)" | tee -a "$MAIN_LOG"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi

    echo "📊 统计: ✅ $SUCCESS_COUNT | ❌ $FAILED_COUNT" | tee -a "$MAIN_LOG"
    echo "" | tee -a "$MAIN_LOG"
done

echo "========================================" | tee -a "$MAIN_LOG"
echo "🎉 完成" | tee -a "$MAIN_LOG"
echo "✅ 成功: $SUCCESS_COUNT | ❌ 失败: $FAILED_COUNT" | tee -a "$MAIN_LOG"
echo "========================================" | tee -a "$MAIN_LOG"
