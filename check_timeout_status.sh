#!/bin/bash
# 检查带真实超时机制的任务运行状态

LOG_DIR="/data/zq/evolve/logs"

echo "════════════════════════════════════════════════════════"
echo "📊 任务运行状态（真实1小时超时）"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════════"
echo ""

# 检查进程
echo "🔍 运行状态:"
if ps aux | grep "run_sequential_with_real_timeout" | grep -v grep > /dev/null; then
    echo "  ✅ 脚本正在运行"
    ps aux | grep "run_sequential_with_real_timeout" | grep -v grep | head -2
else
    echo "  ❌ 脚本未运行"
fi
echo ""

# 当前Python进程
echo "🐍 Python进程:"
PYTHON_COUNT=$(ps aux | grep "python3.*submit_generate" | grep -v grep | wc -l)
if [ $PYTHON_COUNT -gt 0 ]; then
    echo "  ✅ $PYTHON_COUNT 个Python进程在运行"
    ps aux | grep "python3.*submit_generate" | grep -v grep | head -3
else
    echo "  ⏸️ 没有Python进程（可能在任务间隙）"
fi
echo ""

# 统计信息
echo "📈 任务统计:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -f "$LOG_DIR/task_success.log" ]; then
    SUCCESS=$(wc -l < "$LOG_DIR/task_success.log" 2>/dev/null || echo 0)
    echo "  ✅ 成功: $SUCCESS 个任务"
else
    echo "  ✅ 成功: 0 个任务"
fi

if [ -f "$LOG_DIR/task_timeouts.log" ]; then
    TIMEOUT=$(wc -l < "$LOG_DIR/task_timeouts.log" 2>/dev/null || echo 0)
    echo "  ⏱️ 超时: $TIMEOUT 个任务"
    if [ $TIMEOUT -gt 0 ]; then
        echo ""
        echo "     最近超时的任务:"
        tail -3 "$LOG_DIR/task_timeouts.log" | sed 's/^/     /'
    fi
else
    echo "  ⏱️ 超时: 0 个任务"
fi
echo ""

# 最新日志
echo "📝 最新活动（最后10行）:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
LATEST_LOG=$(find "$LOG_DIR" -name "sequential_timeout_*.log" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
if [ -n "$LATEST_LOG" ]; then
    tail -10 "$LATEST_LOG" | grep -v "CODE_DIR\|Attempting to load\|Successfully loaded" | tail -10
else
    echo "  未找到日志文件"
fi
echo ""

echo "════════════════════════════════════════════════════════"
echo "💡 有用命令:"
echo "  实时查看: tail -f $LOG_DIR/sequential_timeout_*.log"
echo "  查看超时: cat $LOG_DIR/task_timeouts.log"
echo "  查看成功: cat $LOG_DIR/task_success.log"
echo "  停止程序: kill \$(cat $LOG_DIR/algotune_running.pid)"
echo "════════════════════════════════════════════════════════"



