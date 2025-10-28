"""Helpers for injecting AlgoTune task assets into OpenEvolve prompts."""

from __future__ import annotations

import ast
import logging
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Mapping, Optional

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class TaskPromptAssets:
    """Container holding pre-rendered task snippets for prompt injection."""

    task_name: str
    task_dir: Path
    replacements: Dict[str, str]


def _read_text(path: Path) -> str:
    if not path.exists():
        raise FileNotFoundError(f"File not found: {path}")
    return path.read_text(encoding="utf-8")


def _get_source_segment(src: str, node: ast.AST) -> str:
    try:
        segment = ast.get_source_segment(src, node)
        if segment:
            return segment
    except Exception:
        pass

    lines = src.splitlines(True)
    start = max(getattr(node, "lineno", 1) - 1, 0)
    end = getattr(node, "end_lineno", start + 1)
    return "".join(lines[start:end])


def _extract_function_source(src: str, func_name: str) -> Optional[str]:
    try:
        tree = ast.parse(src)
    except SyntaxError:
        tree = None

    if tree:
        for node in tree.body:
            if isinstance(node, ast.FunctionDef) and node.name == func_name:
                return _get_source_segment(src, node).strip()
        for node in tree.body:
            if isinstance(node, ast.ClassDef):
                for child in node.body:
                    if isinstance(child, ast.FunctionDef) and child.name == func_name:
                        return _get_source_segment(src, child).strip()

    fallback = re.search(
        rf"(?:^|\n)[^\S\n]*def\s+{func_name}\s*\(.*?\):\s*(?:\n(?:[ \t].*|\n)*)",
        src,
        re.DOTALL,
    )
    return fallback.group(0).strip() if fallback else None


def load_task_prompt_assets(
    task_name: str,
    task_dir: Path,
    *,
    module_filename: Optional[str] = None,
    description_filename: str = "description.txt",
) -> TaskPromptAssets:
    """Load description/baseline snippets required by the prompt."""

    if not task_dir.exists():
        raise FileNotFoundError(f"Task directory not found: {task_dir}")

    description_path = task_dir / description_filename
    description_text = _read_text(description_path).strip()

    if module_filename:
        module_path = task_dir / module_filename
    else:
        module_path = task_dir / f"{task_name}.py"

    if not module_path.exists() and not module_filename:
        candidates = [p for p in task_dir.glob("*.py") if p.name != "__init__.py"]
        if len(candidates) == 1:
            module_path = candidates[0]

    module_source = _read_text(module_path)

    solve_src = _extract_function_source(module_source, "solve")
    is_solution_src = _extract_function_source(module_source, "is_solution")

    if not solve_src or not is_solution_src:
        raise RuntimeError(
            f"Failed to extract solve/is_solution from {module_path}"
        )

    replacements: Dict[str, str] = {}
    replacements[f"<task/{description_filename}>"] = description_text
    if description_filename != "description.txt":
        replacements["<task/description.txt>"] = description_text
    else:
        # Ensure both explicit and canonical tokens resolve
        replacements.setdefault("<task/description.txt>", description_text)

    replacements["<task.solve>"] = solve_src.strip()
    replacements["<task.is_solution>"] = is_solution_src.strip()

    return TaskPromptAssets(task_name=task_name, task_dir=task_dir, replacements=replacements)


def apply_task_placeholders(text: str, replacements: Mapping[str, str]) -> str:
    """Replace known task placeholders in *text* using *replacements*."""

    result = text
    for placeholder, payload in replacements.items():
        if placeholder not in result:
            continue

        snippet = payload.strip("\n")
        if snippet:
            formatted = f"\n{snippet}\n"
        else:
            formatted = ""
        result = result.replace(placeholder, formatted)
    return result
