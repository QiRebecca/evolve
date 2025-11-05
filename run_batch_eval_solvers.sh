#!/bin/bash
# Batch evaluation script for all solvers

set -e  # Exit on error

# Activate conda environment
source $(conda info --base)/etc/profile.d/conda.sh
conda activate env

MODEL="chatgptoss-20b"
RESULTS_DIR="AlgoTune/results"
GENERATION_FILE="reports/generation.json"
SUMMARY_FILE="results/eval_summary.json"
NUM_RUNS=10
TIMEOUT=600

echo "=========================================="
echo "🚀 Batch Solver Evaluation"
echo "=========================================="
echo "Model: $MODEL"
echo "Results dir: $RESULTS_DIR"
echo "Summary file: $SUMMARY_FILE"
echo "Timeout: ${TIMEOUT}s per task"
echo "Python: $(which python)"
echo "=========================================="
echo ""

python scripts/batch_eval_solvers.py \
    --model "$MODEL" \
    --results-dir "$RESULTS_DIR" \
    --generation-file "$GENERATION_FILE" \
    --summary-file "$SUMMARY_FILE" \
    --num-runs "$NUM_RUNS" \
    --timeout "$TIMEOUT"

echo ""
echo "=========================================="
echo "✓ Batch Evaluation Complete!"
echo "=========================================="
echo ""
echo "Check results:"
echo "  cat $SUMMARY_FILE | python -m json.tool"
echo "  cat logs/batch_eval_${MODEL}.log"

