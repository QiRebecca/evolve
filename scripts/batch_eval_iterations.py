#!/usr/bin/env python3
"""
Batch evaluate all iterations from llm_responses on test dataset.
Extracts Solver code from each iteration and evaluates it.
"""

import argparse
import json
import logging
import re
import sys
import tempfile
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Add project root to path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))
sys.path.insert(0, str(project_root / "scripts"))

from final_eval_with_generation_baseline import (
    load_baseline_from_generation,
    evaluate_solver_on_test,
    calculate_final_metrics
)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def extract_solver_from_response(response_file: Path) -> Optional[str]:
    """Extract Solver class code from LLM response file."""
    try:
        content = response_file.read_text()
        
        # Skip empty files
        if not content.strip():
            logger.warning(f"Empty response file: {response_file.name}")
            return None
        
        # Look for code blocks containing Solver class
        # Pattern 1: ```python ... ```
        code_blocks = re.findall(r'```python\n(.*?)```', content, re.DOTALL)
        
        if not code_blocks:
            # Pattern 2: ```\n ... ```
            code_blocks = re.findall(r'```\n(.*?)```', content, re.DOTALL)
        
        # Find the block containing "class Solver"
        for block in code_blocks:
            if 'class Solver' in block:
                return block.strip()
        
        # If no code blocks, try to find Solver class directly in content
        if 'class Solver' in content:
            # Extract from "class Solver" to end of file or next major section
            match = re.search(r'(class Solver.*)', content, re.DOTALL)
            if match:
                return match.group(1).strip()
        
        logger.warning(f"No Solver class found in {response_file.name}")
        return None
        
    except Exception as e:
        logger.error(f"Error extracting from {response_file.name}: {e}")
        return None


