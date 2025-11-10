#!/bin/bash
# 不使用 set -e，因为我们需要处理超时和失败的情况
set -u  # 只检查未定义变量

cd /data/zq/evolve

# 基础配置
export ALGO_TUNE_DATA_DIR=/data/zq/evolve/AlgoTune/data
export ALGO_TUNE_SPLIT=train
export ALGO_TUNE_NUM_RUNS=5

# 配置参数
ITERATIONS=5
CONFIG_FILE=openevolve/configs/algotune_prompt.yaml
PRIMARY_MODEL=o3
TIMEOUT_HOURS=2  # 每个task的超时时间（小时）
TIMEOUT_SECONDS=$((TIMEOUT_HOURS * 3600))

# 结果目录
RESULTS_BASE=openevolve/result

# 状态文件
STATE_FILE=logs/run_state.json
LOG_DIR=logs

# 创建日志目录
mkdir -p $LOG_DIR

# 加载状态（如果存在）
if [ -f "$STATE_FILE" ]; then
    echo "发现状态文件，尝试恢复..."
    COMPLETED_TASKS=$(python3 -c "import json; f=open('$STATE_FILE'); d=json.load(f); print(' '.join(d.get('completed', [])))" 2>/dev/null || echo "")
    FAILED_TASKS=$(python3 -c "import json; f=open('$STATE_FILE'); d=json.load(f); print(' '.join(d.get('failed', [])))" 2>/dev/null || echo "")
    echo "状态文件中已完成: $(echo $COMPLETED_TASKS | wc -w) tasks"
    echo "状态文件中已失败: $(echo $FAILED_TASKS | wc -w) tasks"
else
    COMPLETED_TASKS=""
    FAILED_TASKS=""
fi

# 扫描文件系统，找出所有已完成的tasks（通过检查best_program.py）
echo "扫描文件系统查找已完成的tasks..."
COMPLETED_FROM_FS=$(python3 << PYEOF
import json
import os

# 读取所有tasks
with open('reports/generation.json', 'r') as f:
    data = json.load(f)
tasks = sorted(data.keys())

# 扫描已完成的tasks
RESULTS_BASE = "openevolve/result"
completed = []
for task in tasks:
    output_dir = os.path.join(RESULTS_BASE, task)
    best_program = os.path.join(output_dir, "best_program.py")
    if os.path.exists(best_program):
        completed.append(task)

print(' '.join(completed))
PYEOF
)

