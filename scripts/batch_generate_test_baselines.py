#!/usr/bin/env python3
"""
Batch generate TEST baselines for all tasks.

Features:
- Progress tracking with real-time updates
- Skip already completed tasks (resume support)
- Timeout handling (skip slow tasks)
- Detailed logging to file
- Summary report at the end

Usage:
    python scripts/batch_generate_test_baselines.py \
        --data-dir AlgoTune/data \
        --output reports/test_baseline.json \
        --timeout 600 \
        --num-runs 10
"""

import argparse
import json
import logging
import sys
import signal
import traceback
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, List, Optional

# Add project root to path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))
sys.path.insert(0, str(project_root / "AlgoTune"))

from scripts.generate_test_baseline import generate_test_baseline


class TimeoutException(Exception):
    """Raised when a task times out."""
    pass


def timeout_handler(signum, frame):
    """Signal handler for timeout."""
    raise TimeoutException("Task execution timed out")


def load_existing_baselines(output_file: Path) -> Dict[str, Any]:
    """Load existing test_baseline.json if it exists."""
    if output_file.exists():
        try:
            with open(output_file, 'r') as f:
                return json.load(f)
        except (json.JSONDecodeError, FileNotFoundError):
            logging.warning(f"Could not load existing baseline file {output_file}, starting fresh")
            return {}
    return {}


def save_baseline(output_file: Path, all_data: Dict[str, Any]):
    """Save baseline data to JSON file."""
    output_file.parent.mkdir(parents=True, exist_ok=True)
    with open(output_file, 'w') as f:
        json.dump(all_data, f, indent=2)


def get_all_tasks_from_generation(generation_file: Path) -> List[str]:
    """Get list of all tasks from generation.json."""
    if not generation_file.exists():
        raise FileNotFoundError(f"Generation file not found: {generation_file}")
    
    with open(generation_file, 'r') as f:
        data = json.load(f)
    
    # Extract task names (top-level keys)
    tasks = sorted(data.keys())
    logging.info(f"Found {len(tasks)} tasks in {generation_file}")
    
    return tasks


def format_time(seconds: float) -> str:
    """Format seconds as human-readable time."""
    if seconds < 60:
        return f"{seconds:.1f}s"
    elif seconds < 3600:
        mins = int(seconds / 60)
        secs = seconds % 60
        return f"{mins}m {secs:.0f}s"
    else:
        hours = int(seconds / 3600)
        mins = int((seconds % 3600) / 60)
        return f"{hours}h {mins}m"


