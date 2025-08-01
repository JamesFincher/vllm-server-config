#!/bin/bash
# FP8 KV Cache Configuration - Aggressive Memory Optimization
# Uses FP8 quantized KV cache to maximize context length
#
# Configuration:
# - Tensor Parallelism: 4 (distributes across all GPUs)
# - KV Cache: FP8 quantized (may reduce quality)
# - Context Length: Up to 760,000 tokens
# - Memory Utilization: 95%
#
# WARNING: FP8 KV cache may degrade output quality
# Use only when maximum context length is required

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
LOG_FILE="/var/log/vllm/vllm_fp8_kv_$(date +%Y%m%d-%H%M%S).log"

echo "=== FP8 KV Cache Configuration ==="
echo "WARNING: Using FP8 KV cache - quality may degrade!"
echo "This configuration prioritizes maximum context length over quality"
echo "Context Length: Up to 760,000 tokens"
echo "Log file: $LOG_FILE"
echo ""

vllm serve /models/qwen3 \
    --tensor-parallel-size 4 \
    --max-model-len 760000 \
    --kv-cache-dtype fp8 \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.95 \
    --trust-remote-code \
    2>&1 | tee $LOG_FILE
