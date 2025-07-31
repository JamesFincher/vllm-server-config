#!/bin/bash
source /opt/vllm/bin/activate

export VLLM_API_KEY='YOUR_API_KEY_HERE'
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3

echo "WARNING: Using FP8 KV cache - quality may degrade!"
echo "This goes against nisten's recommendation but might be necessary"

vllm serve /models/qwen3 \
    --tensor-parallel-size 4 \
    --max-model-len 760000 \
    --kv-cache-dtype fp8 \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.95 \
    --trust-remote-code \
    2>&1 | tee /root/vllm_fp8_kv.log
