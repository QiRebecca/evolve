#!/bin/bash
# 快速检查 AlgoTune 运行状态

echo "========================================="
echo "📊 AlgoTune 运行状态"
echo "时间: $(date)"
echo "========================================="
echo ""

# 检查进程
echo "🔍 进程状态："
if ps aux | grep "submit_generate_python.py" | grep -v grep > /dev/null; then
    echo "  ✅ Python进程运行中"
    ps aux | grep "submit_generate_python.py" | grep -v grep | head -2
else
    echo "  ❌ Python进程未运行"
fi
echo ""

# 最新日志
echo "📝 最新日志 (最后10行):"
echo "----------------------------------------"
find /data/zq/evolve/logs -name "generation_10samples_*.log" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2- | xargs tail -10 2>/dev/null || echo "  未找到日志文件"
echo ""

# 超时任务
echo "⏱️ 超时任务："
echo "----------------------------------------"
if [ -f "/data/zq/evolve/logs/task_timeouts.log" ]; then
    timeout_count=$(wc -l < /data/zq/evolve/logs/task_timeouts.log)
    if [ "$timeout_count" -gt 0 ]; then
        echo "  发现 $timeout_count 个超时任务："
        tail -5 /data/zq/evolve/logs/task_timeouts.log
    else
        echo "  ✅ 暂无超时任务"
    fi
else
    echo "  ✅ 暂无超时任务"
fi
echo ""

# 已完成任务统计
echo "📈 进度统计："
echo "----------------------------------------"
if [ -f "/data/zq/evolve/reports/generation.json" ]; then
    total_tasks=$(grep -c '"n":' /data/zq/evolve/reports/generation.json)
    echo "  已处理任务数: $total_tasks"
fi
echo ""

echo "========================================="
echo "💡 常用命令："
echo "  实时查看日志: tail -f /data/zq/evolve/logs/generation_10samples_*.log"
echo "  查看超时日志: cat /data/zq/evolve/logs/task_timeouts.log"
echo "  停止程序: kill \$(cat /data/zq/evolve/logs/algotune_running.pid)"
echo "========================================="


