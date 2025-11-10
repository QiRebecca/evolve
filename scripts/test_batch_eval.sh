#!/bin/bash
# Test batch evaluation script for specific tasks
# This script runs in background and can continue after logout
# Usage: nohup bash scripts/test_batch_eval.sh > logs/test_batch_eval.log 2>&1 &

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
echo "Testing batch evaluation for specific tasks"
echo "=========================================="
echo "Model: $MODEL"
echo "Tasks: communicability max_common_subgraph max_clique_cpsat"
echo "Summary file: $SUMMARY_FILE"
echo "=========================================="

# Run batch evaluation with specific tasks
python scripts/batch_eval_solvers.py \
    --model "$MODEL" \
    --results-dir "$RESULTS_DIR" \
    --generation-file "$GENERATION_FILE" \
    --summary-file "$SUMMARY_FILE" \
    --num-runs "$NUM_RUNS" \
    --timeout "$TIMEOUT" \
    --no-skip-existing \
    --tasks communicability max_common_subgraph max_clique_cpsat

echo "=========================================="
echo "Batch evaluation completed"
echo "=========================================="

