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
cd /data/zq/evolve/AlgoTune
python3 /data/zq/evolve/AlgoTune/scripts/run_local_model.py aes_gcm_encryption /tmp/solver.py \
    --model-name openai/chatgptoss-20b \
    --api-base http://127.0.0.1:8010/v1 \
    --api-key dummy \
    --temperature 0.0 \
    --max-tokens 2048
