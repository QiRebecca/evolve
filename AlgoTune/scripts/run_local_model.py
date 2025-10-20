#!/usr/bin/env python3
"""Utility to call a local OpenAI-compatible model without the AlgoTune agent loop."""

from __future__ import annotations

import argparse
import ast
import os
import re
import textwrap
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import litellm

from AlgoTuner.config.loader import load_config

# ---------------------------------------------------------------------------
# Prompt construction helpers
# ---------------------------------------------------------------------------


def _load_initial_template() -> str:
    template_path = Path("AlgoTuner/messages/initial_system_message.txt")
    if not template_path.exists():
        raise FileNotFoundError(
            "Expected initial system message template at AlgoTuner/messages/initial_system_message.txt"
        )
    return template_path.read_text(encoding="utf-8")


def _load_task_description(task_name: str) -> str:
    description_path = Path("AlgoTuneTasks") / task_name / "description.txt"
    if not description_path.exists():
        raise FileNotFoundError(
            f"Could not find description for task '{task_name}' at {description_path}"
        )
    return description_path.read_text(encoding="utf-8").strip()

# Utility -----------------------------------------------------------------

def _gather_extra_packages() -> str:
    pyproject_path = Path("pyproject.toml")
    if not pyproject_path.exists():
        return " - (None specified or all filtered)\n"

    try:
        import tomllib as toml_lib  # Python 3.11+
    except ImportError:  # pragma: no cover - fallback for older Python
        import toml as toml_lib  # type: ignore

    try:
        with pyproject_path.open("rb") as fp:
            project = toml_lib.load(fp)
    except Exception as exc:  # pragma: no cover - just surface message to the user
        return f" - (failed to inspect pyproject.toml: {exc})\n"

    deps = project.get("project", {}).get("dependencies")
    if deps is None:
        deps = project.get("tool", {}).get("poetry", {}).get("dependencies", {})

    if isinstance(deps, dict):
        dep_names = deps.keys()
    elif isinstance(deps, list):
        dep_names = deps
    else:
        return " - (no extra dependencies declared)\n"

    exclude = {
        "python",
        "litellm",
        "google-generativeai",
        "pylint",
        "line_profiler",
        "pytest",
        "orjson",
        "pyyaml",
        "pillow",
    }

    cleaned = []
    for dep in dep_names:
        if not dep:
            continue
        name = (
            dep.split("[")[0]
            .split(" ")[0]
            .split("=")[0]
            .split(">")[0]
            .split("<")[0]
            .strip()
            .strip("\"")
            .strip("'")
        )
        if name and name not in exclude:
            cleaned.append(name)

    if not cleaned:
        return " - (no additional packages beyond the Python standard library)\n"

    cleaned = sorted(set(cleaned))
    return "".join(f" - {pkg}\n" for pkg in cleaned)


def _inject_package_list(initial_content: str, package_list: str) -> str:
    pattern = re.compile(
        r"(?P<prefix>^.*?additional packages:\s*\r?\n)(?:^[ \t]*-[^\r\n]*\r?\n?)+",
        re.IGNORECASE | re.MULTILINE,
    )

    def _replace(match: re.Match[str]) -> str:
        return match.group("prefix") + package_list

    return pattern.sub(_replace, initial_content, count=1)


def _read_task_module(task_name: str) -> str:
    module_path = Path("AlgoTuneTasks") / task_name / f"{task_name}.py"
    if not module_path.exists():
        raise FileNotFoundError(
            f"Could not find task module for '{task_name}' at {module_path}"
        )
    return module_path.read_text(encoding="utf-8")


def _find_task_class(tree: ast.AST) -> Optional[ast.ClassDef]:
    for node in tree.body:  # type: ignore[attr-defined]
        if isinstance(node, ast.ClassDef):
            for base in node.bases:
                if isinstance(base, ast.Name) and base.id == "Task":
                    return node
                if isinstance(base, ast.Attribute) and base.attr == "Task":
                    return node
    return None


def _collect_import_lines(source: str) -> list[str]:
    imports: list[str] = []
    for line in source.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("import ") or stripped.startswith("from "):
            if "logging" in stripped:
                continue
            if "AlgoTuneTasks.base" in stripped or "tasks.base" in stripped.lower():
                continue
            imports.append(stripped)
    return imports


def _collect_called_names(node: ast.AST) -> set[str]:
    names: set[str] = set()

    class _Visitor(ast.NodeVisitor):
        def visit_Call(self, call: ast.Call) -> None:  # noqa: N802
            func = call.func
            if isinstance(func, ast.Name):
                names.add(func.id)
            elif isinstance(func, ast.Attribute):
                names.add(func.attr)
            self.generic_visit(call)

    _Visitor().visit(node)
    return names


