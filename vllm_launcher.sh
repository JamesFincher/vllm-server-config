#!/bin/bash
source /opt/vllm/bin/activate

# Re-export all environment variables
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export VLLM_API_KEY='YOUR_API_KEY_HERE'
export NCCL_DEBUG=INFO
export CUDA_VISIBLE_DEVICES=0,1,2,3
export NCCL_P2P_DISABLE=0
export NCCL_IB_DISABLE=1
export NCCL_SOCKET_IFNAME=lo
export NCCL_ALGO=Tree
export NCCL_PROTO=Simple
export VLLM_FP8_E4M3_KV_CACHE=0
export VLLM_FP8_KV_CACHE=0

echo "Starting vLLM with optimized settings..."
echo "Model: Qwen3-Coder-480B-A35B-Instruct-FP8"
echo "Weights: FP8, KV Cache: FP16 (for quality)"
echo "Context: 760,000 tokens"
echo "GPUs: 4×H200"
echo ""

# Start vLLM with model as positional argument (new syntax)
vllm serve /models/qwen3 \
    --tensor-parallel-size 4 \
    --max-model-len 760000 \
    --kv-cache-dtype fp16 \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.92 \
    --max-num-seqs 256 \
    --swap-space 0 \
    --disable-log-requests \
    --trust-remote-code \
    --enable-chunked-prefill \
    --max-num-batched-tokens 32768 \
    2>&1 | tee /root/vllm.log
