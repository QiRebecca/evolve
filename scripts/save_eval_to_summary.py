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
1. Loads per-problem baselines from test_baseline.json (TEST dataset, required)
2. Evaluates solver on TEST dataset with 10 runs per problem
3. Calculates speedup = mean([baseline_i / solver_i]) (AlgoTune official method)
4. Saves/updates results in summary JSON format
5. Supports multiple models per task

Prerequisites:
1. Generate TEST baseline first: ./run_generate_test_baseline.sh
2. Then run this script
"""

import argparse
import json
import logging
import sys
import os
import time
import statistics
import importlib.util
import glob
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, List

# Add project root to path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))
sys.path.insert(0, str(project_root / "AlgoTune"))

from AlgoTuneTasks.factory import TaskFactory
from AlgoTuner.utils.discover_and_list_tasks import discover_and_import_tasks
from AlgoTuner.utils.serialization import dataset_decoder


def load_per_problem_baselines(generation_file: Path, task_name: str) -> List[float]:
    """
    Load per-problem baseline times from test_baseline.json.
    
    Args:
        generation_file: Path to generation.json (used to locate test_baseline.json)
        task_name: Name of the task
        
    Returns:
        List of baseline times (ms) for each problem
    """
    test_baseline_file = generation_file.parent / 'test_baseline.json'
    
    if not test_baseline_file.exists():
        raise FileNotFoundError(
            f"test_baseline.json not found at {test_baseline_file}\n"
            f"Please run ./run_generate_test_baseline.sh first to generate TEST baseline."
        )
    
    logging.info(f"Loading per-problem baselines from {test_baseline_file}")
    
    with open(test_baseline_file, 'r') as f:
        data = json.load(f)
    
    if task_name not in data:
        raise ValueError(f"Task '{task_name}' not found in {test_baseline_file}")
    
    task_data = data[task_name]
    
    if 'problem_min_times' not in task_data:
        raise ValueError(f"'problem_min_times' not found in test_baseline.json for task '{task_name}'")
    
    per_problem_baselines = task_data['problem_min_times']
    
    logging.info(f"Loaded {len(per_problem_baselines)} per-problem baselines")
    logging.info(f"  First 3 problems: {[f'{b:.2f}ms' for b in per_problem_baselines[:3]]}")
    logging.info(f"  Overall mean: {statistics.mean(per_problem_baselines):.4f}ms")
    
    return per_problem_baselines


def evaluate_solver_on_test(
    solver_path: str,
    task_name: str,
    data_dir: Path,
    num_runs: int = 10
) -> Dict[str, Any]:
    """
    Evaluate solver on TEST dataset using AlgoTune official method (isolated execution).
    
    Uses evaluate_code_on_dataset() which uses isolated execution (subprocess) to match
    AlgoTune official evaluation methodology.
    
    Args:
        solver_path: Path to solver.py
        task_name: Name of the task
        data_dir: Data directory
        num_runs: Number of runs per problem (default 10 for test)
        
    Returns:
        Dictionary with solver times for each problem
    """
    # Set up environment to match AlgoTune official evaluation
    os.environ.setdefault("DATA_DIR", str(data_dir))
    os.environ.setdefault("ALGO_TUNE_DATA_DIR", str(data_dir))
    os.environ.setdefault("CURRENT_TASK_NAME", task_name)
    os.environ.setdefault("SKIP_DATASET_GEN", "1")
    # Note: evaluate_code_on_dataset uses hardcoded use_isolated_execution=True
    
    from AlgoTuneTasks.factory import TaskFactory
    from AlgoTuner.utils.evaluator.main import evaluate_code_on_dataset
    from AlgoTune.evaluate import _load_task_class, _load_solver_callable, _prepare_dataset, _load_per_problem_baselines
    
    discover_and_import_tasks()
    
    logging.info(f"Evaluating solver using AlgoTune official method (isolated execution)")
    logging.info(f"Solver path: {solver_path}")
    logging.info(f"Task: {task_name}")
    logging.info(f"Data dir: {data_dir}")
    logging.info(f"Num runs per problem: {num_runs}")
    
    # Load task class and prepare dataset (same as evaluate.py)
    task_class = _load_task_class(task_name)
    baseline_task = task_class(data_dir=str(data_dir))
    baseline_task.task_name = task_name
    dataset_list = _prepare_dataset(baseline_task, split="test", max_samples=None)
    
    # Create BaselineManager (same as official method)
    # This ensures we use the same baseline generation method
    from AlgoTuner.utils.evaluator.baseline_manager import BaselineManager
    
    baseline_manager = BaselineManager(baseline_task)
    
    # Prepare candidate task with solver
    candidate_task = task_class(data_dir=str(data_dir))
    candidate_task.task_name = task_name
    solver_callable = _load_solver_callable(solver_path, task_class, candidate_task)
    candidate_task.solve = solver_callable  # type: ignore[attr-defined]
    candidate_task.oracle = solver_callable  # type: ignore[attr-defined]
    
    # Call evaluate_code_on_dataset directly to get problem-level results
    # Use same parameters as official method (handlers.py:1779-1785)
    from AlgoTuner.utils.timing_config import EVAL_RUNS
    
    dataset_results = evaluate_code_on_dataset(
        task_obj=candidate_task,
        dataset_iterable=dataset_list,
        baseline_manager=baseline_manager,  # Same as official: pass BaselineManager
        data_subset="test",
        test_mode=False,  # Same as official: False unless max_samples is set
        default_num_eval_runs=EVAL_RUNS,  # Same as official: EVAL_RUNS for test
        # default_num_warmup_runs not passed (use default WARMUPS=1, same as official)
    )
    
    # Extract problem-level results from DatasetResults
    solver_results = []
    
    for prob_result in dataset_results.results:
        solver_time_ms = prob_result.solver_time_ms
        min_time_ms = None
        
        # Extract min_time_ms from timing if available
        if prob_result.execution.timing:
            min_time_ms = prob_result.execution.timing.min_ms
        
        solver_results.append({
            'problem_id': prob_result.problem_id,
            'min_time_ms': min_time_ms,
            'mean_time_ms': prob_result.execution.timing.mean_ms if prob_result.execution.timing else None,
            'times_ms': prob_result.execution.timing.times_ms if prob_result.execution.timing else [],
            'is_valid': prob_result.is_valid,
            'num_runs': num_runs,
            'error': prob_result.execution.error,
            'status': 'success' if prob_result.execution.success else 'failed'
        })
    
    return {
        'results': solver_results,
        'num_problems': len(solver_results),
        'dataset_results': dataset_results  # Keep reference for debugging
    }


def calculate_final_metrics(
    per_problem_baselines: List[float],
    solver_results: List[Dict[str, Any]]
) -> Dict[str, Any]:
    """
    Calculate final metrics using AlgoTune official methodology.
    
    AlgoTune official method:
    1. For each problem: calculate speedup_i = baseline_i / solver_i
    2. final_speedup = mean([speedup_1, speedup_2, ..., speedup_N])
    
    Args:
        per_problem_baselines: List of baseline times for each problem
        solver_results: List of solver evaluation results
        
    Returns:
        Dictionary with metrics
    """
    num_problems = len(solver_results)
    num_valid = sum(1 for r in solver_results if r['is_valid'])
    num_failed = sum(1 for r in solver_results if r['status'] == 'failed')
    num_success = sum(1 for r in solver_results if r['status'] == 'success')
    
    if len(per_problem_baselines) != num_problems:
        raise ValueError(
            f"Mismatch: {len(per_problem_baselines)} baselines but {num_problems} solver results"
        )
    
    # Build detailed problem results
    problem_details = []
    per_problem_speedups = []
    successful_solver_times = []
    
    for i in range(num_problems):
        baseline_i = per_problem_baselines[i]
        result = solver_results[i]
        
        problem_detail = {
            'problem_id': result['problem_id'],
            'baseline_time_ms': baseline_i,
            'solver_time_ms': result['min_time_ms'],
            'is_valid': result['is_valid'],
            'status': result['status'],
            'error': result['error']
        }
        
        # Only calculate speedup for successful runs
        if result['status'] == 'success' and result['min_time_ms'] is not None and result['min_time_ms'] > 0:
            speedup_i = baseline_i / result['min_time_ms']
            problem_detail['speedup'] = speedup_i
            per_problem_speedups.append(speedup_i)
            successful_solver_times.append(result['min_time_ms'])
        else:
            problem_detail['speedup'] = None
        
        problem_details.append(problem_detail)
    
    # Calculate aggregate metrics only from successful problems
    if per_problem_speedups:
        final_speedup = statistics.mean(per_problem_speedups)
        median_speedup = statistics.median(per_problem_speedups)
    else:
        final_speedup = 0.0
        median_speedup = 0.0
    
    baseline_avg_min_ms = statistics.mean(per_problem_baselines)
    
    if successful_solver_times:
        solver_avg_min_ms = statistics.mean(successful_solver_times)
        solver_std_min_ms = statistics.stdev(successful_solver_times) if len(successful_solver_times) > 1 else 0.0
    else:
        solver_avg_min_ms = 0.0
        solver_std_min_ms = 0.0
    
    metrics = {
        'speedup': final_speedup,
        'baseline_avg_min_ms': baseline_avg_min_ms,
        'solver_avg_min_ms': solver_avg_min_ms,
        'solver_std_min_ms': solver_std_min_ms,
        'mean_per_problem_speedup': final_speedup,
        'median_per_problem_speedup': median_speedup,
        'num_problems': num_problems,
        'num_success': num_success,
        'num_failed': num_failed,
        'num_valid': num_valid,
        'accuracy': num_valid / num_problems if num_problems > 0 else 0.0,
        'improvement_pct': (final_speedup - 1.0) * 100,
        'num_errors': num_problems - num_valid,
        'num_timeouts': 0,
        'problem_results': problem_details,
    }
    
    logging.info("=" * 70)
    logging.info("METRICS (AlgoTune Official Methodology):")
    logging.info(f"  Final Speedup:       {final_speedup:.4f}x ⭐")
    logging.info(f"    = mean([baseline_i / solver_i]) for successful problems")
    logging.info(f"  Median Speedup:      {median_speedup:.4f}x")
    logging.info(f"  Baseline avg:        {baseline_avg_min_ms:.4f}ms (reference)")
    logging.info(f"  Solver avg:          {solver_avg_min_ms:.4f}ms (std={solver_std_min_ms:.4f})")
    logging.info(f"  Improvement:         {metrics['improvement_pct']:+.2f}%")
    logging.info(f"  Problems:            {num_problems} total")
    logging.info(f"    ✓ Success:         {num_success}")
    logging.info(f"    ✓ Valid:           {num_valid}")
    logging.info(f"    ✗ Failed:          {num_failed}")
    if num_failed > 0:
        failed_ids = [p['problem_id'] for p in problem_details if p['status'] == 'failed']
        logging.info(f"      Failed IDs:      {', '.join(failed_ids)}")
    logging.info("=" * 70)
    
    return metrics


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
    
    Format (aligned with baseline generation logic):
    {
        "task_name": {
            "model_name": {
                "speedup": "1.0234",  # mean([baseline_i / solver_i]) ⭐ AlgoTune official
                "accuracy": "1.0000",
                "baseline_avg_min_ms": "98.9890",
                "solver_avg_min_ms": "96.5000",
                "solver_std_min_ms": "1.2345",
                "mean_per_problem_speedup": "1.0250",
                "median_per_problem_speedup": "1.0200",
                "num_valid": 10,
                "num_evaluated": 10,
                "improvement_pct": "+2.34",
                "eval_date": "2025-10-31"
            }
        }
    }
    """
    # Initialize task if not exists
    if task_name not in summary_data:
        summary_data[task_name] = {}
    
    # Format the result (convert floats to strings like in agent_summary.json)
    result = {
        "speedup": f"{metrics['speedup']:.4f}",  # Main speedup (mean of per-problem speedups)
        "accuracy": f"{metrics['accuracy']:.4f}",
        "baseline_avg_min_ms": f"{metrics['baseline_avg_min_ms']:.4f}",
        "solver_avg_min_ms": f"{metrics['solver_avg_min_ms']:.4f}",
        "solver_std_min_ms": f"{metrics['solver_std_min_ms']:.4f}",
        "mean_per_problem_speedup": f"{metrics['mean_per_problem_speedup']:.4f}",
        "median_per_problem_speedup": f"{metrics['median_per_problem_speedup']:.4f}",
        "num_valid": metrics['num_valid'],
        "num_evaluated": metrics['num_problems'],
        "num_success": metrics['num_success'],
        "num_failed": metrics['num_failed'],
        "num_errors": metrics.get('num_errors', 0),
        "num_timeouts": metrics.get('num_timeouts', 0),
        "improvement_pct": f"{metrics['improvement_pct']:.2f}",
        "eval_date": datetime.now().strftime("%Y-%m-%d"),
        "eval_timestamp": datetime.now().isoformat(),
        "problem_results": [
            {
                "problem_id": p['problem_id'],
                "baseline_time_ms": f"{p['baseline_time_ms']:.4f}",
                "solver_time_ms": f"{p['solver_time_ms']:.4f}" if p['solver_time_ms'] is not None else None,
                "speedup": f"{p['speedup']:.4f}" if p['speedup'] is not None else None,
                "is_valid": p['is_valid'],
                "status": p['status'],
                "error": p['error']
            }
            for p in metrics['problem_results']
        ]
    }
    
    # Add to summary
    summary_data[task_name][model_name] = result
    
    logging.info(f"Added result for {task_name} / {model_name}")
    logging.info(f"  Speedup: {result['speedup']}x")
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
    
    # Step 1: Load per-problem baselines from test_baseline.json (required)
    logging.info("Step 1: Loading per-problem TEST baselines...")
    per_problem_baselines = load_per_problem_baselines(generation_file, args.task)
    logging.info("")
    
    # Step 2: Evaluate solver on TEST dataset
    logging.info("Step 2: Evaluating solver on TEST dataset...")
    try:
        eval_results = evaluate_solver_on_test(
            solver_path=args.solver,
            task_name=args.task,
            data_dir=data_dir,
            num_runs=args.num_runs
        )
        logging.info("")
        
        # Step 3: Calculate final metrics (AlgoTune official: per-problem speedup)
        logging.info("Step 3: Calculating final metrics (AlgoTune official methodology)...")
        metrics = calculate_final_metrics(per_problem_baselines, eval_results['results'])
        logging.info("")
        
    except Exception as e:
        # Solver loading or execution failed completely
        error_msg = f"{type(e).__name__}: {str(e)}"
        logging.error(f"Solver evaluation failed: {error_msg}")
        
        # Create metrics with all problems marked as failed
        num_problems = len(per_problem_baselines)
        problem_details = []
        
        for i in range(num_problems):
            problem_details.append({
                'problem_id': f'problem_{i+1}',
                'baseline_time_ms': per_problem_baselines[i],
                'solver_time_ms': None,
                'speedup': None,
                'is_valid': False,
                'status': 'failed',
                'error': error_msg
            })
        
        metrics = {
            'speedup': 0.0,
            'baseline_avg_min_ms': statistics.mean(per_problem_baselines),
            'solver_avg_min_ms': 0.0,
            'solver_std_min_ms': 0.0,
            'mean_per_problem_speedup': 0.0,
            'median_per_problem_speedup': 0.0,
            'num_problems': num_problems,
            'num_success': 0,
            'num_failed': num_problems,
            'num_valid': 0,
            'accuracy': 0.0,
            'improvement_pct': -100.0,
            'num_errors': num_problems,
            'num_timeouts': 0,
            'problem_results': problem_details,
        }
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
    print(f"\n📊 Final Speedup: {metrics['speedup']:.4f}x (AlgoTune official: mean of per-problem speedups)")
    print(f"   Baseline avg: {metrics['baseline_avg_min_ms']:.2f}ms (reference)")
    print(f"   Solver avg:   {metrics['solver_avg_min_ms']:.2f}ms")
    print(f"✓ Accuracy: {metrics['accuracy']:.1%}")
    print(f"📁 Summary: {summary_path}\n")
    
    return 0


if __name__ == '__main__':
    sys.exit(main())