@dataclass
class _HelperInfo:
    name: str
    lineno: int
    code: str


def _dedent_and_strip(segment: str) -> str:
    return textwrap.dedent(segment).strip()


def _collect_helper_sources(
    root_node: ast.FunctionDef,
    source_text: str,
    class_methods: dict[str, ast.FunctionDef],
    module_functions: dict[str, ast.FunctionDef],
    exclude: Optional[set[str]] = None,
) -> list[_HelperInfo]:
    exclude = exclude or set()
    queue = list(_collect_called_names(root_node))
    seen: set[str] = set()
    results: dict[str, _HelperInfo] = {}

    while queue:
        name = queue.pop()
        if name in seen or name in exclude:
            continue
        seen.add(name)

        if name in class_methods:
            node = class_methods[name]
            segment = ast.get_source_segment(source_text, node)
            if segment is None:
                continue
            code = _dedent_and_strip(segment)
            results[name] = _HelperInfo(name=name, lineno=node.lineno, code=code)
            queue.extend(_collect_called_names(node))
        elif name in module_functions:
            node = module_functions[name]
            segment = ast.get_source_segment(source_text, node)
            if segment is None:
                continue
            code = _dedent_and_strip(segment)
            results[name] = _HelperInfo(name=name, lineno=node.lineno, code=code)
            queue.extend(_collect_called_names(node))

    return [info for _, info in sorted(results.items(), key=lambda item: item[1].lineno)]


def _format_numbered_code(code: str) -> str:
    lines = code.splitlines()
    if not lines:
        return ""
    width = len(str(len(lines)))
    return "\n".join(f"| {str(i).zfill(width)}: {line}" for i, line in enumerate(lines, 1))


def _build_reference_sections(task_name: str) -> tuple[str, str]:
    source_text = _read_task_module(task_name)
    tree = ast.parse(source_text)
    task_class = _find_task_class(tree)
    if task_class is None:
        raise RuntimeError(
            f"Could not locate Task subclass in AlgoTuneTasks/{task_name}/{task_name}.py"
        )

    class_methods: dict[str, ast.FunctionDef] = {}
    for item in task_class.body:
        if isinstance(item, ast.FunctionDef):
            class_methods[item.name] = item

    module_functions: dict[str, ast.FunctionDef] = {}
    for node in tree.body:  # type: ignore[attr-defined]
        if isinstance(node, ast.FunctionDef):
            module_functions[node.name] = node

    solve_node = class_methods.get("solve")
    validation_node = class_methods.get("is_solution")
    if solve_node is None or validation_node is None:
        raise RuntimeError(
            f"Task '{task_name}' must define both solve and is_solution methods."
        )

    solve_helpers = _collect_helper_sources(
        solve_node,
        source_text,
        class_methods,
        module_functions,
        exclude={"solve", "is_solution"},
    )

    validation_helpers = _collect_helper_sources(
        validation_node,
        source_text,
        class_methods,
        module_functions,
        exclude={"solve", "is_solution"} | {info.name for info in solve_helpers},
    )

    solve_segments = [info.code for info in solve_helpers]
    solve_segments.append(_dedent_and_strip(ast.get_source_segment(source_text, solve_node) or ""))
    solve_code = "\n\n".join(segment for segment in solve_segments if segment)

    validation_segments = [info.code for info in validation_helpers]
    validation_segments.append(
        _dedent_and_strip(ast.get_source_segment(source_text, validation_node) or "")
    )
    validation_code = "\n\n".join(segment for segment in validation_segments if segment)

    imports = _collect_import_lines(source_text)
    imports_str = "\n".join(imports).strip()

    if imports_str:
        solve_section = f"{imports_str}\n\n{_format_numbered_code(solve_code)}"
        validation_section = f"{imports_str}\n\n{_format_numbered_code(validation_code)}"
    else:
        solve_section = _format_numbered_code(solve_code)
        validation_section = _format_numbered_code(validation_code)

    return solve_section, validation_section


def _strip_agent_workflow_instructions(system_prompt: str) -> str:
    start_marker = "Your messages should include a short thought"
    end_marker = "**GOALS:**"
    cleaned = system_prompt

    cleaned = re.sub(
        r"You are to use the commands defined below to accomplish this task\.\s*",
        "",
        cleaned,
    )

    start_idx = cleaned.find(start_marker)
    end_idx = cleaned.find(end_marker)
    if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
        cleaned = cleaned[:start_idx].rstrip() + "\n\n" + cleaned[end_idx:]

    addition = textwrap.dedent(
        """
        **RESPONSE FORMAT (Single Turn):**
        Reply with a single message that contains only the complete contents of `solver.py`, wrapped in a ```python fenced code block.
        Do not include natural-language explanations, multiple messages, or command strings.
        """
    ).strip()

    insertion_point = cleaned.find("**GOALS:**")
    if insertion_point != -1:
        cleaned = (
            cleaned[:insertion_point].rstrip()
            + "\n\n"
            + addition
            + "\n\n"
            + cleaned[insertion_point:]
        )
    else:
        cleaned = cleaned.rstrip() + "\n\n" + addition

    return cleaned.strip()


