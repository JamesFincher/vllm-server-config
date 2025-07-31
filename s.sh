#!/bin/bash
# Run this on your GPU instance after SSH-ing in

set -e

echo "=== Setting up Qwen3-480B with vLLM ==="

# 1. System setup
echo "Installing system dependencies..."
apt update && apt install -y python3-pip python3-venv git screen htop nvtop
ulimit -n 100000

# 2. Create venv and install vLLM
echo "Creating Python environment..."
python3 -m venv /opt/vllm
source /opt/vllm/bin/activate
pip install --upgrade pip
pip install -U vllm --torch-backend auto

# 3. Download model
echo "Downloading Qwen3-Coder-480B-FP8 model (60GB)..."
echo "This will take 10-15 minutes..."
python3 -c "
from huggingface_hub import snapshot_download
snapshot_download('Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8', 
                 local_dir='/models/qwen3',
                 local_dir_use_symlinks=False)"

# 4. Create start script
cat > /root/start_vllm.sh << 'EOF'
#!/bin/bash
source /opt/vllm/bin/activate
export VLLM_USE_DEEP_GEMM=1
export VLLM_API_KEY="${VLLM_API_KEY:-YOUR_API_KEY_HERE}"

echo "Starting vLLM with API key: $VLLM_API_KEY"
vllm serve /models/qwen3 \
    --enable-expert-parallel \
    --data-parallel-size 4 \
    --max-model-len 400000 \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.95
EOF

chmod +x /root/start_vllm.sh

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To start vLLM:"
echo "  screen -S vllm"
echo "  export VLLM_API_KEY='YOUR_API_KEY_HERE'"
echo "  /root/start_vllm.sh"
echo ""
echo "Then press Ctrl+A, D to detach"
