#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import ast
import json
import os
import re
import textwrap
import re
import ast
from pathlib import Path
from typing import Dict, Tuple, Optional

import torch
from transformers import AutoTokenizer, AutoModelForCausalLM
from transformers import GPT2Tokenizer  # 用于 slow 回退（BPE）

MARKER_START = "<<<SOLVER_PY_START>>>"
MARKER_END = "<<<SOLVER_PY_END>>>"

# --- Safety switches ---
os.environ.setdefault("FLASH_ATTENTION_SKIP_IMPORT", "1")
os.environ.setdefault("XFORMERS_DISABLED", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("HF_HUB_OFFLINE", "1")


def read_text(path: Path) -> str:
    if not path.exists():
        raise FileNotFoundError(f"File not found: {path}")
    return path.read_text(encoding="utf-8")


def _get_source_segment(src: str, node: ast.AST) -> str:
    try:
        seg = ast.get_source_segment(src, node)
        if seg:
            return seg
    except Exception:
        pass
    lines = src.splitlines(True)
    s = getattr(node, "lineno", 1) - 1
    e = getattr(node, "end_lineno", s + 1)
    return "".join(lines[s:e])


def _extract_func_src(src: str, name: str) -> Optional[str]:
    try:
        tree = ast.parse(src)
    except SyntaxError:
        tree = None
    if tree:
        for n in tree.body:
            if isinstance(n, ast.FunctionDef) and n.name == name:
                return _get_source_segment(src, n).strip()
        for n in tree.body:
            if isinstance(n, ast.ClassDef):
                for m in n.body:
                    if isinstance(m, ast.FunctionDef) and m.name == name:
                        return _get_source_segment(src, m).strip()
    m = re.search(rf"(^|\n)\s*def\s+{name}\s*\(.*?\):\s*(?:\n(?:[ \t].*|\n)+)", src, re.DOTALL)
    return m.group(0).strip() if m else None


def extract_baseline_funcs(task_py_text: str) -> Tuple[str, str]:
    solve_src = _extract_func_src(task_py_text, "solve")
    is_solution_src = _extract_func_src(task_py_text, "is_solution")
    if not solve_src or not is_solution_src:
        raise RuntimeError("Failed to extract solve / is_solution from baseline.")
    return solve_src, is_solution_src


def build_prompt(desc_text: str, solve_src: str, is_solution_src: str) -> str:
    header = textwrap.dedent("""\
    You’re an autonomous programmer tasked with solving a specific problem.
    You are to use the commands defined below to accomplish this task.
    Apart from the default Python packages, you have access to the following
    additional packages:
    - cryptography
    - cvxpy
    - cython
    - dask
    - diffrax
    - ecos
    - faiss-cpu
    - hdbscan
    - highspy
    - jax
    - networkx
    - numba
    - numpy
    - ortools
    - pandas
    - pot
    - pulp
    - pyomo
    - python-sat
    - scikit-learn
    - scipy
    - sympy
    - torch
    YOUR TASK:
    Your objective is to define a class named ‘Solver‘ in ‘solver.py‘ with a
    method:
    ‘‘’
    class Solver:
    def solve(self, problem, **kwargs) -> Any:
    \"\"\"Your implementation goes here.\"\"\"
    ...
    ‘‘’
    IMPORTANT: Compilation time of your init function will not count towards
    your function’s runtime.

    This ‘solve‘ function will be the entrypoint called by the evaluation
    harness. Strive to align your class and method implementation as
    closely as possible with the desired performance criteria.
    For each instance, your function can run for at most 10x the baseline
    runtime for that instance. Strive to have your implementation run as
    fast as possible, while returning the same output as the baseline function (for the same given input). Be creative and optimize your
    approach!

    **GOALS:**
    Your primary objective is to optimize the ‘solve‘ function to run as as
    fast as possible, while returning the optimal solution.

    You will receive better scores the quicker your solution runs, and you
    will be penalized for exceeding the time limit or returning nonoptimal solutions.
    Below you find the description of the task you will have to solve. Read
    it carefully and understand what the problem is and what your solver
    should do.
    <task/description.txt>
    Here is the baseline which you will be graded against. Your task is to
    write a function that produces the same output, in less time.
    <task.solve>
    This function will be used to check if your solution is valid for a given
    problem. If it returns False, it means the solution is invalid:
    <task.is_solution>

    -----------

    for <task.xxx> please extract from the file directly

    --------

    the only output we need is solver.py, please let the model output this only in exact form mentioned in the prompt, and the solver should be putted in solver.py under output path with corresponding task name. 
    """).strip()

    prompt = header
    prompt = prompt.replace("<task/description.txt>", "\n" + desc_text.strip() + "\n")
    prompt = prompt.replace("<task.solve>", "\n" + solve_src + "\n")
    prompt = prompt.replace("<task.is_solution>", "\n" + is_solution_src + "\n")
    prompt += textwrap.dedent(f"""
    -----
    ABSOLUTE OUTPUT FORMAT (STRICT):

    You MUST wrap the **entire and only** contents of solver.py between the
    following two sentinel lines, with no extra characters, spaces or text
    before/after them:

    {MARKER_START}
    <solver.py contents ONLY — no backticks, no explanations>
    {MARKER_END}

    Rules:
    - Do NOT use Markdown code fences (no ```).
    - Do NOT print anything outside {MARKER_START} … {MARKER_END}.
    - The code must contain:
        - `from typing import Any`
        - `class Solver:` with `def solve(self, problem, **kwargs) -> Any:`
    """)
    return prompt


def _try_build_slow_gpt2_tokenizer_from_json(model_dir: Path):
    """
    纯 Python 解析 tokenizer.json（BPE）并构造慢速 GPT2Tokenizer。
    仅在 fast 失败且 tokenizer.json 的 model.type == 'BPE' 时使用。
    """
    tj_path = model_dir / "tokenizer.json"
    if not tj_path.exists():
        return None
    try:
        with open(tj_path, "r", encoding="utf-8") as f:
            tj = json.load(f)
    except Exception:
        return None

    model_obj = tj.get("model", {})
    if str(model_obj.get("type", "")).lower() != "bpe":
        return None

    vocab = model_obj.get("vocab")
    merges = model_obj.get("merges") or tj.get("merges")
    if not isinstance(vocab, dict) or not isinstance(merges, list):
        return None

    # 写出临时 vocab.json / merges.txt
    tmp_vocab = model_dir / "_tmp_vocab_from_json.json"
    tmp_merges = model_dir / "_tmp_merges_from_json.txt"
    try:
        import json as _json
        with open(tmp_vocab, "w", encoding="utf-8") as f:
            _json.dump(vocab, f, ensure_ascii=False)
        with open(tmp_merges, "w", encoding="utf-8") as f:
            f.write("\n".join(merges))
        tok = GPT2Tokenizer(vocab_file=str(tmp_vocab), merges_file=str(tmp_merges))
        if tok.pad_token_id is None and tok.eos_token_id is not None:
            tok.pad_token = tok.eos_token
        return tok
    except Exception:
        return None


def load_model(model_path: Path):
    import importlib, inspect, sys
    import torch
    from transformers import AutoTokenizer, AutoModelForCausalLM, PreTrainedModel, PretrainedConfig

    # 选择 dtype
    if torch.cuda.is_available():
        dtype = torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16
    else:
        dtype = torch.float32

    # 1) tokenizer（你这步没问题）
    tok = AutoTokenizer.from_pretrained(
        str(model_path),
        use_fast=True,
        trust_remote_code=True,
        local_files_only=True,
    )
    if tok.pad_token_id is None and getattr(tok, "eos_token_id", None) is not None:
        tok.pad_token_id = tok.eos_token_id

    # 2) 先尝试常规 Auto 路径（直接在 GPU 上构建，避免 CPU->GPU 大搬运峰值）
    try:
        mdl = AutoModelForCausalLM.from_pretrained(
            str(model_path),
            dtype=dtype,
            device_map="cuda",          # ★ 关键：直接落到 GPU
            trust_remote_code=True,
            local_files_only=True,
            low_cpu_mem_usage=True,
        )
        try: mdl.config.attn_implementation = "eager"
        except Exception: pass
        return tok, mdl
    except Exception as e:
        auto_err = e

    # 3) 兜底：直接从子模块导入，寻找 *ForCausalLM 的类
    #    目前 4.57.1 下 __init__ 里没导出，但子模块通常有定义
    try:
        m = importlib.import_module("transformers.models.gpt_oss.modeling_gpt_oss")
    except Exception as e:
        raise RuntimeError(f"无法导入子模块 transformers.models.gpt_oss.modeling_gpt_oss：{e}\n原始Auto错误：{auto_err!r}")

    # 枚举子模块中的类，优先选择类名以 ForCausalLM 结尾的 PreTrainedModel 子类
    candidate = None
    for name, obj in vars(m).items():
        if inspect.isclass(obj):
            try:
                if issubclass(obj, PreTrainedModel) and obj is not PreTrainedModel:
                    if name.endswith("ForCausalLM"):
                        candidate = obj
                        break
            except Exception:
                pass

    # 如果没找到严格后缀的，再退一步选择任意 PreTrainedModel 子类（通常只有一个实现）
    if candidate is None:
        for name, obj in vars(m).items():
            if inspect.isclass(obj):
                try:
                    if issubclass(obj, PreTrainedModel) and obj is not PreTrainedModel:
                        candidate = obj
                        break
                except Exception:
                    pass

    if candidate is None:
        raise RuntimeError(
            "在 transformers.models.gpt_oss.modeling_gpt_oss 中没有发现 PreTrainedModel 子类。"
            f"\n原始Auto错误：{auto_err!r}"
        )

    # 4) 配置同理，优先从 auto 读；读不到再从 configuration 子模块找一个 PretrainedConfig 子类
    try:
        cfg = PretrainedConfig.from_pretrained(str(model_path), trust_remote_code=True, local_files_only=True)
    except Exception:
        try:
            cm = importlib.import_module("transformers.models.gpt_oss.configuration_gpt_oss")
            cfg_cls = None
            for name, obj in vars(cm).items():
                if inspect.isclass(obj):
                    try:
                        if issubclass(obj, PretrainedConfig) and obj is not PretrainedConfig:
                            cfg_cls = obj; break
                    except Exception:
                        pass
            if cfg_cls is None:
                raise RuntimeError("未找到 gpt_oss 的 PretrainedConfig 子类")
            cfg = cfg_cls.from_pretrained(str(model_path), trust_remote_code=True, local_files_only=True)
        except Exception as e:
            raise RuntimeError(f"加载 gpt_oss 配置失败（既非 Auto 也非手动）：{e}\n原始Auto错误：{auto_err!r}")

    # 5) 用找到的类加载权重
    mdl = candidate.from_pretrained(
        str(model_path),
        config=cfg,
        torch_dtype=dtype,
        device_map="cuda",             # ★ 手动 fallback 也直接落到 GPU
        trust_remote_code=True,
        local_files_only=True,
        low_cpu_mem_usage=True,
    )
    try: mdl.config.attn_implementation = "eager"
    except Exception: pass
    return tok, mdl



def apply_chat_template(tokenizer, prompt: str) -> Dict[str, torch.Tensor]:
    try:
        input_ids = tokenizer.apply_chat_template(
            [{"role": "user", "content": prompt}],
            tokenize=True,
            add_generation_prompt=True,
            return_tensors="pt",
        )
        return {"input_ids": input_ids}
    except Exception:
        return tokenizer(prompt, return_tensors="pt")


def run_inference(tokenizer, model, prompt: str, max_new_tokens: int = 2048) -> str:
    model.eval()
    inputs = apply_chat_template(tokenizer, prompt)
    dev = next(model.parameters()).device
    for k in inputs:
        inputs[k] = inputs[k].to(dev)

    # 预热：触发 Triton kernel 首编译，降低首次卡顿/碎片
    with torch.inference_mode():
        _ = model.generate(**inputs, max_new_tokens=1, do_sample=False)
        if next(model.parameters()).is_cuda:
            torch.cuda.synchronize()
        out = model.generate(
            **inputs,
            max_new_tokens=max_new_tokens,
            do_sample=False,             # 保持可复现
            repetition_penalty=1.05,
            eos_token_id=getattr(tokenizer, "eos_token_id", None),
            pad_token_id=getattr(tokenizer, "pad_token_id", None),
        )
    gen_ids = out[:, inputs["input_ids"].shape[1]:]
    txt = tokenizer.decode(gen_ids[0], skip_special_tokens=True)
    return txt.strip()


def extract_solver_py(text: str) -> str:
    """
    只提取 {MARKER_START} 与 {MARKER_END} 之间的代码并返回。
    不做任何其它兜底，不拼 baseline，不抓 fenced block。
    若标记缺失，直接报错。
    """
    t = text.replace("\r\n", "\n").replace("\r", "\n").lstrip("\ufeff")

    # 允许标记前后有空白，但标记字符串必须原样出现
    start = t.find(MARKER_START)
    if start == -1:
        raise RuntimeError("MARKER_START not found in model output")

    start += len(MARKER_START)
    end = t.find(MARKER_END, start)
    if end == -1:
        raise RuntimeError("MARKER_END not found in model output")

    code = t[start:end].strip()

    # 如果模型仍然把代码包进了 ```python fenced block，去掉围栏
    code = re.sub(r"^```(?:python|py)?\s*", "", code, flags=re.IGNORECASE).strip()
    code = re.sub(r"\s*```$", "", code).strip()

    # 可选：小修补——若使用了 Any 却没导入，补上 import（仍为纯代码）
    if "from typing import Any" not in code and re.search(r"\bAny\b", code):
        code = "from typing import Any\n" + code

    # 可选：快速契约检查，确保真的有 class Solver.solve（不满足则报错）
    try:
        tree = ast.parse(code)
        ok = False
        for n in tree.body:
            if isinstance(n, ast.ClassDef) and n.name == "Solver":
                for m in n.body:
                    if isinstance(m, ast.FunctionDef) and m.name == "solve":
                        ok = True
                        break
        if not ok:
            raise RuntimeError("extracted segment does not contain class Solver.solve")
    except Exception as e:
        raise RuntimeError(f"invalid solver.py segment: {e}")

    return code



def main():
    p = argparse.ArgumentParser()
    p.add_argument("--task", required=True)
    p.add_argument("--model-path", default="/data/zq/models/gpt-oss-20b")
    p.add_argument("--tasks-root", default="/data/zq/evolve/AlgoTune/AlgoTuneTasks")
    p.add_argument("--out-root", default="/data/zq/evolve/AlgoTune/results/chatgptoss-20b")
    p.add_argument("--max-new-tokens", type=int, default=2048)
    args = p.parse_args()

    task = args.task
    model_path = Path(args.model_path)
    tasks_root = Path(args.tasks_root)
    out_root = Path(args.out_root)

    desc_path = tasks_root / task / "description.txt"
    task_py_path = tasks_root / task / f"{task}.py"

    out_dir = out_root / task
    out_dir.mkdir(parents=True, exist_ok=True)
    solver_out = out_dir / "solver.py"
    prompt_out = out_dir / "prompt_used.txt"
    raw_out = out_dir / "raw_model_output.txt"

    print(f"[INFO] Task       : {task}")
    print(f"[INFO] Model Path : {model_path}")
    print(f"[INFO] Desc Path  : {desc_path}")
    print(f"[INFO] Task Py    : {task_py_path}")
    print(f"[INFO] Output Dir : {out_dir}")

    desc_text = read_text(desc_path)
    task_py_text = read_text(task_py_path)
    solve_src, is_solution_src = extract_baseline_funcs(task_py_text)
    prompt = build_prompt(desc_text, solve_src, is_solution_src)
    prompt_out.write_text(prompt, encoding="utf-8")

    tok, mdl = load_model(model_path)

    gen = run_inference(tok, mdl, prompt, max_new_tokens=args.max_new_tokens)
    raw_out.write_text(gen, encoding="utf-8")

    code = extract_solver_py(gen)
    solver_out.write_text(code, encoding="utf-8")
    print(f"[OK] solver.py -> {solver_out}")


if __name__ == "__main__":
    main()
