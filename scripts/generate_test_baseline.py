#!/usr/bin/env python3
"""
Generate baseline for TEST dataset (same methodology as generation.json for TRAIN).

This creates a baseline on TEST data so we can fairly compare solver performance.
"""

import argparse
import json
import logging
import sys
import statistics
import time
from pathlib import Path
from typing import Dict, Any, List

# Add project root to path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))
sys.path.insert(0, str(project_root / "AlgoTune"))

from AlgoTuneTasks.factory import TaskFactory
from AlgoTuner.utils.discover_and_list_tasks import discover_and_import_tasks

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def generate_test_baseline(
    task_name: str,
    data_dir: Path,
    num_runs: int = 10
) -> Dict[str, Any]:
    """
    Generate baseline for TEST dataset (AlgoTune official method).
    
    Methodology:
    1. For each problem: warmup 1x + run num_runs times, take min
    2. Store per-problem min times
    3. Calculate avg_min_ms = mean([all problems' min values])
    
    No repetitions needed - single run with 10 measurements per problem.
    
    Args:
        task_name: Name of the task
        data_dir: Data directory
        num_runs: Number of runs per problem (default 10)
        
    Returns:
        Dict with baseline statistics
    """
    # Discover and load task
    discover_and_import_tasks()
    task_instance = TaskFactory(task_name, data_dir=str(data_dir))
    task_instance.task_name = task_name
    
    # Load TEST dataset
    logger.info(f"Loading TEST dataset for {task_name}")
    
    import glob
    from AlgoTuner.utils.serialization import dataset_decoder
    import os
    
    # Find test JSONL file
    test_files = glob.glob(str(data_dir / "**" / f"{task_name}*_test.jsonl"), recursive=True)
    if not test_files:
        test_files = glob.glob(str(data_dir / f"{task_name}" / f"*_test.jsonl"))
    
    if not test_files:
        raise FileNotFoundError(f"No test JSONL file found for {task_name} in {data_dir}")
    
    test_file = test_files[0]
    logger.info(f"Loading test data from: {test_file}")
    
    # Get base directory for resolving bin/npy references
    test_base_dir = os.path.dirname(test_file)
    
    test_dataset = []
    with open(test_file, 'r') as f:
        for line in f:
            if line.strip():
                raw_data = json.loads(line)
                decoded_data = dataset_decoder(raw_data, base_dir=test_base_dir)
                if 'problem' in decoded_data:
                    test_dataset.append(decoded_data['problem'])
                else:
                    test_dataset.append(decoded_data)
    
    logger.info(f"Loaded {len(test_dataset)} test problems")
    
    # Run baseline evaluation once
    logger.info(f"\n{'='*60}")
    logger.info(f"Running baseline evaluation")
    logger.info(f"{'='*60}")
    
    problem_min_times = []
    
    for idx, problem in enumerate(test_dataset):
        problem_id = f'problem_{idx+1}'
        logger.info(f"Evaluating problem {idx+1}/{len(test_dataset)}")
        
        times_ns = []
        
        # Warmup run (not timed)
        _ = task_instance.solve(problem)
        
        # Run num_runs timed measurements
        for run_idx in range(num_runs):
            t0 = time.perf_counter_ns()
            result = task_instance.solve(problem)
            elapsed_ns = time.perf_counter_ns() - t0
            times_ns.append(elapsed_ns)
        
        # Take minimum
        min_ns = min(times_ns)
        min_time_ms = min_ns / 1e6
        problem_min_times.append(min_time_ms)
        
        logger.info(f"  Problem {problem_id}: min={min_time_ms:.4f}ms")
    
    # Calculate statistics
    avg_min_ms = statistics.mean(problem_min_times)
    std_min_ms = statistics.stdev(problem_min_times) if len(problem_min_times) > 1 else 0.0
    
    logger.info(f"\n{'='*60}")
    logger.info("FINAL TEST BASELINE")
    logger.info(f"{'='*60}")
    logger.info(f"  Number of problems: {len(test_dataset)}")
    logger.info(f"  Runs per problem: {num_runs}")
    logger.info(f"  Avg min time: {avg_min_ms:.4f}ms")
    logger.info(f"  Std dev: {std_min_ms:.4f}ms")
    logger.info(f"{'='*60}")
    
    return {
        'task_name': task_name,
        'dataset': 'test',
        'dataset_size': len(test_dataset),
        'num_runs': num_runs,
        'problem_min_times': problem_min_times,
        'avg_min_ms': avg_min_ms,
        'std_min_ms': std_min_ms
    }


def main():
    parser = argparse.ArgumentParser(
        description='Generate baseline for TEST dataset'
    )
    parser.add_argument(
        '--task',
        default='aes_gcm_encryption',
        help='Task name'
    )
    parser.add_argument(
        '--data-dir',
        type=Path,
        default=Path('AlgoTune/data'),
        help='Data directory'
    )
    parser.add_argument(
        '--num-runs',
        type=int,
        default=10,
        help='Number of runs per problem (default: 10)'
    )
    parser.add_argument(
        '--output',
        type=Path,
        default=Path('reports/test_baseline.json'),
        help='Output JSON file'
    )
    
    args = parser.parse_args()
    
    logger.info("="*70)
    logger.info("Generate TEST Baseline (AlgoTune Official Method)")
    logger.info("="*70)
    logger.info(f"Task: {args.task}")
    logger.info(f"Data dir: {args.data_dir}")
    logger.info(f"Runs per problem: {args.num_runs}")
    logger.info("")
    
    # Generate baseline
    baseline_data = generate_test_baseline(
        task_name=args.task,
        data_dir=args.data_dir,
        num_runs=args.num_runs
    )
    
    # Save to file
    args.output.parent.mkdir(parents=True, exist_ok=True)
    
    # Load existing file if exists
    if args.output.exists():
        with open(args.output, 'r') as f:
            all_data = json.load(f)
    else:
        all_data = {}
    
    # Add this task's baseline
    all_data[args.task] = baseline_data
    
    with open(args.output, 'w') as f:
        json.dump(all_data, f, indent=2)
    
    logger.info(f"\n✓ TEST baseline saved to: {args.output}")
    logger.info(f"  Avg min time: {baseline_data['avg_min_ms']:.4f}ms")
    logger.info(f"  Problems: {baseline_data['dataset_size']}")
    
    return 0


if __name__ == '__main__':
    sys.exit(main())




