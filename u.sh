SH to server
ssh -i ~/.ssh/qwen3-deploy-20250731-114902 -p 22 root@86.38.238.64

# Update the start script with 760k context
cat > /root/start_vllm.sh << 'EOF'
#!/bin/bash
source /opt/vllm/bin/activate
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
    --gpu-memory-utilization 0.95 \
    --dtype float16
EOF

chmod +x /root/start_vllm.sh

# Restart vLLM with new settings
screen -r vllm
# Ctrl+C to stop current instance
export VLLM_API_KEY='YOUR_API_KEY_HERE'
/root/start_vllm.sh
# Ctrl+A, D to detach

