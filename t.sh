# 1. Make sure you're in the venv
source /opt/vllm/bin/activate

# 2. Install vLLM (the key package)
pip install vllm

# 3. Download the model (this takes 10-15 minutes)
python3 -c "
from huggingface_hub import snapshot_download
print('Downloading Qwen3-Coder-480B-FP8 model (60GB)...')
snapshot_download('Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8', 
                 local_dir='/models/qwen3',
                 local_dir_use_symlinks=False,
                 resume_download=True)
print('Download complete!')
"

# 4. Create the start script
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

# 5. Start vLLM in screen
screen -S vllm
export VLLM_API_KEY='YOUR_API_KEY_HERE'
/root/start_vllm.sh
