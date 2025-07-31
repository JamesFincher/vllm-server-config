wtart script with the required environment variable
cat > /root/start_vllm.sh << 'EOF'
#!/bin/bash
source /opt/vllm/bin/activate

# Required for extended context beyond model's default
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export VLLM_USE_DEEP_GEMM=1
export VLLM_API_KEY="${VLLM_API_KEY:-YOUR_API_KEY_HERE}"

echo "Starting vLLM server..."
echo "Model: Qwen3-Coder-480B-A35B-Instruct-FP8"
echo "Context: 760,000 tokens (like @nisten)"
echo "Weights: FP8 quantized"
echo "KV Cache: 16-bit (NOT quantized)"
echo "API Key: $VLLM_API_KEY"

vllm serve /models/qwen3 \
    --enable-expert-parallel \
    --data-parallel-size 4 \
    --max-model-len 760000 \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.95
EOF

chmod +x /root/start_vllm.sh

# Start vLLM with 760k context
screen -S vllm
export VLLM_API_KEY='YOUR_API_KEY_HERE'
/root/start_vllm.sh
