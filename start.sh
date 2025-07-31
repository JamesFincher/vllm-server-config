#!/bin/bash
# Complete startup script for Qwen3-480B on VM
# Run this on your VM: bash start_qwen3.sh

set -e

echo "=== Starting Qwen3-480B vLLM Server ==="

# 1. Clean up any existing screen sessions
echo "Cleaning up old sessions..."
screen -ls | grep vllm | cut -d. -f1 | awk '{print $1}' | xargs -I {} screen -S {}.vllm -X quit 2>/dev/null || true
pkill -f vllm || true

# 2. Activate virtual environment
echo "Activating Python environment..."
source /opt/vllm/bin/activate

# 3. Set environment variables
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export VLLM_USE_DEEP_GEMM=1
export VLLM_API_KEY='YOUR_API_KEY_HERE'

# 4. Create a startup script
cat > /root/vllm_server.sh << 'EOF'
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
EOF
chmod +x /root/vllm_server.sh

# 5. Start in screen
echo "Starting vLLM in screen session..."
screen -dmS vllm_server bash -c '/root/vllm_server.sh'

echo ""
echo "=== vLLM Server Starting ==="
echo "Model loading takes 5-10 minutes..."
echo ""
echo "Monitor progress:"
echo "  screen -r vllm_server     # Attach to screen"
echo "  tail -f /root/vllm.log    # Watch logs"
echo ""
echo "API will be available at: http://localhost:8000"
echo "API Key: YOUR_API_KEY_HERE"
