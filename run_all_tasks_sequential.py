#!/usr/bin/env python3
"""
串行运行所有OpenEvolve task（逐个运行，不并行）
"""
import subprocess
import sys
import os
import json
import time
from pathlib import Path
from typing import List, Tuple

# 配置
CONFIG_FILE = "openevolve/configs/algotune_prompt.yaml"
PRIMARY_MODEL = "o3"
ITERATIONS = 20  # Evolution迭代次数
TIMEOUT_HOURS = 2
TIMEOUT_SECONDS = TIMEOUT_HOURS * 3600
RESULTS_BASE = "openevolve/result"
LOG_DIR = "logs"

# 环境变量
os.environ.setdefault("ALGO_TUNE_DATA_DIR", "/data/zq/evolve/AlgoTune/data")
os.environ.setdefault("ALGO_TUNE_SPLIT", "train")
os.environ.setdefault("ALGO_TUNE_NUM_RUNS", "5")  # 每个evaluation运行5次


def load_tasks() -> List[str]:
    """加载所有task列表"""
    try:
        with open("reports/generation.json", "r") as f:
            data = json.load(f)
        return sorted(data.keys())
    except FileNotFoundError:
        print("❌ 找不到 reports/generation.json")
        sys.exit(1)


def is_completed(task_name: str) -> bool:
    """检查task是否已完成"""
    result_dir = Path(RESULTS_BASE) / task_name
    return (result_dir / "best_program.py").exists()


def run_task(task_name: str) -> Tuple[str, bool, str]:
    """运行单个task"""
    output_dir = Path(RESULTS_BASE) / task_name
    log_file = Path(LOG_DIR) / f"{task_name}.log"
    
    # 创建目录
    output_dir.mkdir(parents=True, exist_ok=True)
    log_file.parent.mkdir(parents=True, exist_ok=True)
    
    print(f"🚀 Starting task: {task_name}")
    
    # 构建命令
    cmd = [
        "timeout", str(TIMEOUT_SECONDS),
        "bash", "-c",
        f"ALGO_TUNE_TASK={task_name} "
        f"python openevolve/openevolve-run.py "
        f"/data/zq/evolve/AlgoTune/AlgoTuneTasks/{task_name}/{task_name}.py "
        f"AlgoTune/evaluate.py "
        f"--config {CONFIG_FILE} "
        f"--primary-model {PRIMARY_MODEL} "
        f"--iterations {ITERATIONS} "
        f"--output {output_dir}"
    ]
    
    # 运行任务
    start_time = time.time()
    try:
        with open(log_file, "w") as log_f:
            result = subprocess.run(
                cmd,
                stdout=log_f,
                stderr=subprocess.STDOUT,
                cwd="/data/zq/evolve",
                timeout=TIMEOUT_SECONDS + 60  # 额外60秒缓冲
            )
        
        elapsed = time.time() - start_time
        
        # 检查结果
        if result.returncode == 124:  # timeout命令的超时退出码
            return (task_name, False, f"TIMEOUT after {TIMEOUT_HOURS}h")
        elif result.returncode == 0:
            if is_completed(task_name):
                return (task_name, True, f"SUCCESS ({elapsed:.1f}s)")
            else:
                return (task_name, False, "No best_program.py found")
        else:
            return (task_name, False, f"FAILED (exit code {result.returncode})")
            
    except subprocess.TimeoutExpired:
        return (task_name, False, f"TIMEOUT after {TIMEOUT_HOURS}h")
    except Exception as e:
        return (task_name, False, f"EXCEPTION: {str(e)}")


def main():
    """主函数"""
    print("=" * 70)
    print("串行运行所有OpenEvolve Tasks")
    print("=" * 70)
    print(f"运行方式: 串行（逐个运行，不并行）")
    print(f"每个task超时: {TIMEOUT_HOURS}小时")
    print(f"迭代次数: {ITERATIONS}")
    print(f"每个evaluation运行次数: {os.environ.get('ALGO_TUNE_NUM_RUNS', '5')}")
    print(f"Checkpoint间隔: 每5个iteration")
    print()
    
    # 加载tasks
    all_tasks = load_tasks()
    print(f"📋 总共 {len(all_tasks)} 个tasks")
    
    # 过滤已完成的tasks
    pending_tasks = [t for t in all_tasks if not is_completed(t)]
    print(f"⏳ 待运行: {len(pending_tasks)} 个tasks")
    print(f"✅ 已完成: {len(all_tasks) - len(pending_tasks)} 个tasks")
    print()
    
    if not pending_tasks:
        print("✅ 所有tasks都已完成！")
        return
    
    # 串行运行
    completed = []
    failed = []
    
    print(f"🚀 开始串行运行（逐个运行）...")
    print()
    
    for i, task in enumerate(pending_tasks, 1):
        print(f"[{i}/{len(pending_tasks)}] 运行: {task}")
        task_name, success, message = run_task(task)
        
        if success:
            completed.append(task_name)
            print(f"✅ [{i}/{len(pending_tasks)}] {task_name}: {message}")
        else:
            failed.append((task_name, message))
            print(f"❌ [{i}/{len(pending_tasks)}] {task_name}: {message}")
        
        print()  # 空行分隔
    
    # 总结
    print("=" * 70)
    print("运行总结")
    print("=" * 70)
    print(f"✅ 成功: {len(completed)}")
    print(f"❌ 失败: {len(failed)}")
    print(f"📊 总计: {len(pending_tasks)}")
    
    if failed:
        print()
        print("失败的tasks:")
        for task_name, message in failed:
            print(f"  - {task_name}: {message}")


if __name__ == "__main__":
    main()

