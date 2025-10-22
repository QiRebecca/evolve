#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Run all AlgoTune tasks sequentially with a progress bar and write solvers to:
  /data/zq/evolve/AlgoTune/results/<model_dir>/<task_name>/solver.py

- Discovers tasks under AlgoTuneTasks/
- Imports scripts/run_local_model.py dynamically and calls run_local_model(...)
- Shows a progress bar (tqdm if available; otherwise simple prints)
- Continues on errors; prints a summary at the end
"""

from __future__ import annotations

import argparse
import importlib.util
import sys
import traceback
from pathlib import Path
from typing import List, Tuple, Dict, Any
import time

# Optional progress bar
try:
    from tqdm import tqdm  # type: ignore
except Exception:
    tqdm = None


REPO_ROOT = Path(__file__).resolve().parents[1]  # repo root = .../AlgoTune
SCRIPTS_DIR = REPO_ROOT / "scripts"
TASKS_DIR_DEFAULT = REPO_ROOT / "AlgoTuneTasks"
RESULTS_ROOT_DEFAULT = Path("/data/zq/evolve/AlgoTune/results")


def _import_run_local_model() -> Any:
    """
    Dynamically import scripts/run_local_model.py and return its module object.
    This avoids path/package issues and reuses your robust run_local_model().
    """
    import importlib.util
    import sys
    script_path = SCRIPTS_DIR / "run_local_model.py"
    if not script_path.exists():
        raise FileNotFoundError(f"Cannot find {script_path}")

    spec = importlib.util.spec_from_file_location("run_local_model_module", script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Failed to create import spec for run_local_model.py")

    module = importlib.util.module_from_spec(spec)
    # ★ 关键修复：把模块提前注册到 sys.modules，供 dataclasses/typing 等反射查找
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)  # type: ignore[attr-defined]
    return module



def discover_tasks(tasks_dir: Path) -> List[str]:
    """
    Discover valid task names under tasks_dir. A valid task dir:
      - is a directory
      - its name does not start with '_' or '.'
      - contains <task_name>.py and description.txt
    Skips common non-task dirs like 'base', '__pycache__'.
    """
    task_names: List[str] = []
    for d in sorted(tasks_dir.iterdir()):
        if not d.is_dir():
            continue
        name = d.name
        if name.startswith(("_", ".")):
            continue
        if name in {"base", "__pycache__"}:
            continue
        if (d / f"{name}.py").exists() and (d / "description.txt").exists():
            task_names.append(name)
    return task_names


def safe_model_dir(model_name: str) -> str:
    """
    Convert model name to a safe directory name, e.g.:
      'openai/chatgptoss-20b' -> 'chatgptoss-20b'
      'my-provider/my-model'  -> 'my-model'
    """
    return model_name.split("/")[-1]


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run all AlgoTune tasks and write solver.py with a progress bar."
    )
    parser.add_argument(
        "--tasks-dir",
        type=str,
        default=str(TASKS_DIR_DEFAULT),
        help=f"Directory containing tasks (default: {TASKS_DIR_DEFAULT})",
    )
    parser.add_argument(
        "--results-root",
        type=str,
        default=str(RESULTS_ROOT_DEFAULT),
        help=f"Root directory to write results (default: {RESULTS_ROOT_DEFAULT})",
    )
    parser.add_argument(
        "--model-name",
        required=True,
        help="Model identifier; for LiteLLM+OpenAI-compatible gateway use 'openai/<id>' "
             "(e.g., 'openai/chatgptoss-20b') to avoid provider detection errors.",
    )
    parser.add_argument("--api-base", required=True, help="OpenAI-compatible API base URL")
    parser.add_argument("--api-key", required=True, help="API key (can be 'dummy' for local gateways)")
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--max-tokens", type=int, default=2048)
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Skip tasks that already have results/<model_dir>/<task>/solver.py",
    )
    args = parser.parse_args()

    tasks_dir = Path(args.tasks_dir).resolve()
    results_root = Path(args.results_root).resolve()
    model_dir = safe_model_dir(args.model_name)

    # Import run_local_model from your existing script
    rlm_module = _import_run_local_model()
    run_local_model = getattr(rlm_module, "run_local_model", None)
    if run_local_model is None:
        raise RuntimeError("run_local_model() not found in scripts/run_local_model.py")

    # Discover tasks
    if not tasks_dir.exists():
        raise FileNotFoundError(f"Tasks directory not found: {tasks_dir}")
    tasks = discover_tasks(tasks_dir)
    if not tasks:
        print(f"No tasks found under {tasks_dir}")
        sys.exit(1)

    # Prepare output dirs
    overall_out_dir = results_root / model_dir
    overall_out_dir.mkdir(parents=True, exist_ok=True)

    # Summary containers
    successes: List[Tuple[str, Path, float]] = []
    failures: List[Tuple[str, str]] = []

    printable_total = len(tasks)
    print(f"Discovered {printable_total} tasks under {tasks_dir}")
    print(f"Results root: {overall_out_dir}")

    # Progress bar setup
    iterator = tasks
    if tqdm is not None:
        pbar = tqdm(total=len(tasks), desc=f"Running tasks -> {model_dir}", unit="task")
    else:
        pbar = None

    try:
        for task_name in iterator:
            out_dir = overall_out_dir / task_name
            out_dir.mkdir(parents=True, exist_ok=True)
            out_path = out_dir / "solver.py"

            if args.resume and out_path.exists():
                msg = f"[SKIP] {task_name} (already exists: {out_path})"
                if pbar:
                    pbar.write(msg)
                    pbar.update(1)
                else:
                    print(msg)
                continue

            t0 = time.time()
            try:
                # Call your robust function directly
                final_path: Path = run_local_model(
                    model_name=args.model_name,
                    api_base=args.api_base,
                    api_key=args.api_key,
                    task_name=task_name,
                    temperature=args.temperature,
                    max_tokens=args.max_tokens,
                    save_path=out_path,
                )
                dt = time.time() - t0
                successes.append((task_name, final_path, dt))
                msg = f"[OK] {task_name} -> {final_path} ({dt:.1f}s)"
                if pbar:
                    pbar.write(msg)
                    pbar.update(1)
                else:
                    print(msg)
            except Exception as exc:
                dt = time.time() - t0
                failures.append((task_name, f"{type(exc).__name__}: {exc}"))
                msg = f"[FAIL] {task_name} ({dt:.1f}s) -> {type(exc).__name__}: {exc}"
                if pbar:
                    pbar.write(msg)
                    pbar.update(1)
                else:
                    print(msg)
                    traceback.print_exc()

    finally:
        if pbar:
            pbar.close()

    # Summary
    print("\n=== SUMMARY ===")
    print(f"Total: {len(tasks)} | Success: {len(successes)} | Fail: {len(failures)}\n")
    if successes:
        print("Succeeded:")
        for name, path, dt in successes:
            print(f"  - {name:>24s}  ->  {str(path)}  ({dt:.1f}s)")
    if failures:
        print("\nFailed:")
        for name, reason in failures:
            print(f"  - {name:>24s}  ->  {reason}")

    # Exit code
    sys.exit(0 if len(failures) == 0 else 2)


if __name__ == "__main__":
    main()
