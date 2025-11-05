#!/bin/bash

# Batch generate TEST baselines for all tasks

set -e

echo "=========================================="
echo "Batch Generate TEST Baselines"
echo "=========================================="
echo ""

# Set environment variables
export ALGO_TUNE_DATA_DIR="/data/zq/evolve/AlgoTune/data"
export DACE_cache_dir="/data/zq/evolve/.dace_cache"
mkdir -p "$DACE_cache_dir"

cd /data/zq/evolve

echo "This will:"
echo "  1. Process all tasks from reports/generation.json"
echo "  2. For each task: 10 problems × (1 warmup + 10 runs)"
echo "  3. Skip tasks that already have baselines"
echo "  4. Timeout: 10 minutes per task"
echo "  5. Save progress incrementally"
echo ""
echo "This may take several hours for all tasks..."
echo ""

# Create logs directory
mkdir -p logs

# Run batch generation
python scripts/batch_generate_test_baselines.py \
  --data-dir AlgoTune/data \
  --output reports/test_baseline.json \
  --generation-file reports/generation.json \
  --num-runs 10 \
  --timeout 600 \
  --skip-existing

echo ""
echo "=========================================="
echo "✓ Batch Generation Complete!"
echo "=========================================="
echo ""
echo "Check results:"
echo "  cat reports/test_baseline.json | jq 'keys'"
echo "  cat logs/batch_test_baseline.log"

