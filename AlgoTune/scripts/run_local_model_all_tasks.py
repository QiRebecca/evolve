#!/usr/bin/env python3
"""Run ``run_local_model`` for multiple AlgoTune tasks with progress and logging."""

from __future__ import annotations

import argparse
import logging
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Iterable, Sequence

from tqdm import tqdm

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from AlgoTuner.config.loader import load_config  # noqa: E402
from scripts.run_local_model import run_local_model  # noqa: E402


def _discover_tasks(task_root: Path) -> list[str]:
    tasks: list[str] = []
    for child in sorted(task_root.iterdir()):
        if not child.is_dir():
            continue
        name = child.name
        if name.startswith("__"):
            continue
        if not (child / f"{name}.py").exists():
            continue
        if not (child / "description.txt").exists():
            continue
        tasks.append(name)
    return tasks


def _prepare_logger(log_path: Path, task_name: str) -> logging.Logger:
    logger = logging.getLogger(f"run_local_model_all.{task_name}")
    logger.handlers.clear()
    logger.setLevel(logging.INFO)

    log_path.parent.mkdir(parents=True, exist_ok=True)

    file_handler = logging.FileHandler(log_path, encoding="utf-8")
    formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)

    return logger


def _ensure_api_credentials(model_name: str, api_key: str | None, api_base: str | None) -> tuple[str, str | None]:
    config = load_config()
    models_config = config.get("models", {})
    model_entry = models_config.get(model_name, {}) if isinstance(models_config, dict) else {}

    if api_key is None and isinstance(model_entry, dict):
        env_name = model_entry.get("api_key_env")
        if env_name:
            api_key = os.environ.get(env_name)

    if api_base is None and isinstance(model_entry, dict):
        api_base = model_entry.get("api_base") or model_entry.get("base_url")

    if api_key is None:
        raise SystemExit("No API key provided via --api-key, environment variable, or config.")

    return api_key, api_base


def _normalise_tasks(task_root: Path, requested: Sequence[str] | None) -> list[str]:
    if requested:
        tasks = []
        for task in requested:
            task_path = task_root / task
            if not task_path.exists():
                raise SystemExit(f"Task '{task}' not found under {task_root}.")
            tasks.append(task)
        return sorted(set(tasks))
    return _discover_tasks(task_root)


def _run_tasks(
    tasks: Iterable[str],
    *,
    model_name: str,
    api_base: str | None,
    api_key: str,
    temperature: float,
    max_tokens: int,
    output_root: Path,
    log_root: Path,
    overwrite: bool,
) -> tuple[list[str], list[str], list[str]]:
    successes: list[str] = []
    failures: list[str] = []
    skipped: list[str] = []

    log_root.mkdir(parents=True, exist_ok=True)

    progress = tqdm(tasks, desc="AlgoTune tasks", unit="task")

    for task_name in progress:
        output_dir = output_root / task_name
        solver_path = output_dir / "solver.py"
        task_log_dir = log_root / task_name
        log_path = task_log_dir / "run.log"
        logger = _prepare_logger(log_path, task_name)

        logger.info("Starting generation for task '%s'", task_name)
        logger.info(
            "Parameters: model=%s api_base=%s temperature=%s max_tokens=%s overwrite=%s",
            model_name,
            api_base,
            temperature,
            max_tokens,
            overwrite,
        )

        if solver_path.exists() and not overwrite:
            message = f"Skipping '{task_name}' because {solver_path} already exists"
            logger.info(message)
            tqdm.write(f"[SKIP] {message}")
            skipped.append(task_name)
        else:
            try:
                final_path = run_local_model(
                    model_name=model_name,
                    api_base=api_base,
                    api_key=api_key,
                    task_name=task_name,
                    temperature=temperature,
                    max_tokens=max_tokens,
                    save_path=solver_path,
                )
            except Exception as exc:  # noqa: BLE001 - need to log arbitrary failures
                logger.exception("Task '%s' failed", task_name)
                tqdm.write(f"[FAIL] {task_name}: {exc}")
                failures.append(task_name)
            else:
                logger.info("Solver written to %s", final_path)
                tqdm.write(f"[OK] {task_name} -> {final_path}")
                successes.append(task_name)

        for handler in list(logger.handlers):
            handler.close()
            logger.removeHandler(handler)

    progress.close()
    return successes, failures, skipped


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Batch runner for scripts/run_local_model.py across multiple AlgoTune tasks.",
    )
    parser.add_argument(
        "--model-name",
        required=True,
        help="Model identifier for the OpenAI-compatible endpoint (e.g. 'openai/chatgptoss-20b').",
    )
    parser.add_argument("--api-base", dest="api_base", default=None, help="Base URL of the OpenAI-compatible endpoint.")
    parser.add_argument("--api-key", dest="api_key", default=None, help="API key for the OpenAI-compatible endpoint.")
    parser.add_argument("--temperature", type=float, default=0.0, help="Sampling temperature for each request.")
    parser.add_argument("--max-tokens", type=int, default=4096, help="Maximum tokens to request from the model.")
    parser.add_argument(
        "--output-root",
        type=Path,
        default=Path("results/chatgptoss-20b"),
        help="Directory where per-task solver.py files will be stored.",
    )
    parser.add_argument(
        "--log-base",
        type=Path,
        default=None,
        help=(
            "Optional base directory for logs."
            " A timestamped subdirectory will be created inside this path."
        ),
    )
    parser.add_argument(
        "--tasks",
        nargs="*",
        help="Optional subset of task names to run. Defaults to all tasks discovered in AlgoTuneTasks/.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Regenerate solver.py even if it already exists in the output directory.",
    )

    args = parser.parse_args()

    api_key, api_base = _ensure_api_credentials(args.model_name, args.api_key, args.api_base)

    task_root = ROOT_DIR / "AlgoTuneTasks"
    tasks = _normalise_tasks(task_root, args.tasks)
    if not tasks:
        raise SystemExit("No tasks found to run.")

    output_root = args.output_root
    if not output_root.is_absolute():
        output_root = ROOT_DIR / output_root

    output_root.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    if args.log_base is None:
        log_base = ROOT_DIR / "logs" / "run_local_model"
    else:
        log_base = args.log_base
        if not log_base.is_absolute():
            log_base = ROOT_DIR / log_base

    log_root = log_base / timestamp
    log_root.mkdir(parents=True, exist_ok=True)
    tqdm.write(f"Logs for this run will be stored in {log_root}")

    successes, failures, skipped = _run_tasks(
        tasks,
        model_name=args.model_name,
        api_base=api_base,
        api_key=api_key,
        temperature=args.temperature,
        max_tokens=args.max_tokens,
        output_root=output_root,
        log_root=log_root,
        overwrite=args.overwrite,
    )

    total = len(tasks)
    summary_lines = [
        "Batch run summary:",
        f"  Total tasks: {total}",
        f"  Successful: {len(successes)}",
        f"  Failed: {len(failures)}",
        f"  Skipped: {len(skipped)}",
        f"  Logs: {log_root}",
    ]

    if failures:
        summary_lines.append("  Failed tasks: " + ", ".join(sorted(failures)))

    tqdm.write("\n".join(summary_lines))

    summary_path = log_root / "summary.log"
    summary_path.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
