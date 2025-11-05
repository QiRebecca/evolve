#!/bin/bash
set -e

# 激活conda环境
source /opt/mambaforge/etc/profile.d/conda.sh
conda activate env

SCRIPT_DIR="/data/zq/evolve/AlgoTune/scripts"
LOG_DIR="/data/zq/evolve/logs"
TARGET_TIME_MS=100

mkdir -p "$LOG_DIR"

MAIN_LOG="$LOG_DIR/generation_persistent_$(date +%Y%m%d_%H%M%S).log"
ERROR_LOG="$LOG_DIR/skipped_tasks.log"
PID_FILE="$LOG_DIR/algotune.pid"

echo "========================================" | tee -a "$MAIN_LOG"
echo "🚀 生成10样本数据集 (持久化模式)" | tee -a "$MAIN_LOG"
echo "时间: $(date)" | tee -a "$MAIN_LOG"
echo "Python: $(which python3)" | tee -a "$MAIN_LOG"
echo "Conda环境: $CONDA_DEFAULT_ENV" | tee -a "$MAIN_LOG"
echo "主日志: $MAIN_LOG" | tee -a "$MAIN_LOG"
echo "错误日志: $ERROR_LOG" | tee -a "$MAIN_LOG"
echo "PID文件: $PID_FILE" | tee -a "$MAIN_LOG"
echo "========================================" | tee -a "$MAIN_LOG"
echo "" | tee -a "$MAIN_LOG"

cd /data/zq/evolve/AlgoTune

# 运行主程序
python3 "$SCRIPT_DIR/submit_generate_python.py" \
    --target-time-ms $TARGET_TIME_MS \
    --standalone \
    2>&1 | while IFS= read -r line; do
        echo "$line" | tee -a "$MAIN_LOG"
        
        # 检测超时或错误
        if echo "$line" | grep -qiE "timeout|failed|error.*generation"; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line" >> "$ERROR_LOG"
        fi
    done

EXIT_CODE=${PIPESTATUS[0]}

echo "" | tee -a "$MAIN_LOG"
echo "========================================" | tee -a "$MAIN_LOG"
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ 全部完成！" | tee -a "$MAIN_LOG"
else
    echo "⚠️  运行结束，退出码: $EXIT_CODE" | tee -a "$MAIN_LOG"
    echo "查看错误日志: $ERROR_LOG" | tee -a "$MAIN_LOG"
fi
echo "时间: $(date)" | tee -a "$MAIN_LOG"
echo "========================================" | tee -a "$MAIN_LOG"

exit $EXIT_CODE
