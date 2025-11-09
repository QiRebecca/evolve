#!/usr/bin/env python3
import json
import numpy as np
from collections import defaultdict

try:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False
    print("Warning: matplotlib not available, skipping plots")

with open('/data/zq/evolve/results/eval_summary.json', 'r') as f:
    eval_data = json.load(f)

with open('/data/zq/evolve/AlgoTune/reports/generation.json', 'r') as f:
    generation_data = json.load(f)

print("=" * 80)
print("评估数据分析报告")
print("=" * 80)

print("\n1. 任务总体情况分析")
print("-" * 80)

total_tasks_in_generation = len(generation_data)
print(f"generation.json中的总任务数: {total_tasks_in_generation}")

eval_tasks = set()
for task_name, models in eval_data.items():
    eval_tasks.add(task_name)

tasks_in_generation = set(generation_data.keys())
evaluated_tasks = eval_tasks & tasks_in_generation
missing_tasks = tasks_in_generation - eval_tasks

print(f"eval_summary.json中已评估的任务数: {len(evaluated_tasks)}")
print(f"未评估的任务数: {len(missing_tasks)}")

if missing_tasks:
    print(f"\n未评估的任务列表 ({len(missing_tasks)}个):")
    for i, task in enumerate(sorted(missing_tasks), 1):
        print(f"  {i}. {task}")

print("\n2. chatgptoss-20b 评估结果统计")
print("-" * 80)

gptoss_tasks = []
for task_name, models in eval_data.items():
    if 'chatgptoss-20b' in models:
        gptoss_tasks.append((task_name, models['chatgptoss-20b']))

print(f"chatgptoss-20b 评估的任务总数: {len(gptoss_tasks)}")

fully_valid = []
partially_valid = []
fully_invalid = []
accuracies = []
speedups = []

for task_name, result in gptoss_tasks:
    valid_count = result.get('num_valid', result.get('valid_count', 0))
    total_count = result.get('num_evaluated', result.get('total_count', 0))
    
    accuracy_raw = result.get('accuracy', 0)
    accuracy = float(accuracy_raw) if accuracy_raw else 0
    
    speedup_raw = result.get('speedup', None)
    speedup = float(speedup_raw) if speedup_raw and speedup_raw != 'N/A' else None
    
    accuracies.append(accuracy)
    
    if valid_count == total_count and valid_count > 0:
        fully_valid.append((task_name, result))
        # 只统计完全成功的任务的speedup
        if speedup is not None and speedup > 0 and accuracy == 1.0:
            speedups.append((task_name, speedup))
    elif valid_count > 0:
        partially_valid.append((task_name, result))
    else:
        fully_invalid.append((task_name, result))

print(f"\n完全成功 (所有测试通过): {len(fully_valid)} 个 ({len(fully_valid)/len(gptoss_tasks)*100:.1f}%)")
print(f"部分成功 (部分测试通过): {len(partially_valid)} 个 ({len(partially_valid)/len(gptoss_tasks)*100:.1f}%)")
print(f"完全失败 (所有测试失败): {len(fully_invalid)} 个 ({len(fully_invalid)/len(gptoss_tasks)*100:.1f}%)")

print(f"\nAccuracy 统计:")
print(f"  平均 Accuracy: {np.mean(accuracies):.4f} ({np.mean(accuracies)*100:.2f}%)")
print(f"  中位数 Accuracy: {np.median(accuracies):.4f} ({np.median(accuracies)*100:.2f}%)")
print(f"  最小 Accuracy: {np.min(accuracies):.4f} ({np.min(accuracies)*100:.2f}%)")
print(f"  最大 Accuracy: {np.max(accuracies):.4f} ({np.max(accuracies)*100:.2f}%)")

accuracy_1_0 = sum(1 for a in accuracies if a == 1.0)
accuracy_0_5_to_1 = sum(1 for a in accuracies if 0.5 <= a < 1.0)
accuracy_0_to_0_5 = sum(1 for a in accuracies if 0 < a < 0.5)
accuracy_0 = sum(1 for a in accuracies if a == 0)

print(f"\nAccuracy 分布:")
print(f"  Accuracy = 1.0:       {accuracy_1_0} 个 ({accuracy_1_0/len(gptoss_tasks)*100:.1f}%)")
print(f"  0.5 ≤ Accuracy < 1.0: {accuracy_0_5_to_1} 个 ({accuracy_0_5_to_1/len(gptoss_tasks)*100:.1f}%)")
print(f"  0 < Accuracy < 0.5:   {accuracy_0_to_0_5} 个 ({accuracy_0_to_0_5/len(gptoss_tasks)*100:.1f}%)")
print(f"  Accuracy = 0:         {accuracy_0} 个 ({accuracy_0/len(gptoss_tasks)*100:.1f}%)")

print("\n3. Speedup 分析 (仅包含完全成功的任务)")
print("-" * 80)

print(f"\n有效 Speedup 数据的任务数: {len(speedups)} (仅统计 Accuracy=1.0 的任务)")

