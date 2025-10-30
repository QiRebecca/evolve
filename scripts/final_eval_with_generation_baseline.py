#!/usr/bin/env python3
"""
Final evaluation script using generation.json baseline (Paper-Aligned Methodology).

Usage:
    python scripts/final_eval_with_generation_baseline.py \
        --task aes_gcm_encryption \
        --solver results/aes_gcm_encryption/best/best_program.py

This script:
1. Reads baseline runtime from generation.json (average of 3 runs)
2. Evaluates solver on TEST dataset with 10 runs per problem  
3. Calculates speedup = sum(baselines) / sum(solvers) (paper method)

Works with any task and any solver.
"""

import argparse
import json
import logging
import sys
import os
import statistics
from pathlib import Path
from typing import Dict, Any, List

# Add project root and AlgoTune to path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))
sys.path.insert(0, str(project_root / "AlgoTune"))

from AlgoTuneTasks.factory import TaskFactory
from AlgoTuner.utils.discover_and_list_tasks import discover_and_import_tasks


def load_baseline_from_generation(generation_file: Path, task_name: str) -> float:
    """
    Load baseline runtime from generation.json.
    
    Takes the average of the 3 baseline runs' avg_min_ms values.
    
    Args:
        generation_file: Path to generation.json
        task_name: Name of the task
        
    Returns:
        Average baseline runtime in milliseconds
    """
    with open(generation_file, 'r') as f:
        data = json.load(f)
    
    if task_name not in data:
        raise ValueError(f"Task '{task_name}' not found in {generation_file}")
    
    task_data = data[task_name]
    baseline_runs = task_data.get('baseline_runs', {})
    
    if not baseline_runs:
        raise ValueError(f"No baseline_runs found for task '{task_name}'")
    
    # Collect avg_min_ms from all successful runs
    avg_times = []
    for run_id, run_info in baseline_runs.items():
        if run_info.get('success') and run_info.get('avg_min_ms') is not None:
            avg_times.append(run_info['avg_min_ms'])
    
    if not avg_times:
        raise ValueError(f"No successful baseline runs found for task '{task_name}'")
    
    # Calculate average
    baseline_avg = sum(avg_times) / len(avg_times)
    
    logging.info(f"Loaded baseline from generation.json:")
    for i, time in enumerate(avg_times):
        logging.info(f"  Run {i}: {time:.4f}ms")
    logging.info(f"  Average: {baseline_avg:.4f}ms (used as fixed baseline)")
    
    return baseline_avg


def evaluate_solver_on_test(
    solver_path: str,
    task_name: str,
    data_dir: Path,
    num_runs: int = 10
) -> Dict[str, Any]:
    """
    Evaluate solver on TEST dataset with specified number of runs.
    
    Args:
        solver_path: Path to solver.py
        task_name: Name of the task
        data_dir: Data directory
        num_runs: Number of runs per problem (default 10 for test)
        
    Returns:
        Dictionary with solver times for each problem
    """
    # Discover and load task
    discover_and_import_tasks()
    
    # TaskFactory is a function that returns task instance directly
    task_instance = TaskFactory(task_name, data_dir=str(data_dir))
    task_instance.task_name = task_name
    
    # Load TEST dataset
    logging.info(f"Loading TEST dataset for {task_name}")
    train_iter, test_iter = task_instance.load_dataset(train_size=10, test_size=10)
    test_dataset = list(test_iter)
    
    logging.info(f"Loaded {len(test_dataset)} test problems")
    
    # Load solver
    import importlib.util
    spec = importlib.util.spec_from_file_location("solver_module", solver_path)
    solver_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(solver_module)
    
    solver_instance = solver_module.Solver()
    
    # Evaluate each problem with num_runs
    import time
    import statistics
    
    solver_results = []
    
    for idx, problem_data in enumerate(test_dataset):
        problem = problem_data.get('problem', problem_data)
        problem_id = problem_data.get('id', f'problem_{idx+1}')
        
        logging.info(f"Evaluating problem {idx+1}/{len(test_dataset)} (ID: {problem_id})")
        
        times_ns = []
        
        # Run num_runs times (each with warmup + timed)
        for run_idx in range(num_runs):
            # Warmup run (not timed)
            _ = solver_instance.solve(problem)
            
            # Timed run
            t0 = time.perf_counter_ns()
            result = solver_instance.solve(problem)
            elapsed_ns = time.perf_counter_ns() - t0
            
            times_ns.append(elapsed_ns)
        
        # Calculate statistics
        min_ns = min(times_ns)
        mean_ns = statistics.mean(times_ns)
        min_time_ms = min_ns / 1e6
        mean_time_ms = mean_ns / 1e6
        
        # Verify correctness
        is_valid = task_instance.is_solution(problem, result)
        
        solver_results.append({
            'problem_id': problem_id,
            'min_time_ms': min_time_ms,
            'mean_time_ms': mean_time_ms,
            'times_ms': [t / 1e6 for t in times_ns],
            'is_valid': is_valid,
            'num_runs': num_runs
        })
        
        logging.info(
            f"  Problem {problem_id}: min={min_time_ms:.2f}ms, "
            f"mean={mean_time_ms:.2f}ms, valid={is_valid}"
        )
    
    return {
        'results': solver_results,
        'num_problems': len(test_dataset)
    }


