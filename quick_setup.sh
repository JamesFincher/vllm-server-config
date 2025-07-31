#!/bin/bash
# Quick setup script for vLLM with Qwen3-480B
source /opt/vllm/bin/activate
export VLLM_API_KEY='YOUR_API_KEY_HERE'
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3

vllm serve /models/qwen3 \
    --tensor-parallel-size 2 \
    --pipeline-parallel-size 2 \
    --max-model-len 700000 \
    --kv-cache-dtype fp8 \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.98 \
    --trust-remote-code
