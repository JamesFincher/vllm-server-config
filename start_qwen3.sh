#!/bin/bash
source /opt/vllm/bin/activate

# Keep your existing environment variables
export VLLM_USE_V1=0
export VLLM_API_KEY='YOUR_API_KEY_HERE'
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3
export VLLM_TORCH_COMPILE_LEVEL=0

echo "Starting Qwen3-480B with simplified model name..."
vllm serve /models/qwen3 \
    --served-model-name qwen3 \
    --tensor-parallel-size 4 \
    --max-model-len 200000 \
    --host 0.0.0.0 \
    --port 8000 \
    --gpu-memory-utilization 0.95 \
    --enforce-eager \
    --trust-remote-code \
    2>&1 | tee /root/vllm_server.log