#!/bin/bash
# Basic vLLM Configuration - Minimal Options
# For systems with lower memory requirements or initial testing
#
# Configuration:
# - No tensor parallelism (single GPU mode)
# - Minimal parameters for maximum compatibility
# - Suitable for initial testing and debugging

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

# Create log directory
mkdir -p /var/log/vllm
LOG_FILE="/var/log/vllm/vllm_basic_$(date +%Y%m%d-%H%M%S).log"

echo "=== Basic vLLM Configuration ==="
echo "Starting vLLM with minimal options..."
echo "Configuration: Single GPU, default settings"
echo "Log file: $LOG_FILE"
echo ""

vllm serve /models/qwen3 \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --trust-remote-code \
    2>&1 | tee $LOG_FILE
