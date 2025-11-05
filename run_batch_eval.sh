#!/bin/bash

# Batch evaluate all 40 iterations on test dataset
# This script evaluates each iteration from llm_responses using the paper's methodology

set -e

echo "=========================================="
echo "Batch Evaluation of All Iterations"
echo "=========================================="
echo ""

# Set environment variables
export ALGO_TUNE_TASK="aes_gcm_encryption"
export ALGO_TUNE_DATA_DIR="/data/zq/evolve/AlgoTune/data"
export ALGO_TUNE_SPLIT="test"  # Use TEST dataset for final evaluation
export DACE_cache_dir="/data/zq/evolve/.dace_cache"
mkdir -p "$DACE_cache_dir"

cd /data/zq/evolve

echo "Task: $ALGO_TUNE_TASK"
echo "Data Dir: $ALGO_TUNE_DATA_DIR"
echo "Split: $ALGO_TUNE_SPLIT"
echo ""
echo "Baseline: Will auto-detect test_baseline.json if exists"
echo "  - If test_baseline.json exists: TEST baseline vs TEST solver"
echo "  - Otherwise: TRAIN baseline (generation.json) vs TEST solver"
echo ""
echo "Num Runs: 10 (per problem, as per paper)"
echo ""
echo "NOTE: For fair comparison, first run ./run_generate_test_baseline.sh"
echo ""

# Run batch evaluation
python scripts/batch_eval_iterations.py \
  --task aes_gcm_encryption \
  --responses-dir llm_responses \
  --data-dir AlgoTune/data \
  --generation-file reports/generation.json \
  --output results/all_iterations_eval.json \
  --num-runs 10

echo ""
echo "=========================================="
echo "Evaluation Complete!"
echo "=========================================="
echo "Results saved to: results/all_iterations_eval.json"
echo ""
echo "To view the best iteration:"
echo "  cat results/all_iterations_eval.json | jq '.best_iteration'"

