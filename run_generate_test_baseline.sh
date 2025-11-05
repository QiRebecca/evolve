#!/bin/bash

# Generate baseline for TEST dataset (same methodology as TRAIN)

set -e

echo "=========================================="
echo "Generate TEST Baseline"
echo "=========================================="
echo ""

# Set environment variables
export ALGO_TUNE_TASK="aes_gcm_encryption"
export ALGO_TUNE_DATA_DIR="/data/zq/evolve/AlgoTune/data"
export DACE_cache_dir="/data/zq/evolve/.dace_cache"
mkdir -p "$DACE_cache_dir"

cd /data/zq/evolve

echo "This will:"
echo "  1. Load TEST dataset (10 problems)"
echo "  2. Run baseline solver on each problem (1 warmup + 10 timed runs)"
echo "  3. Take min of 10 runs for each problem"
echo "  4. Store per-problem baseline times"
echo ""
echo "This will take about 2-3 minutes..."
echo ""

python scripts/generate_test_baseline.py \
  --task aes_gcm_encryption \
  --data-dir AlgoTune/data \
  --num-runs 10 \
  --output reports/test_baseline.json

echo ""
echo "=========================================="
echo "✓ TEST Baseline Generated!"
echo "=========================================="
echo ""
echo "Next step: Run batch evaluation with TEST baseline"
echo "  ./run_batch_eval.sh"




