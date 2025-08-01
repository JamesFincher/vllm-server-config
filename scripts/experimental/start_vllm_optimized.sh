#!/bin/bash
set -e

echo "=== Starting Qwen3-480B with nisten's configuration ==="
echo "Key: FP8 weights, FP16 KV cache, 760k context"

# Clean environment
pkill -f vllm || true
screen -wipe 2>/dev/null || true

# Activate vLLM environment
source /opt/vllm/bin/activate

# Critical environment variables
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export VLLM_API_KEY='YOUR_API_KEY_HERE'

# NCCL settings for H200 GPUs
export NCCL_DEBUG=INFO
export CUDA_VISIBLE_DEVICES=0,1,2,3
export NCCL_P2P_DISABLE=0
export NCCL_IB_DISABLE=1
export NCCL_SOCKET_IFNAME=lo
export NCCL_ALGO=Tree
export NCCL_PROTO=Simple

# Force FP16 KV cache (CRITICAL for quality)
export VLLM_FP8_E4M3_KV_CACHE=0
export VLLM_FP8_KV_CACHE=0

# Create launcher script
cat > /root/vllm_launcher.sh << 'LAUNCHER'
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

# Start vLLM with tensor parallelism (more stable than data parallelism)
vllm serve /models/qwen3 \
    --model Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8 \
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
LAUNCHER

chmod +x /root/vllm_launcher.sh

# Start in screen
echo "Starting vLLM in screen session..."
screen -dmS vllm_server bash -c '/root/vllm_launcher.sh'

echo ""
echo "=== vLLM Server Starting ==="
echo "This implements nisten's configuration:"
echo "- FP8 quantized weights (already in model)"
echo "- FP16 KV cache (--kv-cache-dtype fp16)"
echo "- 760k context window"
echo "- Optimized for 50M+ tokens/hour throughput"
echo ""
echo "Monitor: screen -r vllm_server"
echo "Logs: tail -f /root/vllm.log"
echo ""
echo "Model loading takes 5-10 minutes..."
