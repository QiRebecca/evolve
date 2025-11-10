#!/bin/bash
# Batch evaluation script for SLOW tasks with extended timeout
# Usage: nohup bash scripts/run_slow_tasks_batch.sh > logs/run_slow_tasks_$(date +%Y%m%d_%H%M%S).log 2>&1 &

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
TIMEOUT=3600  # Extended timeout: 1 hour (3600s) instead of 10 minutes

cd /data/zq/evolve

echo "=========================================="
echo "Starting batch evaluation for SLOW tasks"
echo "=========================================="
echo "Model: $MODEL"
echo "Summary file: $SUMMARY_FILE"
echo "Timeout per task: ${TIMEOUT}s (1 hour)"
echo "Start time: $(date)"
echo "=========================================="

# Run batch evaluation for slow tasks only
python scripts/batch_eval_solvers.py \
    --model "$MODEL" \
    --results-dir "$RESULTS_DIR" \
    --generation-file "$GENERATION_FILE" \
    --summary-file "$SUMMARY_FILE" \
    --num-runs "$NUM_RUNS" \
    --timeout "$TIMEOUT" \
    --tasks convex_hull convolve_1d correlate_1d dijkstra_from_indices discrete_log vertex_cover

echo "=========================================="
echo "Batch evaluation completed"
echo "End time: $(date)"
echo "=========================================="

