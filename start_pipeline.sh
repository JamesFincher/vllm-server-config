#!/bin/bash
source /opt/vllm/bin/activate
export VLLM_API_KEY='YOUR_API_KEY_HERE'
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3

echo "Starting vLLM with Pipeline + Tensor Parallelism..."
echo "This distributes layers across GPUs to free memory for KV cache"

vllm serve /models/qwen3 \
    --tensor-parallel-size 2 \
    --pipeline-parallel-size 2 \
    --max-model-len 760000 \
    --kv-cache-dtype fp8 \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.98 \
    --trust-remote-code \
    --swap-space 0 \
    2>&1 | tee /root/vllm_pipeline.log
