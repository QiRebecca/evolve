#!/bin/bash
# Batch evaluation script for ALL tasks
# This script runs in background and can continue after logout
# Usage: nohup bash scripts/run_all_tasks_batch.sh > logs/run_all_tasks_$(date +%Y%m%d_%H%M%S).log 2>&1 &

# Don't exit on error - continue with next task
set +e

# Activate conda environment
source $(conda info --base)/etc/profile.d/conda.sh
conda activate env

MODEL="chatgptoss-20b"
RESULTS_DIR="AlgoTune/results"
GENERATION_FILE="reports/generation.json"
SUMMARY_FILE="results/eval_gptoss20b.json"
NUM_RUNS=10
TIMEOUT=600

cd /data/zq/evolve

echo "=========================================="
echo "Starting batch evaluation for ALL tasks"
echo "=========================================="
echo "Model: $MODEL"
echo "Summary file: $SUMMARY_FILE"
echo "Timeout per task: ${TIMEOUT}s"
echo "Start time: $(date)"
echo "=========================================="

# Run batch evaluation for all tasks
python scripts/batch_eval_solvers.py \
    --model "$MODEL" \
    --results-dir "$RESULTS_DIR" \
    --generation-file "$GENERATION_FILE" \
    --summary-file "$SUMMARY_FILE" \
    --num-runs "$NUM_RUNS" \
    --timeout "$TIMEOUT" \
    --no-skip-existing

echo "=========================================="
echo "Batch evaluation completed"
echo "End time: $(date)"
echo "=========================================="

