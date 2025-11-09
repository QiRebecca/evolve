#!/bin/bash
# Batch evaluation script for all solvers
# This script runs in background and can continue after logout
# Usage: nohup bash run_batch_eval_solvers.sh > logs/batch_eval_stdout.log 2>&1 &

# Don't exit on error - continue with next task
set +e

# Activate conda environment
source $(conda info --base)/etc/profile.d/conda.sh
conda activate env

MODEL="chatgptoss-20b"
RESULTS_DIR="AlgoTune/results"
GENERATION_FILE="reports/generation.json"
SUMMARY_FILE="results/eval_gptoss20b.json"  # Updated to match expected output path
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

EXIT_CODE=$?

echo ""
echo "=========================================="
if [ $EXIT_CODE -eq 0 ]; then
    echo "✓ Batch Evaluation Complete!"
else
    echo "⚠ Batch Evaluation Finished (some tasks may have failed)"
fi
echo "=========================================="
echo ""
echo "Check results:"
echo "  cat $SUMMARY_FILE | python -m json.tool"
echo "  cat logs/batch_eval_${MODEL}.log"
echo ""
echo "To check progress while running:"
echo "  tail -f logs/batch_eval_${MODEL}.log"
echo "  tail -f logs/batch_eval_stdout.log"

