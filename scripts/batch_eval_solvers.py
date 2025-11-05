#!/usr/bin/env python3
"""
Batch Evaluation Script for All Solvers

This script evaluates all solvers for a given model across all tasks.
Features:
- Automatic task discovery
- Progress tracking with ETA
- Resume capability (skip already evaluated tasks)
- Timeout protection per task
- Detailed logging
- Incremental summary updates

Usage:
    python scripts/batch_eval_solvers.py \
        --model chatgptoss-20b \
        --results-dir AlgoTune/results \
        --generation-file reports/generation.json \
        --summary-file reports/agent_summary.json \
        --timeout 600 \
        --skip-existing
"""

import argparse
import json
import logging
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, List, Optional, Set
from datetime import datetime, timedelta


class SolverEvaluator:
    """Batch evaluator for model solvers"""
    
    def __init__(
        self,
        model: str,
        results_dir: Path,
        generation_file: Path,
        summary_file: Path,
        num_runs: int = 10,
        timeout: int = 600,
        skip_existing: bool = True,
        log_file: Optional[Path] = None
    ):
        self.model = model
        self.results_dir = Path(results_dir)
        self.generation_file = Path(generation_file)
        self.summary_file = Path(summary_file)
        self.num_runs = num_runs
        self.timeout = timeout
        self.skip_existing = skip_existing
        
        # Setup logging
        self.log_file = log_file or Path(f"logs/batch_eval_{model}.log")
        self.log_file.parent.mkdir(parents=True, exist_ok=True)
        self._setup_logging()
        
        # Statistics
        self.stats = {
            'completed': [],
            'skipped': [],
            'failed': [],
            'timeout': [],
            'no_solver': []
        }
        
        self.start_time = None
        
    def _setup_logging(self):
        """Configure logging to both file and console"""
        # Clear existing handlers
        logger = logging.getLogger()
        logger.handlers = []
        
        # Set level
        logger.setLevel(logging.INFO)
        
        # File handler (detailed)
        file_handler = logging.FileHandler(self.log_file, mode='a', encoding='utf-8')
        file_handler.setLevel(logging.INFO)
        file_formatter = logging.Formatter(
            '%(asctime)s - %(levelname)s - %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        file_handler.setFormatter(file_formatter)
        logger.addHandler(file_handler)
        
        # Console handler (concise)
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setLevel(logging.INFO)
        console_formatter = logging.Formatter('%(message)s')
        console_handler.setFormatter(console_formatter)
        logger.addHandler(console_handler)
    
    def load_tasks(self) -> List[str]:
        """Load all tasks from generation.json"""
        if not self.generation_file.exists():
            raise FileNotFoundError(f"Generation file not found: {self.generation_file}")
        
        with open(self.generation_file, 'r') as f:
            data = json.load(f)
        
        tasks = sorted(data.keys())
        logging.info(f"Loaded {len(tasks)} tasks from {self.generation_file}")
        return tasks
    
    def get_already_evaluated(self) -> Set[str]:
        """Get set of tasks already evaluated in summary file"""
        if not self.summary_file.exists():
            return set()
        
        try:
            with open(self.summary_file, 'r') as f:
                summary = json.load(f)
            
            evaluated = set()
            # eval_summary.json format: {task_name: {model_name: {...}}}
            for task_name, model_data in summary.items():
                if self.model in model_data:
                    evaluated.add(task_name)
            
            if evaluated:
                logging.info(f"Found {len(evaluated)} already evaluated tasks for model '{self.model}'")
            return evaluated
        
        except Exception as e:
            logging.warning(f"Could not load summary file: {e}")
            return set()
    
    def find_solver(self, task: str) -> Optional[Path]:
        """Find solver file for a given task"""
        solver_path = self.results_dir / self.model / task / "solver.py"
        
        if solver_path.exists():
            return solver_path
        
        return None
    
    def evaluate_solver(self, task: str, solver_path: Path) -> Dict[str, any]:
        """Evaluate a single solver using save_eval_to_summary.py"""
        cmd = [
            sys.executable,
            "scripts/save_eval_to_summary.py",
            "--task", task,
            "--model", self.model,
            "--solver", str(solver_path),
            "--generation-file", str(self.generation_file),
            "--summary-file", str(self.summary_file),
            "--num-runs", str(self.num_runs)
        ]
        
        logging.info(f"Running: {' '.join(cmd)}")
        
        try:
            result = subprocess.run(
                cmd,
                timeout=self.timeout,
                capture_output=True,
                text=True,
                cwd=Path.cwd()
            )
            
            if result.returncode == 0:
                # Parse speedup from output
                speedup = None
                for line in result.stdout.split('\n'):
                    if 'Final Speedup:' in line:
                        try:
                            speedup = float(line.split(':')[1].split('x')[0].strip())
                        except:
                            pass
                
                return {
                    'status': 'success',
                    'speedup': speedup,
                    'stdout': result.stdout,
                    'stderr': result.stderr
                }
            else:
                return {
                    'status': 'failed',
                    'error': result.stderr or result.stdout,
                    'returncode': result.returncode
                }
        
        except subprocess.TimeoutExpired:
            return {
                'status': 'timeout',
                'error': f'Evaluation exceeded {self.timeout}s timeout'
            }
        
        except Exception as e:
            return {
                'status': 'error',
                'error': str(e)
            }
    
    def format_duration(self, seconds: float) -> str:
        """Format duration in human-readable format"""
        if seconds < 60:
            return f"{seconds:.1f}s"
        elif seconds < 3600:
            return f"{seconds/60:.1f}m"
        else:
            hours = int(seconds // 3600)
            minutes = int((seconds % 3600) // 60)
            return f"{hours}h {minutes}m"
    
    def print_progress(self, current: int, total: int, task: str, elapsed: float):
        """Print progress bar and ETA"""
        completed_count = len(self.stats['completed'])
        skipped_count = len(self.stats['skipped'])
        
        # Calculate ETA
        if completed_count > 0:
            avg_time = elapsed / completed_count
            remaining = total - current
            eta_seconds = avg_time * remaining
            eta_str = self.format_duration(eta_seconds)
        else:
            eta_str = "calculating..."
        
        print(f"\n{'='*80}")
        print(f"[{current}/{total}] Processing: {task}")
        print(f"{'='*80}")
        print(f"Progress: {current}/{total} ({completed_count} done, {skipped_count} skipped) | "
              f"Elapsed: {self.format_duration(elapsed)} | ETA: {eta_str}")
    
    def run(self, tasks: Optional[List[str]] = None):
        """Run batch evaluation"""
        self.start_time = time.time()
        start_datetime = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        # Load tasks
        if tasks is None:
            all_tasks = self.load_tasks()
        else:
            all_tasks = tasks
        
        # Get already evaluated
        already_evaluated = set()
        if self.skip_existing:
            already_evaluated = self.get_already_evaluated()
        
        # Filter tasks
        tasks_to_process = [t for t in all_tasks if t not in already_evaluated]
        
        if not tasks_to_process:
            logging.info("No tasks to process!")
            return
        
        logging.info("="*80)
        logging.info(f"BATCH EVALUATION START")
        logging.info("="*80)
        logging.info(f"Model: {self.model}")
        logging.info(f"Total tasks: {len(all_tasks)}")
        logging.info(f"Already evaluated: {len(already_evaluated)}")
        logging.info(f"To process: {len(tasks_to_process)}")
        logging.info(f"Timeout per task: {self.timeout}s")
        logging.info(f"Start time: {start_datetime}")
        logging.info("="*80)
        logging.info("")
        
        # Process each task
        for idx, task in enumerate(tasks_to_process, 1):
            elapsed = time.time() - self.start_time
            self.print_progress(idx, len(tasks_to_process), task, elapsed)
            
            # Find solver
            solver_path = self.find_solver(task)
            if not solver_path:
                logging.warning(f"✗ SOLVER NOT FOUND: {task}")
                logging.warning(f"  Expected: {self.results_dir / self.model / task / 'solver.py'}")
                self.stats['no_solver'].append(task)
                print(f"Status: ✗ NO SOLVER")
                continue
            
            logging.info(f"Found solver: {solver_path}")
            
            # Evaluate
            task_start = time.time()
            result = self.evaluate_solver(task, solver_path)
            task_duration = time.time() - task_start
            
            # Handle result
            if result['status'] == 'success':
                logging.info(f"✓ SUCCESS: {task}")
                if result['speedup']:
                    logging.info(f"  Speedup: {result['speedup']:.4f}x")
                logging.info(f"  Duration: {self.format_duration(task_duration)}")
                self.stats['completed'].append(task)
                print(f"Status: ✓ COMPLETED")
                if result['speedup']:
                    print(f"  Speedup: {result['speedup']:.4f}x")
                print(f"  Duration: {self.format_duration(task_duration)}")
            
            elif result['status'] == 'timeout':
                logging.warning(f"⏱ TIMEOUT: {task}")
                logging.warning(f"  {result['error']}")
                self.stats['timeout'].append(task)
                print(f"Status: ⏱ TIMEOUT")
            
            else:
                logging.error(f"✗ FAILED: {task}")
                logging.error(f"  Error: {result.get('error', 'Unknown error')}")
                self.stats['failed'].append((task, result.get('error', 'Unknown')))
                print(f"Status: ✗ FAILED")
                print(f"  Error: {result.get('error', 'Unknown')[:100]}")
        
        # Final summary
        self.print_final_summary()
    
    def print_final_summary(self):
        """Print final summary of batch evaluation"""
        total_time = time.time() - self.start_time
        end_datetime = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        print("\n" + "="*80)
        print("BATCH EVALUATION COMPLETE")
        print("="*80)
        print(f"Total time: {self.format_duration(total_time)}")
        print()
        print("Results:")
        print(f"  ✓ Completed: {len(self.stats['completed'])}")
        print(f"  → Skipped:   {len(self.stats['skipped'])}")
        print(f"  ✗ Failed:    {len(self.stats['failed'])}")
        print(f"  ⏱ Timeout:   {len(self.stats['timeout'])}")
        print(f"  ✗ No solver: {len(self.stats['no_solver'])}")
        print()
        print(f"Summary file: {self.summary_file}")
        print(f"Log file: {self.log_file}")
        
        # Show how to view results
        print()
        print("📊 View results:")
        print(f"  # View all evaluated tasks")
        print(f"  cat {self.summary_file} | python -m json.tool | grep -A 10 '{self.model}'")
        print()
        print(f"  # Count tasks")
        print(f"  python -c \"import json; data=json.load(open('{self.summary_file}')); print(f'Tasks: {{len([t for t,m in data.items() if \\\"{self.model}\\\" in m])}}')\"")
        
        # Detailed summary in log
        logging.info("="*80)
        logging.info("FINAL SUMMARY")
        logging.info("="*80)
        
        if self.stats['completed']:
            logging.info(f"Completed: {len(self.stats['completed'])}")
            task_list = ', '.join(self.stats['completed'][:10])
            if len(self.stats['completed']) > 10:
                task_list += f" ... (+{len(self.stats['completed'])-10} more)"
            logging.info(f"  Tasks: {task_list}")
        
        if self.stats['skipped']:
            logging.info(f"Skipped: {len(self.stats['skipped'])}")
            logging.info(f"  Tasks: {', '.join(self.stats['skipped'][:10])}")
        
        if self.stats['no_solver']:
            logging.info(f"No solver: {len(self.stats['no_solver'])}")
            for task in self.stats['no_solver']:
                logging.info(f"  {task}")
        
        if self.stats['failed']:
            logging.info(f"Failed: {len(self.stats['failed'])}")
            for task, error in self.stats['failed']:
                logging.info(f"  {task}: {error[:100]}")
        
        if self.stats['timeout']:
            logging.info(f"Timeout: {len(self.stats['timeout'])}")
            for task in self.stats['timeout']:
                logging.info(f"  {task}")
        
        logging.info(f"End time: {end_datetime}")
        logging.info("="*80)
        
        # Print retry command if needed
        retry_tasks = (
            [t for t, _ in self.stats['failed']] +
            self.stats['timeout']
        )
        
        if retry_tasks:
            print(f"\n⚠️  To retry failed/timeout tasks, run:")
            print(f"python scripts/batch_eval_solvers.py \\")
            print(f"    --model {self.model} \\")
            print(f"    --tasks {' '.join(retry_tasks[:5])}", end='')
            if len(retry_tasks) > 5:
                print(f" ... (+{len(retry_tasks)-5} more)")
            else:
                print()


def main():
    parser = argparse.ArgumentParser(
        description="Batch evaluate all solvers for a model",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument(
        "--model",
        required=True,
        help="Model name (e.g., chatgptoss-20b)"
    )
    
    parser.add_argument(
        "--results-dir",
        type=Path,
        default=Path("AlgoTune/results"),
        help="Results directory containing model solvers (default: AlgoTune/results)"
    )
    
    parser.add_argument(
        "--generation-file",
        type=Path,
        default=Path("reports/generation.json"),
        help="Path to generation.json (default: reports/generation.json)"
    )
    
    parser.add_argument(
        "--summary-file",
        type=Path,
        default=Path("results/eval_summary.json"),
        help="Path to eval_summary.json (default: results/eval_summary.json)"
    )
    
    parser.add_argument(
        "--num-runs",
        type=int,
        default=10,
        help="Number of runs per problem (default: 10)"
    )
    
    parser.add_argument(
        "--timeout",
        type=int,
        default=600,
        help="Timeout per task in seconds (default: 600)"
    )
    
    parser.add_argument(
        "--skip-existing",
        action='store_true',
        default=True,
        help="Skip tasks already in summary file (default: True)"
    )
    
    parser.add_argument(
        "--no-skip-existing",
        action='store_false',
        dest='skip_existing',
        help="Re-evaluate all tasks (don't skip existing)"
    )
    
    parser.add_argument(
        "--tasks",
        nargs='+',
        help="Specific tasks to evaluate (default: all tasks from generation.json)"
    )
    
    parser.add_argument(
        "--log-file",
        type=Path,
        help="Path to log file (default: logs/batch_eval_<model>.log)"
    )
    
    args = parser.parse_args()
    
    # Create evaluator
    evaluator = SolverEvaluator(
        model=args.model,
        results_dir=args.results_dir,
        generation_file=args.generation_file,
        summary_file=args.summary_file,
        num_runs=args.num_runs,
        timeout=args.timeout,
        skip_existing=args.skip_existing,
        log_file=args.log_file
    )
    
    # Run evaluation
    try:
        evaluator.run(tasks=args.tasks)
    except KeyboardInterrupt:
        print("\n\n⚠️  Evaluation interrupted by user")
        evaluator.print_final_summary()
        sys.exit(1)
    except Exception as e:
        logging.error(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()

