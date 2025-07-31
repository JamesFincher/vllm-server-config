#!/bin/bash
source /opt/vllm/bin/activate
export VLLM_API_KEY='YOUR_API_KEY_HERE'
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3

echo "Starting vLLM (correct syntax, auto KV cache)..."
echo "Model: Qwen3-480B"
echo "GPUs: 4xH200"
echo ""

# MODEL PATH AS POSITIONAL ARGUMENT - NO --model FLAG!
vllm serve /models/qwen3 \
    --tensor-parallel-size 4 \
    --max-model-len 760000 \
    --kv-cache-dtype auto \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.90 \
    --trust-remote-code \
    2>&1 | tee /root/vllm_now.log
