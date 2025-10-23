#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import argparse
import traceback
from pathlib import Path
from multiprocessing import Process, Queue
import importlib.util
from datetime import datetime

def import_gen_solver(gen_solver_path: str):
    """把 gen_solver.py 当模块加载，复用其内部函数以便一次加载模型跑多任务。"""
    spec = importlib.util.spec_from_file_location("gen_solver_mod", gen_solver_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # type: ignore
    return mod

def discover_tasks(tasks_root: Path):
    tasks = []
    for p in sorted(tasks_root.iterdir()):
        if not p.is_dir():
            continue
        if (p / f"{p.name}.py").exists() and (p / "description.txt").exists():
            tasks.append(p.name)
    return tasks

def worker(gpu_id: str, task_q: Queue, result_q: Queue, args):
    """每个 GPU一个 worker：加载一次模型，循环处理任务队列。"""
    # 进程级环境
    os.environ["CUDA_VISIBLE_DEVICES"] = str(gpu_id)
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
    os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "max_split_size_mb:128")

    gen = import_gen_solver(args.gen_solver)

    # 一次加载模型（关键）
    try:
        tok, mdl = gen.load_model(Path(args.model_path))
    except Exception as e:
        result_q.put(("__FATAL__", gpu_id, f"load_model failed: {e}"))
        return

    while True:
        task = task_q.get()
        if task is None:
            result_q.put(("__DONE__", gpu_id, ""))
            break

        try:
            # 路径
            task_dir = Path(args.tasks_root) / task
            desc_path = task_dir / "description.txt"
            task_py_path = task_dir / f"{task}.py"

            out_dir = Path(args.out_root) / task
            out_dir.mkdir(parents=True, exist_ok=True)
            solver_out = out_dir / "solver.py"
            prompt_out = out_dir / "prompt_used.txt"
            raw_out = out_dir / "raw_model_output.txt"
            log_path = out_dir / "run.log"

            # 跳过已完成
            if (not args.force) and solver_out.exists():
                result_q.put((task, 0, f"skip (exists {solver_out})"))
                continue

            # 读 baseline 与描述
            desc_text = Path(desc_path).read_text(encoding="utf-8")
            task_py_text = Path(task_py_path).read_text(encoding="utf-8")
            solve_src, is_solution_src = gen.extract_baseline_funcs(task_py_text)
            prompt = gen.build_prompt(desc_text, solve_src, is_solution_src)
            prompt_out.write_text(prompt, encoding="utf-8")

            # 运行生成
            with open(log_path, "a", encoding="utf-8") as logf:
                logf.write(f"\n=== [{datetime.now().isoformat()}] START {task} (GPU {gpu_id}) ===\n")
                logf.flush()
                txt = gen.run_inference(tok, mdl, prompt, max_new_tokens=args.max_new_tokens)
                raw_out.write_text(txt, encoding="utf-8")
                code = gen.extract_solver_py(txt)
                solver_out.write_text(code, encoding="utf-8")
                logf.write(f"=== END {task} -> {solver_out}\n")
                logf.flush()

            result_q.put((task, 0, "ok"))
        except Exception:
            err = traceback.format_exc()
            try:
                (Path(args.out_root) / task / "run.log").write_text(err, encoding="utf-8")
            except Exception:
                pass
            result_q.put((task, 1, err))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gen-solver", default="/data/zq/evolve/AlgoTune/scripts/gen_solver.py")
    ap.add_argument("--tasks-root", default="/data/zq/evolve/AlgoTune/AlgoTuneTasks")
    ap.add_argument("--model-path", default="/data/zq/models/gpt-oss-20b")
    ap.add_argument("--out-root", default="/data/zq/evolve/AlgoTune/results/chatgptoss-20b")
    ap.add_argument("--max-new-tokens", type=int, default=1600)
    ap.add_argument("--gpus", default="2,6", help="逗号分隔GPU编号，如: 2,6")
    ap.add_argument("--only", nargs="*", help="仅运行这些 task 名（可选）")
    ap.add_argument("--exclude", nargs="*", default=[], help="排除这些 task 名（可选）")
    ap.add_argument("--force", action="store_true", help="即使已存在 solver.py 也强制重跑")
    args = ap.parse_args()

    tasks_root = Path(args.tasks_root)
    out_root = Path(args.out_root)
    out_root.mkdir(parents=True, exist_ok=True)

    all_tasks = discover_tasks(tasks_root)
    if args.only:
        only_set = set(args.only)
        tasks = [t for t in all_tasks if t in only_set]
    else:
        tasks = all_tasks[:]
    if args.exclude:
        ex_set = set(args.exclude)
        tasks = [t for t in tasks if t not in ex_set]

    # 跳过已完成
    if not args.force:
        pending = []
        for t in tasks:
            if not (out_root / t / "solver.py").exists():
                pending.append(t)
        tasks = pending

    if not tasks:
        print("[INFO] 没有需要执行的任务（可能都已完成）。")
        return

    gpu_ids = [g.strip() for g in args.gpus.split(",") if g.strip()]
    print(f"[INFO] 待执行任务数: {len(tasks)}, GPUs: {gpu_ids}")

    # 任务队列（共享），两块 GPU 动态抢任务，最大化利用率
    task_q: Queue = Queue()
    result_q: Queue = Queue()
    for t in tasks:
        task_q.put(t)
    # 结束哨兵
    for _ in gpu_ids:
        task_q.put(None)

    # 启动 worker
    workers = []
    for g in gpu_ids:
        p = Process(target=worker, args=(g, task_q, result_q, args), daemon=False)
        p.start()
        workers.append(p)

    total = len(tasks)
    done = 0
    failed = []

    while done < total:
        task, rc, msg = result_q.get()
        if task in ("__DONE__", "__FATAL__"):
            # worker 生命周期消息，忽略计数
            print(f"[{task}] GPU {rc}: {msg}")
            continue
        done += 1
        status = "OK" if rc == 0 else "FAIL"
        print(f"[{done}/{total}] {task}: {status} {('- ' + msg) if msg else ''}")
        if rc != 0:
            failed.append(task)

    for p in workers:
        p.join()

    print("\n=== SUMMARY ===")
    print(f"Total: {total}, Success: {total - len(failed)}, Failed: {len(failed)}")
    if failed:
        print("Failed tasks:")
        for t in failed:
            print(" -", t)

if __name__ == "__main__":
    main()
