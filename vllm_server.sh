#!/bin/bash
source /opt/vllm/bin/activate
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export VLLM_USE_DEEP_GEMM=1
export VLLM_API_KEY='YOUR_API_KEY_HERE'

echo "Starting vLLM..."
echo "Model: Qwen3-Coder-480B-A35B-Instruct-FP8 (FP8 weights, FP16 KV cache)"
echo "Context: 760,000 tokens"
echo "GPUs: 4×H200"
echo "API endpoint: http://0.0.0.0:8000"
echo "API key: $VLLM_API_KEY"
echo ""

vllm serve /models/qwen3 \
    --enable-expert-parallel \
    --data-parallel-size 4 \
    --max-model-len 760000 \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.95 \
    2>&1 | tee /root/vllm.log