# 合并状态文件和文件系统的已完成列表
if [ -n "$COMPLETED_FROM_FS" ]; then
    echo "文件系统中已完成: $(echo $COMPLETED_FROM_FS | wc -w) tasks"
    # 合并两个列表（去重）
    COMPLETED_TASKS=$(python3 -c "
completed_state = set('$COMPLETED_TASKS'.split())
completed_fs = set('$COMPLETED_FROM_FS'.split())
merged = list(completed_state | completed_fs)
print(' '.join(sorted(merged)))
")
else
    echo "文件系统中未找到已完成的tasks"
fi

echo "合并后已完成: $(echo $COMPLETED_TASKS | wc -w) tasks"
echo ""

# 开始时间
START_TIME=$(date +%s)
echo "开始运行所有tasks: $(date)"
echo "总tasks数: 141"
echo "超时设置: $TIMEOUT_HOURS 小时/task"
echo ""

# 计数器
TOTAL_TASKS=141
CURRENT=0
SUCCESS=0
FAILED=0
SKIPPED=0
TIMEOUT_COUNT=0

# 保存状态的函数
save_state() {
    python3 << PYEOF
import json
import os

state_file = "$STATE_FILE"
completed = "$COMPLETED_TASKS".split()
failed = "$FAILED_TASKS".split()

# 去重
completed = list(set([t for t in completed if t]))
failed = list(set([t for t in failed if t]))

state = {
    "completed": completed,
    "failed": failed,
    "total": 141,
    "success": $SUCCESS,
    "failed_count": $FAILED,
    "skipped": $SKIPPED,
    "timeout": $TIMEOUT_COUNT
}

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
PYEOF
}

# 检查task是否已完成
is_completed() {
    local task_name=$1
    local output_dir=$RESULTS_BASE/$task_name
    
    # 检查输出目录是否存在且有best_program.py
    if [ -f "$output_dir/best_program.py" ]; then
        return 0  # 已完成
    else
        return 1  # 未完成
    fi
}

# 运行每个task

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: aes_gcm_encryption"
echo "=========================================="

TASK_NAME=aes_gcm_encryption
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: affine_transform_2d"
echo "=========================================="

TASK_NAME=affine_transform_2d
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: aircraft_wing_design"
echo "=========================================="

TASK_NAME=aircraft_wing_design
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: articulation_points"
echo "=========================================="

TASK_NAME=articulation_points
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: base64_encoding"
echo "=========================================="

TASK_NAME=base64_encoding
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: battery_scheduling"
echo "=========================================="

TASK_NAME=battery_scheduling
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: chacha_encryption"
echo "=========================================="

TASK_NAME=chacha_encryption
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: channel_capacity"
echo "=========================================="

TASK_NAME=channel_capacity
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: chebyshev_center"
echo "=========================================="

TASK_NAME=chebyshev_center
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: cholesky_factorization"
echo "=========================================="

TASK_NAME=cholesky_factorization
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: clustering_outliers"
echo "=========================================="

TASK_NAME=clustering_outliers
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: communicability"
echo "=========================================="

TASK_NAME=communicability
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: convex_hull"
echo "=========================================="

TASK_NAME=convex_hull
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: convolve2d_full_fill"
echo "=========================================="

TASK_NAME=convolve2d_full_fill
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: convolve_1d"
echo "=========================================="

TASK_NAME=convolve_1d
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: correlate2d_full_fill"
echo "=========================================="

TASK_NAME=correlate2d_full_fill
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: correlate_1d"
echo "=========================================="

TASK_NAME=correlate_1d
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: count_connected_components"
echo "=========================================="

TASK_NAME=count_connected_components
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: count_riemann_zeta_zeros"
echo "=========================================="

TASK_NAME=count_riemann_zeta_zeros
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: cumulative_simpson_1d"
echo "=========================================="

TASK_NAME=cumulative_simpson_1d
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: cumulative_simpson_multid"
echo "=========================================="

TASK_NAME=cumulative_simpson_multid
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: cvar_projection"
echo "=========================================="

TASK_NAME=cvar_projection
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: cyclic_independent_set"
echo "=========================================="

TASK_NAME=cyclic_independent_set
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: dct_type_I_scipy_fftpack"
echo "=========================================="

TASK_NAME=dct_type_I_scipy_fftpack
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: delaunay"
echo "=========================================="

TASK_NAME=delaunay
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: dijkstra_from_indices"
echo "=========================================="

TASK_NAME=dijkstra_from_indices
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: discrete_log"
echo "=========================================="

TASK_NAME=discrete_log
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: dst_type_II_scipy_fftpack"
echo "=========================================="

TASK_NAME=dst_type_II_scipy_fftpack
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: earth_movers_distance"
echo "=========================================="

TASK_NAME=earth_movers_distance
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: edge_expansion"
echo "=========================================="

TASK_NAME=edge_expansion
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: eigenvalues_complex"
echo "=========================================="

TASK_NAME=eigenvalues_complex
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: eigenvalues_real"
echo "=========================================="

TASK_NAME=eigenvalues_real
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: eigenvectors_complex"
echo "=========================================="

TASK_NAME=eigenvectors_complex
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: eigenvectors_real"
echo "=========================================="

TASK_NAME=eigenvectors_real
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: elementwise_integration"
echo "=========================================="

TASK_NAME=elementwise_integration
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: feedback_controller_design"
echo "=========================================="

TASK_NAME=feedback_controller_design
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: fft_cmplx_scipy_fftpack"
echo "=========================================="

TASK_NAME=fft_cmplx_scipy_fftpack
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: fft_convolution"
echo "=========================================="

TASK_NAME=fft_convolution
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: fft_real_scipy_fftpack"
echo "=========================================="

TASK_NAME=fft_real_scipy_fftpack
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: firls"
echo "=========================================="

TASK_NAME=firls
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: generalized_eigenvalues_complex"
echo "=========================================="

TASK_NAME=generalized_eigenvalues_complex
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: generalized_eigenvalues_real"
echo "=========================================="

TASK_NAME=generalized_eigenvalues_real
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: generalized_eigenvectors_complex"
echo "=========================================="

TASK_NAME=generalized_eigenvectors_complex
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: generalized_eigenvectors_real"
echo "=========================================="

TASK_NAME=generalized_eigenvectors_real
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: graph_global_efficiency"
echo "=========================================="

TASK_NAME=graph_global_efficiency
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: graph_isomorphism"
echo "=========================================="

TASK_NAME=graph_isomorphism
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: graph_laplacian"
echo "=========================================="

TASK_NAME=graph_laplacian
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: group_lasso"
echo "=========================================="

TASK_NAME=group_lasso
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: gzip_compression"
echo "=========================================="

TASK_NAME=gzip_compression
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: integer_factorization"
echo "=========================================="

TASK_NAME=integer_factorization
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: job_shop_scheduling"
echo "=========================================="

TASK_NAME=job_shop_scheduling
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: kalman_filter"
echo "=========================================="

TASK_NAME=kalman_filter
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: kcenters"
echo "=========================================="

TASK_NAME=kcenters
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: kernel_density_estimation"
echo "=========================================="

TASK_NAME=kernel_density_estimation
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: ks_test_2samp"
echo "=========================================="

TASK_NAME=ks_test_2samp
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: l0_pruning"
echo "=========================================="

TASK_NAME=l0_pruning
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: l1_pruning"
echo "=========================================="

TASK_NAME=l1_pruning
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: lasso"
echo "=========================================="

TASK_NAME=lasso
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: least_squares"
echo "=========================================="

TASK_NAME=least_squares
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: linear_system_solver"
echo "=========================================="

TASK_NAME=linear_system_solver
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: lp_centering"
echo "=========================================="

TASK_NAME=lp_centering
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: lp_mdp"
echo "=========================================="

TASK_NAME=lp_mdp
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: lqr"
echo "=========================================="

TASK_NAME=lqr
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: lti_simulation"
echo "=========================================="

TASK_NAME=lti_simulation
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: lu_factorization"
echo "=========================================="

TASK_NAME=lu_factorization
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: lyapunov_stability"
echo "=========================================="

TASK_NAME=lyapunov_stability
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: markowitz"
echo "=========================================="

TASK_NAME=markowitz
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: matrix_completion"
echo "=========================================="

TASK_NAME=matrix_completion
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: matrix_exponential"
echo "=========================================="

TASK_NAME=matrix_exponential
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: matrix_multiplication"
echo "=========================================="

TASK_NAME=matrix_multiplication
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: matrix_sqrt"
echo "=========================================="

TASK_NAME=matrix_sqrt
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: max_clique_cpsat"
echo "=========================================="

TASK_NAME=max_clique_cpsat
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: max_common_subgraph"
echo "=========================================="

TASK_NAME=max_common_subgraph
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: max_flow_min_cost"
echo "=========================================="

TASK_NAME=max_flow_min_cost
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: max_weighted_independent_set"
echo "=========================================="

TASK_NAME=max_weighted_independent_set
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: min_dominating_set"
echo "=========================================="

TASK_NAME=min_dominating_set
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: min_weight_assignment"
echo "=========================================="

TASK_NAME=min_weight_assignment
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: minimum_spanning_tree"
echo "=========================================="

TASK_NAME=minimum_spanning_tree
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: minimum_volume_ellipsoid"
echo "=========================================="

TASK_NAME=minimum_volume_ellipsoid
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: multi_dim_knapsack"
echo "=========================================="

TASK_NAME=multi_dim_knapsack
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: nmf"
echo "=========================================="

TASK_NAME=nmf
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: ode_brusselator"
echo "=========================================="

TASK_NAME=ode_brusselator
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: ode_fitzhughnagumo"
echo "=========================================="

TASK_NAME=ode_fitzhughnagumo
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: ode_hires"
echo "=========================================="

TASK_NAME=ode_hires
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: ode_hodgkinhuxley"
echo "=========================================="

TASK_NAME=ode_hodgkinhuxley
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: ode_lorenz96_nonchaotic"
echo "=========================================="

TASK_NAME=ode_lorenz96_nonchaotic
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: ode_lotkavolterra"
echo "=========================================="

TASK_NAME=ode_lotkavolterra
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: ode_nbodyproblem"
echo "=========================================="

TASK_NAME=ode_nbodyproblem
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: ode_seirs"
echo "=========================================="

TASK_NAME=ode_seirs
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: ode_stiff_robertson"
echo "=========================================="

TASK_NAME=ode_stiff_robertson
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: ode_stiff_vanderpol"
echo "=========================================="

TASK_NAME=ode_stiff_vanderpol
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: odr"
echo "=========================================="

TASK_NAME=odr
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: optimal_advertising"
echo "=========================================="

TASK_NAME=optimal_advertising
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: outer_product"
echo "=========================================="

TASK_NAME=outer_product
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: pagerank"
echo "=========================================="

TASK_NAME=pagerank
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: pca"
echo "=========================================="

TASK_NAME=pca
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: pde_burgers1d"
echo "=========================================="

TASK_NAME=pde_burgers1d
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: pde_heat1d"
echo "=========================================="

TASK_NAME=pde_heat1d
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: polynomial_mixed"
echo "=========================================="

TASK_NAME=polynomial_mixed
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: polynomial_real"
echo "=========================================="

TASK_NAME=polynomial_real
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: power_control"
echo "=========================================="

TASK_NAME=power_control
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: procrustes"
echo "=========================================="

TASK_NAME=procrustes
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: psd_cone_projection"
echo "=========================================="

TASK_NAME=psd_cone_projection
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: qp"
echo "=========================================="

TASK_NAME=qp
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: qr_factorization"
echo "=========================================="

TASK_NAME=qr_factorization
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: quantile_regression"
echo "=========================================="

TASK_NAME=quantile_regression
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: queens_with_obstacles"
echo "=========================================="

TASK_NAME=queens_with_obstacles
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: queuing"
echo "=========================================="

TASK_NAME=queuing
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: qz_factorization"
echo "=========================================="

TASK_NAME=qz_factorization
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: randomized_svd"
echo "=========================================="

TASK_NAME=randomized_svd
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: rbf_interpolation"
echo "=========================================="

TASK_NAME=rbf_interpolation
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: robust_kalman_filter"
echo "=========================================="

TASK_NAME=robust_kalman_filter
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: robust_linear_program"
echo "=========================================="

TASK_NAME=robust_linear_program
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: rocket_landing_optimization"
echo "=========================================="

TASK_NAME=rocket_landing_optimization
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: rotate_2d"
echo "=========================================="

TASK_NAME=rotate_2d
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: set_cover"
echo "=========================================="

TASK_NAME=set_cover
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: set_cover_conflicts"
echo "=========================================="

TASK_NAME=set_cover_conflicts
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: sha256_hashing"
echo "=========================================="

TASK_NAME=sha256_hashing
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: shift_2d"
echo "=========================================="

TASK_NAME=shift_2d
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: shortest_path_dijkstra"
echo "=========================================="

TASK_NAME=shortest_path_dijkstra
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: sinkhorn"
echo "=========================================="

TASK_NAME=sinkhorn
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: sparse_eigenvectors_complex"
echo "=========================================="

TASK_NAME=sparse_eigenvectors_complex
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: sparse_lowest_eigenvalues_posdef"
echo "=========================================="

TASK_NAME=sparse_lowest_eigenvalues_posdef
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: sparse_lowest_eigenvectors_posdef"
echo "=========================================="

TASK_NAME=sparse_lowest_eigenvectors_posdef
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: sparse_pca"
echo "=========================================="

TASK_NAME=sparse_pca
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: stable_matching"
echo "=========================================="

TASK_NAME=stable_matching
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: svd"
echo "=========================================="

TASK_NAME=svd
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: svm"
echo "=========================================="

TASK_NAME=svm
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: sylvester_solver"
echo "=========================================="

TASK_NAME=sylvester_solver
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: tensor_completion_3d"
echo "=========================================="

TASK_NAME=tensor_completion_3d
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: toeplitz_solver"
echo "=========================================="

TASK_NAME=toeplitz_solver
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: tsp"
echo "=========================================="

TASK_NAME=tsp
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: two_eigenvalues_around_0"
echo "=========================================="

TASK_NAME=two_eigenvalues_around_0
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: unit_simplex_projection"
echo "=========================================="

TASK_NAME=unit_simplex_projection
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: upfirdn1d"
echo "=========================================="

TASK_NAME=upfirdn1d
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: vectorized_newton"
echo "=========================================="

TASK_NAME=vectorized_newton
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: vehicle_routing"
echo "=========================================="

TASK_NAME=vehicle_routing
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: vertex_cover"
echo "=========================================="

TASK_NAME=vertex_cover
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: voronoi_diagram"
echo "=========================================="

TASK_NAME=voronoi_diagram
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: water_filling"
echo "=========================================="

TASK_NAME=water_filling
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi

echo ""
echo "[$CURRENT/$TOTAL_TASKS] Processing task: zoom_2d"
echo "=========================================="

TASK_NAME=zoom_2d
OUTPUT_DIR=$RESULTS_BASE/$TASK_NAME
LOG_FILE=$LOG_DIR/$TASK_NAME.log

# 检查是否已完成（先检查文件系统，再检查状态列表）
SKIP_THIS_TASK=0
if is_completed "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME already completed (found best_program.py), skipping..."
    SKIP_THIS_TASK=1
elif echo "$COMPLETED_TASKS" | grep -qw "$TASK_NAME"; then
    echo "⏭️  Task $TASK_NAME marked as completed in state file, skipping..."
    SKIP_THIS_TASK=1
fi

if [ $SKIP_THIS_TASK -eq 1 ]; then
    SKIPPED=$((SKIPPED + 1))
    CURRENT=$((CURRENT + 1))
else
    echo "🚀 Starting task: $TASK_NAME"
    echo "   Timeout: $TIMEOUT_HOURS hours"
    echo "   Output: $OUTPUT_DIR"
    echo "   Log: $LOG_FILE"

    # 运行OpenEvolve with timeout
    TIMEOUT_EXIT_CODE=0
    timeout $TIMEOUT_SECONDS bash -c "
        ALGO_TUNE_TASK=$TASK_NAME \
        python openevolve/openevolve-run.py \
            /data/zq/evolve/AlgoTune/AlgoTuneTasks/$TASK_NAME/$TASK_NAME.py \
            AlgoTune/evaluate.py \
            --config $CONFIG_FILE \
            --primary-model $PRIMARY_MODEL \
            --iterations $ITERATIONS \
            --output $OUTPUT_DIR \
            2>&1 | tee $LOG_FILE
    " || TIMEOUT_EXIT_CODE=$?

    # 检查结果
    if [ $TIMEOUT_EXIT_CODE -eq 124 ]; then
        # 超时（exit code 124是timeout命令的超时退出码）
        echo "⏱️  Task $TASK_NAME TIMEOUT after $TIMEOUT_HOURS hours"
        FAILED=$((FAILED + 1))
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    elif [ $TIMEOUT_EXIT_CODE -eq 0 ]; then
        # 成功完成
        if is_completed "$TASK_NAME"; then
            echo "✓ Task $TASK_NAME completed successfully"
            SUCCESS=$((SUCCESS + 1))
            COMPLETED_TASKS="$COMPLETED_TASKS $TASK_NAME"
            save_state
        else
            echo "⚠️  Task $TASK_NAME finished but no best_program.py found"
            FAILED=$((FAILED + 1))
            FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
            save_state
        fi
    else
        # 其他错误
        echo "✗ Task $TASK_NAME failed with exit code $TIMEOUT_EXIT_CODE"
        FAILED=$((FAILED + 1))
        FAILED_TASKS="$FAILED_TASKS $TASK_NAME"
        save_state
    fi
    
    CURRENT=$((CURRENT + 1))
fi
# 结束统计
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_HOUR=$((ELAPSED_MIN / 60))

echo ""
echo "=========================================="
echo "所有tasks运行完成"
echo "=========================================="
echo "总tasks: $TOTAL_TASKS"
echo "成功: $SUCCESS"
echo "失败: $FAILED (其中超时: $TIMEOUT_COUNT)"
echo "跳过: $SKIPPED"
echo "总耗时: ${ELAPSED_HOUR}小时${ELAPSED_MIN}分钟"
echo "完成时间: $(date)"
echo ""
echo "状态文件: $STATE_FILE"
echo "日志目录: $LOG_DIR"

