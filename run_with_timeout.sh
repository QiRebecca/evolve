#!/bin/bash

source /opt/mambaforge/etc/profile.d/conda.sh
conda activate env

SCRIPT_DIR="/data/zq/evolve/AlgoTune/scripts"
LOG_DIR="/data/zq/evolve/logs"
TARGET_TIME_MS=100

mkdir -p "$LOG_DIR"
MAIN_LOG="$LOG_DIR/generation_10samples_$(date +%Y%m%d_%H%M%S).log"
TIMEOUT_LOG="$LOG_DIR/timeout_tasks.log"

TOTAL_TIMEOUT=$((100 * 60 * 60))

echo "========================================" | tee -a "$MAIN_LOG"
echo "🚀 开始生成10样本数据集" | tee -a "$MAIN_LOG"
echo "时间: $(date)" | tee -a "$MAIN_LOG"
echo "Python: $(which python3)" | tee -a "$MAIN_LOG"
echo "Conda环境: $CONDA_DEFAULT_ENV" | tee -a "$MAIN_LOG"
echo "日志: $MAIN_LOG" | tee -a "$MAIN_LOG"
echo "总超时: 100小时" | tee -a "$MAIN_LOG"
echo "注意: Python脚本内部应处理单任务超时和跳过逻辑" | tee -a "$MAIN_LOG"
echo "========================================" | tee -a "$MAIN_LOG"
echo "" | tee -a "$MAIN_LOG"

cd /data/zq/evolve/AlgoTune

timeout ${TOTAL_TIMEOUT}s python3 "$SCRIPT_DIR/submit_generate_python.py" \
    --target-time-ms $TARGET_TIME_MS \
    --standalone \
    2>&1 | while IFS= read -r line; do
        echo "$line" | tee -a "$MAIN_LOG"
        
        if echo "$line" | grep -qiE "timeout|超时|卡住"; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line" >> "$TIMEOUT_LOG"
        fi
    done

EXIT_CODE=${PIPESTATUS[0]}

echo "" | tee -a "$MAIN_LOG"
echo "========================================" | tee -a "$MAIN_LOG"
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ 全部完成！" | tee -a "$MAIN_LOG"
elif [ $EXIT_CODE -eq 124 ]; then
    echo "⏱️  总超时(100小时)，可手动重新运行继续" | tee -a "$MAIN_LOG"
else
    echo "⚠️  运行结束，退出码: $EXIT_CODE" | tee -a "$MAIN_LOG"
fi
echo "时间: $(date)" | tee -a "$MAIN_LOG"
if [ -f "$TIMEOUT_LOG" ]; then
    echo "超时任务日志: $TIMEOUT_LOG" | tee -a "$MAIN_LOG"
fi
echo "========================================" | tee -a "$MAIN_LOG"

exit $EXIT_CODE
