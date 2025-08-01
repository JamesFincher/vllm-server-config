#!/bin/bash
# vLLM Pipeline Parallelism Configuration
# Combines tensor and pipeline parallelism for optimal memory distribution
#
# Configuration:
# - Tensor Parallelism: 2 (splits model weights across 2 GPUs)
# - Pipeline Parallelism: 2 (distributes layers across 2 stages)
# - This configuration frees up memory for larger KV cache
# - Supports up to 760k context length (experimental)

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
LOG_FILE="/var/log/vllm/vllm_pipeline_$(date +%Y%m%d-%H%M%S).log"

echo "=== vLLM Pipeline Parallelism Configuration ==="
echo "Starting vLLM with Pipeline + Tensor Parallelism..."
echo "This distributes layers across GPUs to free memory for KV cache"
echo "Log file: $LOG_FILE"
echo ""

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
    2>&1 | tee $LOG_FILE
