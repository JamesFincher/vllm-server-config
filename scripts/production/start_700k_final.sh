#!/bin/bash
# vLLM 700k Context Configuration - Maximum Stable Setup
# Optimized for Qwen3-480B with 4x H200 GPUs
#
# This configuration represents the maximum stable context length achieved
# through extensive testing with tensor parallelism and pipeline parallelism.
#
# Configuration:
# - Tensor Parallelism: 2 (splits model across 2 GPUs)
# - Pipeline Parallelism: 2 (layers distributed across 2 stages)
# - KV Cache: FP8 quantized for memory efficiency
# - Context Length: 700,000 tokens (maximum stable)
# - GPU Memory Utilization: 98%

set -e

# Check required environment variables
if [[ -z "$VLLM_API_KEY" ]]; then
    echo "Error: VLLM_API_KEY environment variable must be set"
    echo "Example: export VLLM_API_KEY='your-secret-key'"
    exit 1
fi

# Activate virtual environment
if [[ ! -f "/opt/vllm/bin/activate" ]]; then
    echo "Error: vLLM virtual environment not found at /opt/vllm"
    echo "Please run the setup script first"
    exit 1
fi
source /opt/vllm/bin/activate

# Set environment variables
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-"0,1,2,3"}

# Create log directory
mkdir -p /var/log/vllm
LOG_FILE="/var/log/vllm/vllm_700k_$(date +%Y%m%d-%H%M%S).log"

echo "=== vLLM 700k Context Configuration ==="
echo "Model: Qwen3-Coder-480B-A35B-Instruct-FP8"
echo "Context Length: 700,000 tokens (MAXIMUM STABLE)"
echo "Memory optimization: FP8 KV cache, Pipeline parallelism"
echo "Performance: TP=2, PP=2, GPU utilization 98%"
echo "Log file: $LOG_FILE"
echo ""

vllm serve /models/qwen3 \
    --tensor-parallel-size 2 \
    --pipeline-parallel-size 2 \
    --max-model-len 700000 \
    --kv-cache-dtype fp8 \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.98 \
    --trust-remote-code \
    2>&1 | tee $LOG_FILE