def _build_system_prompt(task_name: str) -> str:
    initial_template = _load_initial_template()
    package_list = _gather_extra_packages()
    initial_with_packages = _inject_package_list(initial_template, package_list)

    description = _load_task_description(task_name)
    solve_section, validation_section = _build_reference_sections(task_name)

    combined_content = (
        initial_with_packages
        + "\n"
        + description
        + "\n\nBelow is the reference implementation. Your function should run much quicker.\n\n"
        + solve_section
        + "\n\nThis function will be used to check if your solution is valid for a given problem. If it returns False, it means the solution is invalid:\n\n"
        + validation_section
    )

    return _strip_agent_workflow_instructions(combined_content)


def _build_single_prompt(task_name: str) -> tuple[str, str]:
    system_prompt = _build_system_prompt(task_name)
    user_prompt = (
        "请直接根据系统消息输出最终的 solver.py 实现，且仅返回包含完整代码的 ```python fenced block。"
    )
    return system_prompt, user_prompt


def _extract_code(response_text: str) -> Optional[str]:
    pattern = re.compile(r"```(?:python)?\n(.*?)```", re.DOTALL)
    match = pattern.search(response_text)
    if match:
        return match.group(1).strip() + "\n"
    # Fallback: if no fenced code, return full text
    stripped = response_text.strip()
    return stripped + ("\n" if not stripped.endswith("\n") else "") if stripped else None


# Main ---------------------------------------------------------------------

def run_local_model(
    model_name: str,
    api_base: Optional[str],
    api_key: Optional[str],
    task_name: str,
    temperature: float,
    max_tokens: int,
    save_path: Path,
) -> Path:
    system_prompt, user_prompt = _build_single_prompt(task_name)

    completion_params = {
        "model": model_name,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        "temperature": temperature,
        "max_tokens": max_tokens,
    }

    if api_base:
        completion_params["api_base"] = api_base
    if api_key:
        completion_params["api_key"] = api_key

    response = litellm.completion(**completion_params)
    try:
        message = response["choices"][0]["message"]["content"]
    except (KeyError, IndexError) as exc:
        raise RuntimeError(f"Unexpected response structure from model: {response}") from exc

    code = _extract_code(message)
    if not code:
        raise RuntimeError("Model response did not contain any code block.")

    save_path.parent.mkdir(parents=True, exist_ok=True)
    save_path.write_text(code)
    return save_path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run a local OpenAI-compatible model on an AlgoTune task without the agent loop",
    )
    parser.add_argument("task", help="Registered AlgoTune task name (e.g. 'svm')")
    parser.add_argument("output", help="Destination path for the generated solver.py")
    parser.add_argument(
        "--model-name",
        required=False,
        help="Model identifier to send to the OpenAI-compatible endpoint. Defaults to the config entry for the task.",
    )
    parser.add_argument("--api-base", dest="api_base", help="Base URL of the OpenAI-compatible endpoint", default=None)
    parser.add_argument(
        "--api-key",
        dest="api_key",
        help="API key for the OpenAI-compatible endpoint. Overrides environment/config values.",
        default=None,
    )
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--max-tokens", type=int, default=4096)
    args = parser.parse_args()

    config = load_config()
    models_config = config.get("models", {})

    model_name = args.model_name
    api_key = args.api_key
    api_base = args.api_base

    if not model_name:
        raise SystemExit("--model-name is required when bypassing the AlgoTune agent.")

    model_entry = models_config.get(model_name, {}) if isinstance(models_config, dict) else {}

    if api_key is None:
        # Try to honour config entry if it exists
        env_name = model_entry.get("api_key_env") if isinstance(model_entry, dict) else None
        if env_name:
            api_key = os.environ.get(env_name)

    if api_base is None and isinstance(model_entry, dict):
        api_base = model_entry.get("api_base") or model_entry.get("base_url")

    if api_key is None:
        raise SystemExit("No API key provided via --api-key or environment variable.")

    output_path = Path(args.output)
    final_path = run_local_model(
        model_name=model_name,
        api_base=api_base,
        api_key=api_key,
        task_name=args.task,
        temperature=args.temperature,
        max_tokens=args.max_tokens,
        save_path=output_path,
    )

    print(f"Solver written to {final_path}")


if __name__ == "__main__":
    main()