def main():
    parser = argparse.ArgumentParser(description="Batch evaluate all iterations")
    parser.add_argument(
        "--task",
        default="aes_gcm_encryption",
        help="Task name"
    )
    parser.add_argument(
        "--responses-dir",
        type=Path,
        default=Path("llm_responses"),
        help="Directory containing iteration response files"
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=Path("AlgoTune/data"),
        help="Data directory"
    )
    parser.add_argument(
        "--generation-file",
        type=Path,
        default=Path("reports/generation.json"),
        help="Generation baseline file"
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("results/all_iterations_eval.json"),
        help="Output JSON file for all results"
    )
    parser.add_argument(
        "--num-runs",
        type=int,
        default=10,
        help="Number of runs per problem (test dataset)"
    )
    
    args = parser.parse_args()
    
    # Load baseline (auto-detect test_baseline.json if exists)
    logger.info(f"Loading baseline from {args.generation_file}")
    baseline_ms = load_baseline_from_generation(args.generation_file, args.task, use_test_baseline=True)
    logger.info(f"Baseline: {baseline_ms:.4f} ms")
    
    # Find all iteration files
    response_files = sorted(args.responses_dir.glob("iteration_*.txt"))
    logger.info(f"Found {len(response_files)} iteration files")
    
    # Extract iteration number and filter for the latest run
    # Group by iteration number and take the latest timestamp
    # File format: iteration_001_20251030_143130_raw.txt
    iterations_by_num: Dict[int, Path] = {}
    for f in response_files:
        match = re.match(r'iteration_(\d+)_.*_raw\.txt', f.name)
        if match:
            iter_num = int(match.group(1))
            # Keep the latest file for each iteration number
            if iter_num not in iterations_by_num:
                iterations_by_num[iter_num] = f
            else:
                # Compare timestamps (later in filename = more recent)
                if f.name > iterations_by_num[iter_num].name:
                    iterations_by_num[iter_num] = f
    
    logger.info(f"Found {len(iterations_by_num)} unique iterations")
    
    # Evaluate each iteration
    all_results = []
    successful_evals = 0
    failed_extractions = 0
    failed_evals = 0
    
    for iter_num in sorted(iterations_by_num.keys()):
        response_file = iterations_by_num[iter_num]
        logger.info(f"\n{'='*60}")
        logger.info(f"Evaluating Iteration {iter_num:03d}: {response_file.name}")
        logger.info(f"{'='*60}")
        
        # Extract Solver code
        solver_code = extract_solver_from_response(response_file)
        if not solver_code:
            logger.warning(f"Skipping iteration {iter_num}: could not extract Solver code")
            failed_extractions += 1
            all_results.append({
                "iteration": iter_num,
                "file": response_file.name,
                "status": "extraction_failed",
                "error": "No Solver class found"
            })
            continue
        
        # Save to temporary file and evaluate
        try:
            with tempfile.NamedTemporaryFile(
                mode='w', suffix='.py', delete=False
            ) as tmp:
                tmp.write(solver_code)
                tmp_path = Path(tmp.name)
            
            # Evaluate on test dataset
            eval_result = evaluate_solver_on_test(
                solver_path=tmp_path,
                task_name=args.task,
                data_dir=args.data_dir,
                num_runs=args.num_runs
            )
            
            # Extract solver results
            problem_results = eval_result['results']
            
            # Calculate metrics
            metrics = calculate_final_metrics(baseline_ms, problem_results)
            
            # Clean up temp file
            tmp_path.unlink()
            
            # Store result
            result = {
                "iteration": iter_num,
                "file": response_file.name,
                "status": "success",
                "metrics": metrics,
                "num_problems": len(problem_results),
                "num_valid": sum(1 for r in problem_results if r.get('is_valid', False))
            }
            all_results.append(result)
            successful_evals += 1
            
            logger.info(f"✓ Iteration {iter_num}: speedup={metrics['speedup']:.4f}x, "
                       f"solver_avg_min={metrics['solver_avg_min_ms']:.2f}ms, "
                       f"valid={result['num_valid']}/{result['num_problems']}")
            
        except Exception as e:
            logger.error(f"✗ Iteration {iter_num} evaluation failed: {e}")
            failed_evals += 1
            all_results.append({
                "iteration": iter_num,
                "file": response_file.name,
                "status": "evaluation_failed",
                "error": str(e)
            })
            
            # Clean up temp file if it exists
            if 'tmp_path' in locals() and tmp_path.exists():
                tmp_path.unlink()
    
    # Summary
    logger.info(f"\n{'='*60}")
    logger.info("EVALUATION SUMMARY")
    logger.info(f"{'='*60}")
    logger.info(f"Total iterations: {len(iterations_by_num)}")
    logger.info(f"Successful evaluations: {successful_evals}")
    logger.info(f"Failed extractions: {failed_extractions}")
    logger.info(f"Failed evaluations: {failed_evals}")
    
    # Find best iteration
    successful_results = [r for r in all_results if r['status'] == 'success']
    if successful_results:
        # Sort by speedup (baseline_avg_min_ms / solver_avg_min_ms)
        best_result = max(
            successful_results,
            key=lambda r: r['metrics']['speedup']
        )
        
        logger.info(f"\n{'='*60}")
        logger.info("BEST ITERATION (aligned with baseline generation)")
        logger.info(f"{'='*60}")
        logger.info(f"Iteration: {best_result['iteration']}")
        logger.info(f"File: {best_result['file']}")
        logger.info(f"Speedup: {best_result['metrics']['speedup']:.4f}x")
        logger.info(f"  Baseline avg_min_ms: {best_result['metrics']['baseline_avg_min_ms']:.4f}ms")
        logger.info(f"  Solver avg_min_ms:   {best_result['metrics']['solver_avg_min_ms']:.4f}ms (std={best_result['metrics']['solver_std_min_ms']:.4f})")
        logger.info(f"Valid Problems: {best_result['num_valid']}/{best_result['num_problems']}")
        logger.info(f"Improvement: {best_result['metrics']['improvement_pct']:+.2f}%")
    
    # Save all results
    output_data = {
        "task": args.task,
        "baseline_ms": baseline_ms,
        "num_runs": args.num_runs,
        "summary": {
            "total_iterations": len(iterations_by_num),
            "successful_evals": successful_evals,
            "failed_extractions": failed_extractions,
            "failed_evaluations": failed_evals
        },
        "results": all_results
    }
    
    if successful_results:
        output_data["best_iteration"] = best_result
    
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, 'w') as f:
        json.dump(output_data, f, indent=2)
    
    logger.info(f"\nResults saved to {args.output}")
    
    # Return best iteration number for further processing
    if successful_results:
        return best_result['iteration']
    return None


if __name__ == "__main__":
    best_iter = main()
    if best_iter is not None:
        sys.exit(0)
    else:
        sys.exit(1)

