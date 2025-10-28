#!/bin/bash
set +e  # 不要在错误时退出

source /opt/mambaforge/etc/profile.d/conda.sh
conda activate env

SCRIPT_DIR="/data/zq/evolve/AlgoTune/scripts"
LOG_DIR="/data/zq/evolve/logs"
TARGET_TIME_MS=100
TASK_TIMEOUT=3600  # 1小时

mkdir -p "$LOG_DIR"
MAIN_LOG="$LOG_DIR/sequential_timeout_$(date +%Y%m%d_%H%M%S).log"
TIMEOUT_LOG="$LOG_DIR/task_timeouts.log"
SUCCESS_LOG="$LOG_DIR/task_success.log"

echo "========================================" | tee -a "$MAIN_LOG"
echo "🚀 顺序执行任务（真实1小时超时）" | tee -a "$MAIN_LOG"
echo "时间: $(date)" | tee -a "$MAIN_LOG"
echo "单任务超时: 1小时（3600秒）" | tee -a "$MAIN_LOG"
echo "主日志: $MAIN_LOG" | tee -a "$MAIN_LOG"
echo "超时日志: $TIMEOUT_LOG" | tee -a "$MAIN_LOG"
echo "========================================" | tee -a "$MAIN_LOG"
echo "" | tee -a "$MAIN_LOG"

cd /data/zq/evolve/AlgoTune

# 获取所有任务列表
ALL_TASKS=$(python3 -c "
import sys
sys.path.insert(0, '/data/zq/evolve/AlgoTune/scripts')
from AlgoTuner.task_lists import get_task_list
tasks = get_task_list('all')
print(' '.join(tasks))
" 2>/dev/null)

# 如果获取失败，使用硬编码列表
if [ -z "$ALL_TASKS" ]; then
    ALL_TASKS="btsp capacitated_facility_location chacha_encryption channel_capacity chebyshev_center cholesky_factorization clustering_outliers communicability convex_hull"
fi

TASK_COUNT=0
SUCCESS_COUNT=0
TIMEOUT_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

for TASK in $ALL_TASKS; do
    TASK_COUNT=$((TASK_COUNT + 1))
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$MAIN_LOG"
    echo "[$TASK_COUNT] 🔄 开始任务: $TASK" | tee -a "$MAIN_LOG"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$MAIN_LOG"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$MAIN_LOG"
    
    TASK_START=$(date +%s)
    
    # 使用timeout命令运行单个任务（独立Python进程）
    timeout ${TASK_TIMEOUT}s python3 "$SCRIPT_DIR/submit_generate_python.py" \
        --target-time-ms $TARGET_TIME_MS \
        --standalone \
        --sequential \
        --tasks "$TASK" \
        2>&1 | tee -a "$MAIN_LOG"
    
    EXIT_CODE=${PIPESTATUS[0]}
    TASK_END=$(date +%s)
    DURATION=$((TASK_END - TASK_START))
    
    echo "" | tee -a "$MAIN_LOG"
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo "✅ [$TASK_COUNT] '$TASK' 成功完成 (用时: ${DURATION}秒)" | tee -a "$MAIN_LOG"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $TASK - SUCCESS (${DURATION}s)" >> "$SUCCESS_LOG"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        
    elif [ $EXIT_CODE -eq 124 ]; then
        echo "⏱️ [$TASK_COUNT] '$TASK' 超时跳过 (${TASK_TIMEOUT}秒)" | tee -a "$MAIN_LOG"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $TASK - TIMEOUT after ${TASK_TIMEOUT}s" >> "$TIMEOUT_LOG"
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        
    else
        # 检查是否是因为任务已完成而跳过
        if grep -q "already complete" "$MAIN_LOG" 2>/dev/null; then
            echo "⏭️ [$TASK_COUNT] '$TASK' 已完成，跳过" | tee -a "$MAIN_LOG"
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        else
            echo "❌ [$TASK_COUNT] '$TASK' 失败 (退出码: $EXIT_CODE, 用时: ${DURATION}秒)" | tee -a "$MAIN_LOG"
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    fi
    
    echo "" | tee -a "$MAIN_LOG"
    
    # 显示进度
    PROCESSED=$((SUCCESS_COUNT + TIMEOUT_COUNT + FAILED_COUNT + SKIPPED_COUNT))
    echo "📊 进度: $PROCESSED 已处理 | ✅ $SUCCESS_COUNT 成功 | ⏱️ $TIMEOUT_COUNT 超时 | ❌ $FAILED_COUNT 失败 | ⏭️ $SKIPPED_COUNT 跳过" | tee -a "$MAIN_LOG"
    echo "" | tee -a "$MAIN_LOG"
done

echo "========================================" | tee -a "$MAIN_LOG"
echo "🎉 全部任务完成！" | tee -a "$MAIN_LOG"
echo "时间: $(date)" | tee -a "$MAIN_LOG"
echo "" | tee -a "$MAIN_LOG"
echo "📈 最终统计:" | tee -a "$MAIN_LOG"
echo "  总任务数: $TASK_COUNT" | tee -a "$MAIN_LOG"
echo "  ✅ 成功: $SUCCESS_COUNT" | tee -a "$MAIN_LOG"
echo "  ⏱️ 超时: $TIMEOUT_COUNT" | tee -a "$MAIN_LOG"
echo "  ❌ 失败: $FAILED_COUNT" | tee -a "$MAIN_LOG"
echo "  ⏭️ 跳过: $SKIPPED_COUNT" | tee -a "$MAIN_LOG"
echo "" | tee -a "$MAIN_LOG"
echo "📁 日志位置:" | tee -a "$MAIN_LOG"
echo "  主日志: $MAIN_LOG" | tee -a "$MAIN_LOG"
echo "  超时日志: $TIMEOUT_LOG" | tee -a "$MAIN_LOG"
echo "  成功日志: $SUCCESS_LOG" | tee -a "$MAIN_LOG"
echo "========================================" | tee -a "$MAIN_LOG"

