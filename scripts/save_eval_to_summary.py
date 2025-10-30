#!/usr/bin/env python3
"""
Save evaluation results to a unified summary JSON file.

Usage:
    python scripts/save_eval_to_summary.py \
        --task aes_gcm_encryption \
        --model "openevolve-o3" \
        --solver results/aes_gcm_encryption/best/best_program.py \
        --summary-file results/eval_summary.json

This script:
1. Runs evaluation using generation.json baseline
2. Saves/updates results in agent_summary.json format
3. Supports multiple models per task
"""

import argparse
import json
import logging
import sys
from pathlib import Path
from datetime import datetime

# Add project root to path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))
sys.path.insert(0, str(project_root / "AlgoTune"))

from scripts.final_eval_with_generation_baseline import (
    load_baseline_from_generation,
    evaluate_solver_on_test,
    calculate_final_metrics
)


def load_summary_json(summary_path: Path) -> dict:
    """Load existing summary JSON or create empty dict."""
    if summary_path.exists():
        with open(summary_path, 'r') as f:
            return json.load(f)
    return {}


def save_summary_json(summary_path: Path, data: dict):
    """Save summary JSON with pretty formatting."""
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    with open(summary_path, 'w') as f:
        json.dump(data, f, indent=4)
    logging.info(f"Summary saved to: {summary_path}")


def add_result_to_summary(
    summary_data: dict,
    task_name: str,
    model_name: str,
    metrics: dict
) -> dict:
    """
    Add evaluation result to summary data.
    
    Format:
    {
        "task_name": {
            "model_name": {
                "final_speedup": "1.0234",
                "accuracy": "1.0000",
                "mean_speedup": "1.0234",
                "median_speedup": "1.0234",
                "num_valid": 10,
                "num_evaluated": 10,
                "total_runtime_speedup": "1.0234",
                "eval_date": "2025-10-30"
            }
        }
    }
    """
    # Initialize task if not exists
    if task_name not in summary_data:
        summary_data[task_name] = {}
    
    # Format the result (convert floats to strings like in agent_summary.json)
    result = {
        "final_speedup": f"{metrics['total_runtime_speedup']:.4f}",
        "accuracy": f"{metrics['accuracy']:.4f}",
        "mean_speedup": f"{metrics['mean_speedup']:.4f}",
        "median_speedup": f"{metrics['median_speedup']:.4f}",
        "num_valid": metrics['num_valid'],
        "num_evaluated": metrics['num_problems'],
        "num_errors": metrics.get('num_errors', 0),
        "num_timeouts": metrics.get('num_timeouts', 0),
        "baseline_runtime_ms": f"{metrics['baseline_runtime_ms']:.4f}",
        "avg_solver_time_ms": f"{metrics['avg_solver_time_ms']:.2f}",
        "total_solver_ms": f"{metrics['total_solver_ms']:.2f}",
        "total_baseline_ms": f"{metrics['total_baseline_ms']:.2f}",
        "improvement_pct": f"{metrics['improvement_pct']:.2f}",
        "eval_date": datetime.now().strftime("%Y-%m-%d"),
        "eval_timestamp": datetime.now().isoformat()
    }
    
    # Add to summary
    summary_data[task_name][model_name] = result
    
    logging.info(f"Added result for {task_name} / {model_name}")
    logging.info(f"  Final Speedup: {result['final_speedup']}x")
    logging.info(f"  Accuracy: {result['accuracy']}")
    
    return summary_data


def main():
    parser = argparse.ArgumentParser(
        description='Evaluate solver and save to summary JSON'
    )
    parser.add_argument(
        '--task',
        required=True,
        help='Task name (e.g., aes_gcm_encryption)'
    )
    parser.add_argument(
        '--model',
        required=True,
        help='Model name (e.g., openevolve-o3, chatgptoss-20b)'
    )
    parser.add_argument(
        '--solver',
        required=True,
        help='Path to solver.py file'
    )
    parser.add_argument(
        '--summary-file',
        default='results/eval_summary.json',
        help='Path to summary JSON file (default: results/eval_summary.json)'
    )
    parser.add_argument(
        '--generation-file',
        default='reports/generation.json',
        help='Path to generation.json (default: reports/generation.json)'
    )
    parser.add_argument(
        '--data-dir',
        default='AlgoTune/data',
        help='Path to data directory (default: AlgoTune/data)'
    )
    parser.add_argument(
        '--num-runs',
        type=int,
        default=10,
        help='Number of runs per problem (default: 10)'
    )
    
    args = parser.parse_args()
    
    # Setup logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(levelname)s - %(message)s'
    )
    
    # Convert paths
    generation_file = Path(args.generation_file)
    data_dir = Path(args.data_dir)
    summary_path = Path(args.summary_file)
    
    logging.info("="*70)
    logging.info("Evaluate Solver and Update Summary")
    logging.info("="*70)
    logging.info(f"Task: {args.task}")
    logging.info(f"Model: {args.model}")
    logging.info(f"Solver: {args.solver}")
    logging.info(f"Summary file: {summary_path}")
    logging.info("")
    
    # Step 1: Load baseline from generation.json
    logging.info("Step 1: Loading baseline from generation.json...")
    baseline_ms = load_baseline_from_generation(generation_file, args.task)
    logging.info("")
    
    # Step 2: Evaluate solver on TEST dataset
    logging.info("Step 2: Evaluating solver on TEST dataset...")
    eval_results = evaluate_solver_on_test(
        solver_path=args.solver,
        task_name=args.task,
        data_dir=data_dir,
        num_runs=args.num_runs
    )
    logging.info("")
    
    # Step 3: Calculate final metrics
    logging.info("Step 3: Calculating final metrics...")
    metrics = calculate_final_metrics(baseline_ms, eval_results['results'])
    logging.info("")
    
    # Step 4: Load existing summary
    logging.info("Step 4: Loading/updating summary JSON...")
    summary_data = load_summary_json(summary_path)
    
    # Step 5: Add new result
    summary_data = add_result_to_summary(
        summary_data,
        args.task,
        args.model,
        metrics
    )
    
    # Step 6: Save updated summary
    save_summary_json(summary_path, summary_data)
    
    logging.info("")
    logging.info("="*70)
    logging.info("✓ Evaluation complete and summary updated!")
    logging.info("="*70)
    print(f"\n📊 Final Speedup: {metrics['total_runtime_speedup']:.4f}x")
    print(f"✓ Accuracy: {metrics['accuracy']:.1%}")
    print(f"📁 Summary: {summary_path}\n")
    
    return 0


if __name__ == '__main__':
    sys.exit(main())