def calculate_final_metrics(
    baseline_ms: float,
    solver_results: List[Dict[str, Any]]
) -> Dict[str, Any]:
    """
    Calculate final metrics using paper methodology.
    
    Args:
        baseline_ms: Fixed baseline runtime for the task
        solver_results: List of solver evaluation results
        
    Returns:
        Dictionary with metrics
    """
    num_problems = len(solver_results)
    num_valid = sum(1 for r in solver_results if r['is_valid'])
    
    # Extract solver min times
    solver_min_times = [r['min_time_ms'] for r in solver_results]
    
    # Calculate total runtime speedup (paper method)
    # Speedup = sum(baseline_times) / sum(solver_times)
    total_baseline_ms = baseline_ms * num_problems
    total_solver_ms = sum(solver_min_times)
    
    total_runtime_speedup = total_baseline_ms / total_solver_ms if total_solver_ms > 0 else 0.0
    
    # Also calculate per-problem speedups for reference
    per_problem_speedups = [baseline_ms / s for s in solver_min_times]
    mean_speedup = statistics.mean(per_problem_speedups)
    median_speedup = statistics.median(per_problem_speedups)
    
    # Calculate average times
    avg_solver_time = statistics.mean(solver_min_times)
    
    metrics = {
        'baseline_runtime_ms': baseline_ms,
        'total_baseline_ms': total_baseline_ms,
        'total_solver_ms': total_solver_ms,
        'total_runtime_speedup': total_runtime_speedup,  # Paper method ⭐
        'mean_speedup': mean_speedup,  # For reference
        'median_speedup': median_speedup,  # For reference
        'avg_solver_time_ms': avg_solver_time,
        'num_problems': num_problems,
        'num_valid': num_valid,
        'accuracy': num_valid / num_problems if num_problems > 0 else 0.0,
        'improvement_pct': (total_runtime_speedup - 1.0) * 100
    }
    
    return metrics


def main():
    parser = argparse.ArgumentParser(
        description='Final evaluation using generation.json baseline'
    )
    parser.add_argument('--task', required=True, help='Task name')
    parser.add_argument('--solver', required=True, help='Path to solver.py')
    parser.add_argument(
        '--generation-file',
        default='reports/generation.json',
        help='Path to generation.json'
    )
    parser.add_argument(
        '--data-dir',
        default='AlgoTune/data',
        help='Data directory'
    )
    parser.add_argument(
        '--num-runs',
        type=int,
        default=10,
        help='Number of runs per problem (default: 10 for test)'
    )
    parser.add_argument(
        '--output',
        help='Optional output file for results JSON'
    )
    
    args = parser.parse_args()
    
    # Setup logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
    
    # Convert paths
    generation_file = Path(args.generation_file)
    data_dir = Path(args.data_dir)
    
    logging.info("="*60)
    logging.info("Final Evaluation (Paper-Aligned Methodology)")
    logging.info("="*60)
    logging.info(f"Task: {args.task}")
    logging.info(f"Solver: {args.solver}")
    logging.info(f"Generation file: {generation_file}")
    logging.info(f"Runs per problem: {args.num_runs}")
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
    
    # Print results
    print("\n" + "="*60)
    print("  FINAL EVALUATION RESULTS (Paper Methodology)")
    print("="*60)
    print(f"\nTask: {args.task}")
    print(f"Solver: {args.solver}")
    print(f"Dataset: TEST (10 problems)")
    print(f"Runs per problem: {args.num_runs}")
    print(f"\n--- Baseline ---")
    print(f"  Fixed Baseline Runtime: {metrics['baseline_runtime_ms']:.4f}ms")
    print(f"    (avg of 3 runs from generation.json)")
    print(f"\n--- Solver Performance ---")
    print(f"  Total Baseline Runtime: {metrics['total_baseline_ms']:.2f}ms")
    print(f"  Total Solver Runtime: {metrics['total_solver_ms']:.2f}ms")
    print(f"  Avg Solver Time: {metrics['avg_solver_time_ms']:.2f}ms")
    print(f"\n--- Speedup (Paper Method) ---")
    print(f"  Total Runtime Speedup: {metrics['total_runtime_speedup']:.4f}x ⭐")
    print(f"  Improvement: {metrics['improvement_pct']:+.2f}%")
    print(f"\n--- Reference Metrics ---")
    print(f"  Mean Speedup: {metrics['mean_speedup']:.4f}x")
    print(f"  Median Speedup: {metrics['median_speedup']:.4f}x")
    print(f"\n--- Correctness ---")
    print(f"  Accuracy: {metrics['accuracy']:.1%}")
    print(f"  Valid: {metrics['num_valid']}/{metrics['num_problems']}")
    print("\n" + "="*60)
    
    # Save to file if requested
    if args.output:
        output_data = {
            'task': args.task,
            'solver': args.solver,
            'dataset': 'test',
            'num_runs_per_problem': args.num_runs,
            'metrics': metrics,
            'individual_results': eval_results['results']
        }
        
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(output_path, 'w') as f:
            json.dump(output_data, f, indent=2)
        
        print(f"\nResults saved to: {args.output}")
    
    return 0


if __name__ == '__main__':
    sys.exit(main())

