#!/bin/bash
source /opt/vllm/bin/activate
export VLLM_API_KEY='YOUR_API_KEY_HERE'
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3

# Ensure KV cache is NOT quantized
export VLLM_FP8_E4M3_KV_CACHE=0
export VLLM_FP8_KV_CACHE=0

echo "Starting vLLM with auto KV cache (no quantization)..."
vllm serve /models/qwen3 \
    --tensor-parallel-size 4 \
    --max-model-len 760000 \
    --kv-cache-dtype auto \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.90 \
    --trust-remote-code \
    2>&1 | tee /root/vllm_working.log
