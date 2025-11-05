#!/bin/bash

# 设置所有必要的环境变量
export ALGO_TUNE_TASK="aes_gcm_encryption"
export ALGO_TUNE_DATA_DIR="/data/zq/evolve/data"
export ALGO_TUNE_SPLIT="train"  # 训练阶段用train
export OPENAI_API_KEY="sk-qsGBu9Fb3yNwW4NH02F902229cB94668A593927e46742f00"

# 配置DaCe使用统一的缓存目录（防止生成大量临时缓存）
export DACE_cache_dir="/data/zq/evolve/.dace_cache"
mkdir -p "$DACE_cache_dir"

# 运行 OpenEvolve
python openevolve/openevolve-run.py \
  /data/zq/evolve/AlgoTune/AlgoTuneTasks/aes_gcm_encryption/aes_gcm_encryption.py \
  AlgoTune/evaluate.py \
  --config openevolve/configs/algotune_prompt.yaml \
  --primary-model o3 \
  --iterations 5 \
  --output results/aes_gcm_encryption
