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
    num_runs: int = 10,
    dataset_type: str = 'test'
) -> Dict[str, Any]:
    """
    Generate baseline for TEST or TRAIN dataset using AlgoTune official method (isolated execution).
    
    Uses BaselineManager which uses isolated execution (subprocess) to match AlgoTune official
    baseline generation methodology.
    
    Methodology:
    1. For each problem: warmup 1x + run num_runs times, take min (in isolated subprocess)
    2. Store per-problem min times
    3. Calculate avg_min_ms = mean([all problems' min values])
    
    Args:
        task_name: Name of the task
        data_dir: Data directory
        num_runs: Number of runs per problem (default 10)
        dataset_type: 'test' or 'train' (default 'test')
        
    Returns:
        Dict with baseline statistics
    """
    import os
    
    # Set up environment to match AlgoTune official evaluation
    os.environ.setdefault("DATA_DIR", str(data_dir))
    os.environ.setdefault("ALGO_TUNE_DATA_DIR", str(data_dir))
    os.environ.setdefault("CURRENT_TASK_NAME", task_name)
    os.environ.setdefault("ISOLATED_EVAL", "1")  # Use isolated execution to match official method
    
    # Discover and load task
    discover_and_import_tasks()
    task_instance = TaskFactory(task_name, data_dir=str(data_dir))
    task_instance.task_name = task_name
    
    logger.info(f"Generating {dataset_type.upper()} baseline using AlgoTune official method (isolated execution)")
    logger.info(f"Task: {task_name}")
    logger.info(f"Data dir: {data_dir}")
    logger.info(f"Dataset type: {dataset_type}")
    logger.info(f"Runs per problem: {num_runs}")
    
    # Use BaselineManager which uses isolated execution when ISOLATED_EVAL=1
    from AlgoTuner.utils.evaluator.baseline_manager import BaselineManager
    
    baseline_manager = BaselineManager(task_instance)
    
    # Get baseline times using BaselineManager (uses isolated execution)
    baseline_times = baseline_manager.get_baseline_times(
        subset=dataset_type,
        force_regenerate=True,
        test_mode=False,  # Use all problems, not limited to 10
        max_samples=None
    )
    
    logger.info(f"Generated baseline times for {len(baseline_times)} problems")
    
    # Convert to list format (maintaining order)
    # BaselineManager returns dict with problem IDs as keys
    # We need to convert to list maintaining the order
    import glob
    from AlgoTuner.utils.serialization import dataset_decoder
    
    # Load dataset to get problem order
    data_files = glob.glob(str(data_dir / "**" / f"{task_name}*_{dataset_type}.jsonl"), recursive=True)
    if not data_files:
        data_files = glob.glob(str(data_dir / f"{task_name}" / f"*_{dataset_type}.jsonl"))
    
    if not data_files:
        raise FileNotFoundError(f"No {dataset_type} JSONL file found for {task_name} in {data_dir}")
    
    data_file = data_files[0]
    data_base_dir = os.path.dirname(data_file)
    
    dataset = []
    with open(data_file, 'r') as f:
        for line in f:
            if line.strip():
                raw_data = json.loads(line)
                decoded_data = dataset_decoder(raw_data, base_dir=data_base_dir)
                if 'problem' in decoded_data:
                    dataset.append(decoded_data)
                else:
                    dataset.append({'problem': decoded_data})
    
    # Extract problem IDs in order and build problem_min_times list
    problem_min_times = []
    for idx, item in enumerate(dataset):
        # Extract ID same way as BaselineManager
        if isinstance(item, dict):
            problem_id = item.get("id", item.get("seed", item.get("k", None)))
            if problem_id is None:
                problem_id = f"problem_{idx+1}"
            problem_id = str(problem_id)
        else:
            problem_id = f"problem_{idx+1}"
        
        if problem_id in baseline_times:
            problem_min_times.append(baseline_times[problem_id])
        else:
            logger.warning(f"Problem {problem_id} not found in baseline_times, using 0.0")
            problem_min_times.append(0.0)
    
    # Calculate statistics
    avg_min_ms = statistics.mean(problem_min_times)
    std_min_ms = statistics.stdev(problem_min_times) if len(problem_min_times) > 1 else 0.0
    
    logger.info(f"\n{'='*60}")
    logger.info(f"FINAL {dataset_type.upper()} BASELINE (AlgoTune Official Method)")
    logger.info(f"{'='*60}")
    logger.info(f"  Number of problems: {len(problem_min_times)}")
    logger.info(f"  Runs per problem: {num_runs}")
    logger.info(f"  Avg min time: {avg_min_ms:.4f}ms")
    logger.info(f"  Std dev: {std_min_ms:.4f}ms")
    logger.info(f"  Execution method: Isolated (subprocess) ✅")
    logger.info(f"{'='*60}")
    
    return {
        'task_name': task_name,
        'dataset': dataset_type,
        'dataset_size': len(problem_min_times),
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
        '--dataset-type',
        type=str,
        default='test',
        choices=['test', 'train'],
        help='Dataset type: test or train (default: test)'
    )
    parser.add_argument(
        '--output',
        type=Path,
        default=Path('reports/test_baseline.json'),
        help='Output JSON file'
    )
    
    args = parser.parse_args()
    
    logger.info("="*70)
    logger.info(f"Generate {args.dataset_type.upper()} Baseline (AlgoTune Official Method)")
    logger.info("="*70)
    logger.info(f"Task: {args.task}")
    logger.info(f"Data dir: {args.data_dir}")
    logger.info(f"Dataset type: {args.dataset_type}")
    logger.info(f"Runs per problem: {args.num_runs}")
    logger.info("")
    
    # Generate baseline
    baseline_data = generate_test_baseline(
        task_name=args.task,
        data_dir=args.data_dir,
        num_runs=args.num_runs,
        dataset_type=args.dataset_type
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
    
    logger.info(f"\n✓ {args.dataset_type.upper()} baseline saved to: {args.output}")
    logger.info(f"  Avg min time: {baseline_data['avg_min_ms']:.4f}ms")
    logger.info(f"  Problems: {baseline_data['dataset_size']}")
    
    return 0


if __name__ == '__main__':
    sys.exit(main())




