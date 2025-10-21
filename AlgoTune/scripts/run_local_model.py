#!/usr/bin/env python3
"""Utility to call a local OpenAI-compatible model without the AlgoTune agent loop.

- Tries streaming first to avoid finish_reason='length' mapping issues.
- Falls back to non-stream with a robust extractor that can read:
  choices[0].message.content, choices[0].text, or provider raw JSON.
- Builds the same prompts as the original script from project files.
"""

from __future__ import annotations

import argparse
import ast
import json
import os
import re
import textwrap
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, List, Dict, Any

import litellm

# -----------------------------------------------------------------------------
# Optional: allow running outside full AlgoTune env. If import fails, use stub.
# -----------------------------------------------------------------------------
try:
    from AlgoTuner.config.loader import load_config  # type: ignore
except Exception:  # pragma: no cover
    def load_config() -> Dict[str, Any]:
        return {}


# -----------------------------------------------------------------------------
# Prompt construction helpers
# -----------------------------------------------------------------------------

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
    except ImportError:  # pragma: no cover
        import toml as toml_lib  # type: ignore

    try:
        with pyproject_path.open("rb") as fp:
            project = toml_lib.load(fp)
    except Exception as exc:  # pragma: no cover
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

    cleaned: List[str] = []
    for dep in dep_names:
        if not dep:
            continue
        name = (
            str(dep).split("[")[0]
            .split(" ")[0]
            .split("=")[0]
            .split(">")[0]
            .split("<")[0]
            .strip()
            .strip('"')
            .strip("'")
        )
        if name and name.lower() not in exclude:
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
    for node in getattr(tree, "body", []):  # type: ignore[attr-defined]
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
        "Please produce the final solver.py implementation directly from the system message. "
        "Output only a single ```python fenced code block containing the complete file with no extra text. "
        "After the closing triple backticks, append the exact string <END_OF_CODE> on its own line."
    )
    return system_prompt, user_prompt



_CODE_FENCE_RE = re.compile(r"```(?:python)?\n(.*?)```", re.DOTALL)


def _extract_code(response_text: str) -> Optional[str]:
    match = _CODE_FENCE_RE.search(response_text)
    if match:
        return match.group(1).strip() + "\n"
    stripped = response_text.strip()
    return stripped + ("\n" if not stripped.endswith("\n") else "") if stripped else None


# -----------------------------------------------------------------------------
# Robust runner (streaming first, then fallback)
# -----------------------------------------------------------------------------

