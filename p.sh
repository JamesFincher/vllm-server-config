#!/bin/bash
# Exact configuration to match nisten's 760k context setup
source /opt/vllm/bin/activate

# Kill any existing processes
pkill -f vllm
screen -wipe

# Critical environment variables from nisten's setup
export VLLM_API_KEY='YOUR_API_KEY_HERE'
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3

# FORCE KV cache to NOT be quantized (nisten's key insight)
export VLLM_FP8_E4M3_KV_CACHE=0
export VLLM_FP8_KV_CACHE=0
export VLLM_USE_V1=0  # Try using v0 engine which might handle memory differently

echo "=== Starting vLLM with nisten's exact config ==="
echo "Key settings:"
echo "- FP8 weights (already in model)"
echo "- KV cache: FORCED to fp16/bf16 (no quantization)"
echo "- Context: 760,000 tokens"
echo "- Engine: v0 (legacy, might work better)"

# Method 1: Try with v0 engine and forced settings
cat > /root/start_nisten_v0.sh << 'EOF'
#!/bin/bash
source /opt/vllm/bin/activate

export VLLM_API_KEY='YOUR_API_KEY_HERE'
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3
export VLLM_FP8_E4M3_KV_CACHE=0
export VLLM_FP8_KV_CACHE=0
export VLLM_USE_V1=0

vllm serve /models/qwen3 \
    --tensor-parallel-size 4 \
    --max-model-len 760000 \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.95 \
    --enforce-eager \
    --trust-remote-code \
    2>&1 | tee /root/vllm_nisten_v0.log
EOF

# Method 2: Try with different memory pool settings
cat > /root/start_nisten_pool.sh << 'EOF'
#!/bin/bash
source /opt/vllm/bin/activate

export VLLM_API_KEY='YOUR_API_KEY_HERE'
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3
export VLLM_FP8_E4M3_KV_CACHE=0
export VLLM_FP8_KV_CACHE=0

# Try with explicit memory settings
vllm serve /models/qwen3 \
    --tensor-parallel-size 4 \
    --max-model-len 760000 \
    --kv-cache-dtype auto \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.98 \
    --num-gpu-blocks-override 8192 \
    --trust-remote-code \
    2>&1 | tee /root/vllm_nisten_pool.log
EOF

# Method 3: Last resort - use FP8 KV cache but warn about quality
cat > /root/start_fp8_kv.sh << 'EOF'
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
EOF

chmod +x /root/start_nisten_*.sh /root/start_fp8_kv.sh

echo ""
echo "=== Three approaches to try: ==="
echo "1. v0 engine (legacy): ./start_nisten_v0.sh"
echo "2. Memory pool override: ./start_nisten_pool.sh"
echo "3. FP8 KV cache (not recommended): ./start_fp8_kv.sh"
echo ""
echo "Start with option 1 - it's most likely to match nisten's setup"