def main():
    parser = argparse.ArgumentParser(
        description='Batch generate TEST baselines for all tasks'
    )
    parser.add_argument(
        '--data-dir',
        type=Path,
        default=Path('AlgoTune/data'),
        help='Data directory (default: AlgoTune/data)'
    )
    parser.add_argument(
        '--output',
        type=Path,
        default=Path('reports/test_baseline.json'),
        help='Output JSON file (default: reports/test_baseline.json)'
    )
    parser.add_argument(
        '--generation-file',
        type=Path,
        default=Path('reports/generation.json'),
        help='Path to generation.json to get task list (default: reports/generation.json)'
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
        '--timeout',
        type=int,
        default=600,
        help='Timeout per task in seconds (default: 600 = 10 minutes)'
    )
    parser.add_argument(
        '--skip-existing',
        action='store_true',
        default=True,
        help='Skip tasks that already have baselines (default: True)'
    )
    parser.add_argument(
        '--tasks',
        nargs='+',
        help='Optional: specific tasks to run (default: all tasks from generation.json)'
    )
    parser.add_argument(
        '--log-file',
        type=Path,
        default=Path('logs/batch_test_baseline.log'),
        help='Log file path (default: logs/batch_test_baseline.log)'
    )
    
    args = parser.parse_args()
    
    # Setup logging to both file and console
    args.log_file.parent.mkdir(parents=True, exist_ok=True)
    
    # File handler
    file_handler = logging.FileHandler(args.log_file, mode='a')
    file_handler.setLevel(logging.INFO)
    file_handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
    
    # Console handler
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)
    console_handler.setFormatter(logging.Formatter('%(levelname)s - %(message)s'))
    
    # Root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.INFO)
    root_logger.addHandler(file_handler)
    root_logger.addHandler(console_handler)
    
    logging.info("="*80)
    logging.info(f"BATCH GENERATE {args.dataset_type.upper()} BASELINES")
    logging.info("="*80)
    logging.info(f"Start time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    logging.info(f"Data directory: {args.data_dir}")
    logging.info(f"Dataset type: {args.dataset_type}")
    logging.info(f"Output file: {args.output}")
    logging.info(f"Log file: {args.log_file}")
    logging.info(f"Timeout per task: {args.timeout}s")
    logging.info(f"Runs per problem: {args.num_runs}")
    logging.info("")
    
    # Get task list
    if args.tasks:
        tasks = args.tasks
        logging.info(f"Using specified tasks: {len(tasks)} tasks")
    else:
        tasks = get_all_tasks_from_generation(args.generation_file)
        logging.info(f"Loaded {len(tasks)} tasks from {args.generation_file}")
    
    # Load existing baselines
    all_data = load_existing_baselines(args.output)
    existing_count = len(all_data)
    logging.info(f"Found {existing_count} existing baselines")
    
    # Track results
    results = {
        'completed': [],
        'skipped': [],
        'failed': [],
        'timeout': []
    }
    
    start_time = datetime.now()
    
    # Process each task
    for idx, task_name in enumerate(tasks):
        task_num = idx + 1
        total_tasks = len(tasks)
        
        print(f"\n{'='*80}")
        print(f"[{task_num}/{total_tasks}] Processing: {task_name}")
        print(f"{'='*80}")
        
        # Check if already exists
        if args.skip_existing and task_name in all_data:
            logging.info(f"✓ Skipping {task_name} (already has baseline)")
            results['skipped'].append(task_name)
            
            # Show progress
            elapsed = (datetime.now() - start_time).total_seconds()
            avg_time = elapsed / task_num if task_num > 0 else 0
            remaining = avg_time * (total_tasks - task_num)
            print(f"Status: SKIPPED (already exists)")
            print(f"Progress: {task_num}/{total_tasks} | Elapsed: {format_time(elapsed)} | ETA: {format_time(remaining)}")
            continue
        
        # Run with timeout
        task_start = datetime.now()
        
        try:
            # Set up signal for timeout
            signal.signal(signal.SIGALRM, timeout_handler)
            signal.alarm(args.timeout)
            
            try:
                logging.info(f"Starting baseline generation for {task_name}...")
                
                baseline_data = generate_test_baseline(
                    task_name=task_name,
                    data_dir=args.data_dir,
                    num_runs=args.num_runs,
                    dataset_type=args.dataset_type
                )
                
                # Cancel alarm
                signal.alarm(0)
                
                # Save immediately
                all_data[task_name] = baseline_data
                save_baseline(args.output, all_data)
                
                task_duration = (datetime.now() - task_start).total_seconds()
                
                logging.info(f"✓ SUCCESS: {task_name}")
                logging.info(f"  Avg min time: {baseline_data['avg_min_ms']:.4f}ms")
                logging.info(f"  Duration: {format_time(task_duration)}")
                
                results['completed'].append(task_name)
                
                print(f"Status: ✓ COMPLETED")
                print(f"  Baseline: {baseline_data['avg_min_ms']:.2f}ms")
                print(f"  Duration: {format_time(task_duration)}")
                
            except TimeoutException:
                signal.alarm(0)
                logging.warning(f"✗ TIMEOUT: {task_name} exceeded {args.timeout}s")
                results['timeout'].append(task_name)
                
                print(f"Status: ✗ TIMEOUT (exceeded {args.timeout}s)")
                
            except Exception as e:
                signal.alarm(0)
                error_msg = str(e)
                logging.error(f"✗ FAILED: {task_name}")
                logging.error(f"  Error: {error_msg}")
                logging.debug(traceback.format_exc())
                
                results['failed'].append({
                    'task': task_name,
                    'error': error_msg
                })
                
                print(f"Status: ✗ FAILED")
                print(f"  Error: {error_msg[:100]}")
        
        finally:
            # Always cancel alarm
            signal.alarm(0)
        
        # Show overall progress
        elapsed = (datetime.now() - start_time).total_seconds()
        completed_count = len(results['completed']) + len(results['skipped'])
        avg_time = elapsed / task_num if task_num > 0 else 0
        remaining = avg_time * (total_tasks - task_num)
        
        print(f"Progress: {task_num}/{total_tasks} ({completed_count} done) | "
              f"Elapsed: {format_time(elapsed)} | ETA: {format_time(remaining)}")
    
    # Final summary
    total_elapsed = (datetime.now() - start_time).total_seconds()
    
    print(f"\n{'='*80}")
    print("BATCH GENERATION COMPLETE")
    print(f"{'='*80}")
    print(f"Total time: {format_time(total_elapsed)}")
    print(f"\nResults:")
    print(f"  ✓ Completed: {len(results['completed'])}")
    print(f"  → Skipped:   {len(results['skipped'])}")
    print(f"  ✗ Failed:    {len(results['failed'])}")
    print(f"  ⏱ Timeout:   {len(results['timeout'])}")
    print(f"\nTotal tasks in baseline file: {len(all_data)}")
    print(f"Output saved to: {args.output}")
    print(f"Log saved to: {args.log_file}")
    
    # Log details
    logging.info("="*80)
    logging.info("FINAL SUMMARY")
    logging.info("="*80)
    logging.info(f"Completed: {len(results['completed'])}")
    if results['completed']:
        logging.info(f"  Tasks: {', '.join(results['completed'][:10])}" + 
                    (f" ... (+{len(results['completed'])-10} more)" if len(results['completed']) > 10 else ""))
    
    logging.info(f"Skipped: {len(results['skipped'])}")
    if results['skipped']:
        logging.info(f"  Tasks: {', '.join(results['skipped'][:10])}" + 
                    (f" ... (+{len(results['skipped'])-10} more)" if len(results['skipped']) > 10 else ""))
    
    logging.info(f"Failed: {len(results['failed'])}")
    if results['failed']:
        for fail in results['failed'][:5]:
            logging.info(f"  {fail['task']}: {fail['error'][:80]}")
        if len(results['failed']) > 5:
            logging.info(f"  ... (+{len(results['failed'])-5} more)")
    
    logging.info(f"Timeout: {len(results['timeout'])}")
    if results['timeout']:
        logging.info(f"  Tasks: {', '.join(results['timeout'])}")
    
    logging.info(f"Total baselines: {len(all_data)}")
    logging.info(f"End time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    logging.info("="*80)
    
    # Print retry command for failed/timeout tasks
    failed_and_timeout = [f['task'] for f in results['failed']] + results['timeout']
    if failed_and_timeout:
        print(f"\n⚠️  To retry failed/timeout tasks, run:")
        print(f"python scripts/batch_generate_test_baselines.py \\")
        print(f"    --tasks {' '.join(failed_and_timeout[:5])}" + 
              (" \\" if len(failed_and_timeout) > 5 else ""))
        if len(failed_and_timeout) > 5:
            print(f"    ... (+{len(failed_and_timeout)-5} more tasks)")
    
    return 0


if __name__ == '__main__':
    sys.exit(main())

