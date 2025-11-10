env:
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate env


vllm:
export CUDA_VISIBLE_DEVICES=2,6
python -m vllm.entrypoints.openai.api_server \
  --model /data/zq/models/gpt-oss-20b \
  --host 0.0.0.0 \
  --port 8010 \
  --served-model-name chatgptoss-20b \
  --tensor-parallel-size 2 \
  --max-model-len 8192 \
  --dtype bfloat16 \
  --quantization mxfp4 \
  --gpu-memory-utilization 0.70


local model test:
python /data/zq/evolve/AlgoTune/scripts/gen_solver.py   --task aes_gcm_encryption   --model-path /data/zq/models/gpt-oss-20b   --tasks-root /data/zq/evolve/AlgoTune/AlgoTuneTasks   --out-root /data/zq/evolve/AlgoTune/results/chatgptoss-20b   --max-new-tokens 1600


all tasks:
python /data/zq/evolve/AlgoTune/scripts/gen_all_tasks.py   --gpus 2   --gen-solver /data/zq/evolve/AlgoTune/scripts/gen_solver.py   --tasks-root /data/zq/evolve/AlgoTune/AlgoTuneTasks   --model-path /data/zq/models/gpt-oss-20b   --out-root /data/zq/evolve/AlgoTune/results/chatgptoss-20b   --max-new-tokens 1600

clean the gpu first command:
# =====================  Step 1. 清理 GPU 显存与残留进程  =====================

echo "[CLEAN] Killing leftover python processes using GPU..."
for pid in $(nvidia-smi | awk '/python|PYTHON|gen_solver|gen_all|run_all/ {print $5}'); do
  echo " -> kill PID $pid"
  kill -TERM $pid 2>/dev/null || true
done
sleep 2
for pid in $(nvidia-smi | awk '/python|PYTHON|gen_solver|gen_all|run_all/ {print $5}'); do
  echo " -> force kill PID $pid"
  kill -KILL $pid 2>/dev/null || true
done

echo "[CLEAN] Checking GPU status..."
nvidia-smi

# 如果依旧有残留句柄（很少见），用 fuser 检查
fuser -v /dev/nvidia2 /dev/nvidia6 /dev/nvidia-uvm 2>/dev/null || true

# =====================  Step 2. 清理 CUDA/JIT 缓存  =====================
echo "[CLEAN] Removing CUDA / Torch caches..."
rm -rf ~/.nv/ComputeCache
rm -rf ~/.triton
rm -rf ~/.cache/torch_extensions
rm -rf ~/.cache/huggingface/accelerate

# =====================  Step 3. 设置推荐环境变量  =====================
echo "[SETUP] Export environment variables..."
unset PYTORCH_ALLOC_CONF
export PYTORCH_CUDA_ALLOC_CONF="expandable_segments:True,max_split_size_mb:128"
export TOKENIZERS_PARALLELISM=false
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
export CUDA_VISIBLE_DEVICES=2,6

# =====================  Step 4. 启动多任务生成  =====================
echo "[RUN] Starting gen_all_tasks.py ..."
python /data/zq/evolve/AlgoTune/scripts/gen_all_tasks.py \
  --gpus 2,6 \
  --gen-solver /data/zq/evolve/AlgoTune/scripts/gen_solver.py \
  --tasks-root /data/zq/evolve/AlgoTune/AlgoTuneTasks \
  --model-path /data/zq/models/gpt-oss-20b \
  --out-root /data/zq/evolve/AlgoTune/results/chatgptoss-20b \
  --max-new-tokens 1600

# =====================  Done  =====================
echo "[DONE] All tasks finished or running. Check results in:"
echo "        /data/zq/evolve/AlgoTune/results/chatgptoss-20b/"



failed task rerun:
change gen_solver.fail.back to gen_solver.py
export CUDA_VISIBLE_DEVICES=2
python /data/zq/evolve/AlgoTune/scripts/gen_all_tasks.py \
  --gpus 2 \
  --gen-solver /data/zq/evolve/AlgoTune/scripts/gen_solver.py \
  --tasks-root /data/zq/evolve/AlgoTune/AlgoTuneTasks \
  --model-path /data/zq/models/gpt-oss-20b \
  --out-root /data/zq/evolve/AlgoTune/results/chatgptoss-20b \
  --max-new-tokens 5000 \
  --only \
  channel_capacity aircraft_wing_design graph_isomorphism group_lasso job_shop_scheduling kalman_filter kernel_density_estimation minimum_volume_ellipsoid nmf polynomial_real quantile_regression rectanglepacking set_cover_conflicts shortest_path_dijkstra toeplitz_solver tensor_completion_3d vectorized_newton vehicle_routing




generate tasks data（10+10data）：
cd /data/zq/evolve && \
nohup bash run_sequential_with_real_timeout.sh > /data/zq/evolve/logs/nohup_sequential_$(date +%Y%m%d_%H%M%S).log 2>&1 &
 
#断点重跑超时跳过：
cd /data/zq/evolve && \
nohup bash run_retry_timeouts.sh > /data/zq/evolve/logs/nohup_retry_timeouts_$(date +%Y%m%d_%H%M%S).log 2>&1 &




openevolve:
ALGO_TUNE_TASK=aes_gcm_encryption \
ALGO_TUNE_DATA_DIR=/data/zq/evolve/AlgoTune/data \
ALGO_TUNE_SPLIT=train \
ALGO_TUNE_NUM_RUNS=10 \
python openevolve/openevolve-run.py \
  /data/zq/evolve/AlgoTune/AlgoTuneTasks/aes_gcm_encryption/aes_gcm_encryption.py \
  AlgoTune/evaluate.py \
  --config openevolve/configs/algotune_prompt.yaml \
  --primary-model o3 \
  --iterations 5 \
  --output openevolve/result/aes_gcm_encryption


openevolve evaluate:
cd /data/zq/evolve && mkdir -p /data/zq/evolve/.dace_cache && \
ALGO_TUNE_TASK=aes_gcm_encryption \
ALGO_TUNE_DATA_DIR=/data/zq/evolve/AlgoTune/data \
ALGO_TUNE_SPLIT=test \
DACE_cache_dir=/data/zq/evolve/.dace_cache \
poetry run python scripts/save_eval_to_summary.py \
  --task aes_gcm_encryption \
  --model "openevolve-best" \
  --solver openevolve/result/aes_gcm_encryption/best/best_program.py \
  --summary-file results/eval_summary.json \
  --generation-file reports/generation.json \
  --data-dir AlgoTune/data \
  --num-runs 10



gptoss-20b evaluate:
./run_batch_eval_solvers.sh

  


baseline test result generate：
./run_batch_generate_test_baselines.sh