def run_local_model(
    model_name: str,
    api_base: Optional[str],
    api_key: Optional[str],
    task_name: str,
    temperature: float,
    max_tokens: int,
    save_path: Path,
) -> Path:
    """
    Robust runner:
    1) Build prompts
    2) Try streaming to collect text pieces (works around finish_reason='length' mapping issues)
    3) Fallback to non-stream; extract visible text from multiple possible fields
    4) Extract code block (with a fence-missing fallback) and write to save_path
    """
    # Build prompts
    system_prompt, user_prompt = _build_single_prompt(task_name)

    # Compose base params
    completion_params: Dict[str, Any] = {
        "model": model_name,
        "messages": [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_prompt},
        ],
        "temperature": float(temperature),
        "max_tokens": int(max_tokens),
        "stop": ["<END_OF_CODE>"],
    }

    if api_base:
        completion_params["api_base"] = api_base
    if api_key:
        completion_params["api_key"] = api_key

    def _dig(obj: Any, *path: Any) -> Any:
        cur = obj
        for key in path:
            if cur is None:
                return None
            if isinstance(key, int):
                try:
                    if isinstance(cur, list):
                        cur = cur[key]
                    else:
                        cur = cur[key]  # may raise
                except Exception:
                    return None
            else:
                if isinstance(cur, dict):
                    cur = cur.get(key)
                else:
                    cur = getattr(cur, key, None)
        return cur

    def _extract_visible_text(resp: Any) -> Optional[str]:
        """Try multiple layouts to pull visible text."""
        def _from_dict(d: Dict[str, Any]) -> Optional[str]:
            if not isinstance(d, dict):
                return None
            choices = d.get("choices") or []
            if not choices:
                return None
            ch0 = choices[0] or {}

            # Chat style
            msg = ch0.get("message") or {}
            content = msg.get("content")
            if isinstance(content, str) and content.strip():
                return content
            if isinstance(content, list):
                parts: List[str] = []
                for it in content:
                    if isinstance(it, dict):
                        parts.append(it.get("text") or it.get("content") or it.get("value") or "")
                    else:
                        parts.append(str(it))
                joined = "".join(parts).strip()
                if joined:
                    return joined

            # Completions style
            txt = ch0.get("text")
            if isinstance(txt, str) and txt.strip():
                return txt

            return None

        # 1) dict-like data
        data = None
        try:
            if hasattr(resp, "model_dump"):
                data = resp.model_dump()
            elif isinstance(resp, dict):
                data = resp
        except Exception:
            data = None

        text = _from_dict(data) if data is not None else None
        if text:
            return text

        # 2) attributes (LiteLLM pydantic types)
        try:
            content = getattr(resp.choices[0].message, "content", None)
            if isinstance(content, str) and content.strip():
                return content
            if isinstance(content, list):
                return "".join(
                    (c.get("text") if isinstance(c, dict) else str(c)) for c in content
                )
        except Exception:
            pass

        # 3) raw_response
        raw = getattr(resp, "raw_response", None)
        if isinstance(raw, dict):
            text = _from_dict(raw)
            if text:
                return text

        return None

    def _extract_code_lenient(body: str) -> str:
        code = _extract_code(body)
        if code:
            return code
        # Fallback if the model didn't close the fence
        m = re.search(r"```(?:python)?\n(.*)$", body, flags=re.DOTALL)
        if m:
            return m.group(1).rstrip() + "\n"
        # Final fallback: dump everything
        body = body.strip()
        return body + ("\n" if not body.endswith("\n") else "")

    message: Optional[str] = None
    finish_reason: Optional[str] = None

    # ------------------
    # 1) Try streaming
    # ------------------
    try:
        print("DEBUG: Trying streaming mode...")
        stream = litellm.completion(stream=True, **completion_params)
        buf: list[str] = []
        for chunk in stream:
            piece = (
                _dig(chunk, "choices", 0, "delta", "content")
                or _dig(chunk, "choices", 0, "text")
                or _dig(chunk, "choices", 0, "message", "content")
            )
            if piece:
                buf.append(piece)
            fr = _dig(chunk, "choices", 0, "finish_reason")
            if fr:
                finish_reason = fr
        message = "".join(buf).strip()
        print(f"DEBUG: collected {len(message)} characters from stream.")
    except Exception as e:
        print(f"DEBUG: Streaming failed, falling back to non-streaming. Error: {e}")

    # -------------------------------------
    # 2) Fallback: non-streaming completion
    # -------------------------------------
    if not message:
        response = litellm.completion(**completion_params)

        print("=" * 80)
        print("DEBUG: Raw response object:")
        print(response)
        print("=" * 80)

        # Try to dump raw JSON for visibility
        try:
            raw_dump = response.model_dump() if hasattr(response, "model_dump") else (
                response if isinstance(response, dict) else None
            )
            if raw_dump is not None:
                s = json.dumps(raw_dump, ensure_ascii=False)
                print("\nDEBUG: raw response JSON (first 2000 chars):")
                print(s[:2000])
        except Exception as dump_exc:
            print("DEBUG: could not dump raw response JSON:", repr(dump_exc))

        # finish reason (best effort)
        try:
            if isinstance(response, dict):
                finish_reason = _dig(response, "choices", 0, "finish_reason")
            else:
                finish_reason = getattr(response.choices[0], "finish_reason", None)
        except Exception:
            finish_reason = None

        # Extract visible text robustly
        message = _extract_visible_text(response)

        # Debug print
        try:
            if message:
                print("\n" + "=" * 80)
                print("DEBUG: Final message content (first 2000 chars):")
                print("=" * 80)
                print(message[:2000])
                print("=" * 80)
        except Exception:
            pass

    # -----------------
    # 3) Sanity checks
    # -----------------
    if finish_reason == "length":
        print(
            "\nWARNING: Response was truncated (finish_reason='length'). "
            "Consider increasing --max-tokens or reducing prompt size."
        )

    if not message:
        print("\nERROR: No message content found, cannot proceed")
        raise RuntimeError("Model returned no usable content from stream or standard response")

    # ------------------------------
    # 4) Extract code & write to file
    # ------------------------------
    code = _extract_code_lenient(message)

    save_path.parent.mkdir(parents=True, exist_ok=True)
    save_path.write_text(code, encoding="utf-8")
    return save_path


# -----------------------------------------------------------------------------
# CLI
# -----------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run a local OpenAI-compatible model on an AlgoTune task without the agent loop",
    )
    parser.add_argument("task", help="Registered AlgoTune task name (e.g. 'svm' or 'aes_gcm_encryption')")
    parser.add_argument("output", help="Destination path for the generated solver.py")
    parser.add_argument(
        "--model-name",
        required=True,
        help="Model identifier to send to the OpenAI-compatible endpoint.",
    )
    parser.add_argument("--api-base", dest="api_base", help="Base URL of the OpenAI-compatible endpoint", default=None)
    parser.add_argument(
        "--api-key",
        dest="api_key",
        help="API key for the OpenAI-compatible endpoint. Overrides environment/config values.",
        default=None,
    )
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument(
        "--max-tokens",
        type=int,
        default=8192,
        help="Maximum tokens to generate (interpreted by many backends as the total budget: prompt + completion).",
    )
    args = parser.parse_args()

    # Try to load config (optional)
    try:
        config = load_config()
        print(f"Attempting to load config from: {config.get('_loaded_from', '(unknown)')}" if isinstance(config, dict) else "Loaded config (unknown format)")
    except Exception as e:
        print(f"WARNING: Could not load AlgoTuner config: {e}")
        config = {}

    # Honor model-specific config if present (optional)
    models_config = config.get("models", {}) if isinstance(config, dict) else {}
    model_entry = models_config.get(args.model_name, {}) if isinstance(models_config, dict) else {}

    api_key = args.api_key
    api_base = args.api_base

    if api_key is None and isinstance(model_entry, dict):
        env_name = model_entry.get("api_key_env")
        if env_name:
            api_key = os.environ.get(env_name)

    if api_base is None and isinstance(model_entry, dict):
        api_base = model_entry.get("api_base") or model_entry.get("base_url")

    if api_key is None:
        raise SystemExit("No API key provided via --api-key or environment variable.")

    output_path = Path(args.output)
    final_path = run_local_model(
        model_name=args.model_name,
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