if len(speedups) > 0:
    speedup_values = [s for _, s in speedups]
    
    print(f"\nSpeedup 统计:")
    print(f"  平均 Speedup: {np.mean(speedup_values):.2f}x")
    print(f"  中位数 Speedup: {np.median(speedup_values):.2f}x")
    print(f"  最小 Speedup: {np.min(speedup_values):.2f}x")
    print(f"  最大 Speedup: {np.max(speedup_values):.2f}x")
    print(f"  标准差: {np.std(speedup_values):.2f}")
    
    speedup_ranges = [
        ("< 1x (变慢)", lambda x: x < 1),
        ("1x - 2x", lambda x: 1 <= x < 2),
        ("2x - 5x", lambda x: 2 <= x < 5),
        ("5x - 10x", lambda x: 5 <= x < 10),
        ("10x - 50x", lambda x: 10 <= x < 50),
        ("≥ 50x", lambda x: x >= 50),
    ]
    
    print(f"\nSpeedup 分布:")
    for range_name, condition in speedup_ranges:
        count = sum(1 for s in speedup_values if condition(s))
        print(f"  {range_name:20s}: {count:3d} 个 ({count/len(speedups)*100:5.1f}%)")
    
    sorted_speedups = sorted(speedups, key=lambda x: x[1], reverse=True)
    
    print(f"\nTop 10 最高 Speedup:")
    for i, (task, speedup) in enumerate(sorted_speedups[:10], 1):
        print(f"  {i:2d}. {task:40s} {speedup:8.2f}x")
    
    print(f"\nTop 10 最低 Speedup (或变慢):")
    for i, (task, speedup) in enumerate(sorted_speedups[-10:][::-1], 1):
        print(f"  {i:2d}. {task:40s} {speedup:8.2f}x")
    
    if HAS_MATPLOTLIB:
        print("\n生成 Speedup 分布图...")
        
        fig, axes = plt.subplots(2, 2, figsize=(15, 12))
        
        axes[0, 0].hist(speedup_values, bins=50, edgecolor='black', alpha=0.7)
        axes[0, 0].set_xlabel('Speedup')
        axes[0, 0].set_ylabel('Frequency')
        axes[0, 0].set_title(f'Speedup Distribution (All {len(speedups)} tasks)')
        axes[0, 0].axvline(np.mean(speedup_values), color='r', linestyle='--', label=f'Mean: {np.mean(speedup_values):.2f}x')
        axes[0, 0].axvline(np.median(speedup_values), color='g', linestyle='--', label=f'Median: {np.median(speedup_values):.2f}x')
        axes[0, 0].legend()
        axes[0, 0].grid(True, alpha=0.3)
        
        speedup_values_log = [s for s in speedup_values if s > 0]
        axes[0, 1].hist(speedup_values_log, bins=50, edgecolor='black', alpha=0.7)
        axes[0, 1].set_xlabel('Speedup')
        axes[0, 1].set_ylabel('Frequency')
        axes[0, 1].set_title('Speedup Distribution (Log Scale X-axis)')
        axes[0, 1].set_xscale('log')
        axes[0, 1].grid(True, alpha=0.3)
        
        range_counts = [sum(1 for s in speedup_values if condition(s)) for _, condition in speedup_ranges]
        range_labels = [name for name, _ in speedup_ranges]
        colors = ['red', 'orange', 'yellow', 'lightgreen', 'green', 'darkgreen']
        axes[1, 0].bar(range(len(range_counts)), range_counts, color=colors, edgecolor='black', alpha=0.7)
        axes[1, 0].set_xticks(range(len(range_labels)))
        axes[1, 0].set_xticklabels(range_labels, rotation=45, ha='right')
        axes[1, 0].set_ylabel('Number of Tasks')
        axes[1, 0].set_title('Speedup Range Distribution')
        axes[1, 0].grid(True, alpha=0.3, axis='y')
        for i, count in enumerate(range_counts):
            axes[1, 0].text(i, count + 0.5, str(count), ha='center', va='bottom')
        
        sorted_tasks = [task[:30] for task, _ in sorted_speedups[:20]]
        sorted_values = [speedup for _, speedup in sorted_speedups[:20]]
        y_pos = np.arange(len(sorted_tasks))
        axes[1, 1].barh(y_pos, sorted_values, color='steelblue', edgecolor='black', alpha=0.7)
        axes[1, 1].set_yticks(y_pos)
        axes[1, 1].set_yticklabels(sorted_tasks, fontsize=8)
        axes[1, 1].set_xlabel('Speedup')
        axes[1, 1].set_title('Top 20 Tasks by Speedup')
        axes[1, 1].grid(True, alpha=0.3, axis='x')
        axes[1, 1].invert_yaxis()
        
        plt.tight_layout()
        plt.savefig('/data/zq/evolve/analyze/speedup_analysis.png', dpi=150, bbox_inches='tight')
        print(f"图表已保存到: /data/zq/evolve/analyze/speedup_analysis.png")
    else:
        print("\n(matplotlib 未安装，跳过图表生成)")
    
    with open('/data/zq/evolve/analyze/speedup_detailed_table.txt', 'w') as f:
        f.write("=" * 100 + "\n")
        f.write("Speedup 详细表格 (仅包含 Accuracy=1.0 的任务)\n")
        f.write("=" * 100 + "\n\n")
        f.write(f"{'排名':<6}{'任务名称':<45}{'Speedup':>10}{'Accuracy':>10}{'Valid/Total':>15}\n")
        f.write("-" * 100 + "\n")
        
        for i, (task, speedup) in enumerate(sorted_speedups, 1):
            task_result = next(r for t, r in gptoss_tasks if t == task)
            accuracy_raw = task_result.get('accuracy', 0)
            accuracy = float(accuracy_raw) if accuracy_raw else 0
            valid = task_result.get('num_valid', task_result.get('valid_count', 0))
            total = task_result.get('num_evaluated', task_result.get('total_count', 0))
            f.write(f"{i:<6}{task:<45}{speedup:>10.2f}x{accuracy:>9.2%}{valid:>7}/{total:<7}\n")
    
    print(f"详细表格已保存到: /data/zq/evolve/analyze/speedup_detailed_table.txt")

print("\n" + "=" * 80)
print("分析完成!")
print("=" * 80)

