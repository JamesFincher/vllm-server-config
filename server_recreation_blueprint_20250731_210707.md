# Complete Server Recreation Blueprint
Generated: $(date)

This document contains everything needed to recreate this exact server setup.

## Table of Contents
1. [Hardware Requirements](#hardware-requirements)
2. [Operating System](#operating-system)
3. [System Configuration](#system-configuration)
4. [GPU and CUDA Setup](#gpu-and-cuda-setup)
5. [Python Environment](#python-environment)
6. [Model Information](#model-information)
7. [vLLM Installation](#vllm-installation)
8. [Working Configurations](#working-configurations)
9. [Scripts and Tools](#scripts-and-tools)
10. [Reproduction Steps](#reproduction-steps)

## Hardware Requirements
```
CPU: AMD EPYC 9654 96-Core Processor
CPU Cores: 176
RAM: 718Gi

GPUs Required: 4x NVIDIA H200 (or equivalent with 144GB VRAM each)
index, name, memory.total [MiB]
0, NVIDIA H200, 143771 MiB
1, NVIDIA H200, 143771 MiB
2, NVIDIA H200, 143771 MiB
3, NVIDIA H200, 143771 MiB

Minimum Disk Space: 1TB (for OS + model)
Model Storage: ~450GB
```

## Operating System
```bash
# OS Installation
PRETTY_NAME="Ubuntu 22.04.5 LTS"
VERSION_ID="22.04"
Kernel: 5.15.0-139-generic

# Required OS packages
apt-get update
apt-get install -y python3-pip python3-dev build-essential git wget curl vim screen htop nvtop
```

## System Configuration
```bash
# Disable swap (important for performance)
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Set GPU persistence mode
nvidia-smi -pm 1

# System limits
echo '* soft nofile 65535' >> /etc/security/limits.conf
echo '* hard nofile 65535' >> /etc/security/limits.conf
```

## GPU and CUDA Setup
```bash
# NVIDIA Driver Version: 570.133.20
# CUDA Version: 12.8

# Install NVIDIA drivers (if not present)
# wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
# dpkg -i cuda-keyring_1.1-1_all.deb
# apt-get update
# apt-get install -y cuda-toolkit-12-8

# Verify installation
nvidia-smi
nvcc --version
```

## Python Environment
```bash
# Python version: Python 3.10.12

# Create vLLM environment
python3 -m venv /opt/vllm
source /opt/vllm/bin/activate

# Upgrade pip
pip install --upgrade pip

# Install PyTorch with CUDA 12.6
pip install torch==2.7.1+cu126 --index-url https://download.pytorch.org/whl/cu126

# Install vLLM and dependencies
pip install vllm==0.10.0

# Complete pip package list
# Save this for exact reproduction
pip install -r requirements.txt

# requirements.txt content:
aiohappyeyeballs==2.6.1
aiohttp==3.12.15
aiosignal==1.4.0
annotated-types==0.7.0
anyio==4.9.0
astor==0.8.1
async-timeout==5.0.1
attrs==25.3.0
blake3==1.0.5
cachetools==6.1.0
cbor2==5.6.5
certifi==2025.7.14
cffi==1.17.1
charset-normalizer==3.4.2
click==8.2.1
cloudpickle==3.1.1
compressed-tensors==0.10.2
cupy-cuda12x==13.5.1
depyf==0.19.0
dill==0.4.0
# ... (see /root/requirements_full.txt for complete list)
```

## Model Information
```bash
# Model: Qwen3-Coder-480B-A35B-Instruct-FP8
# Location: /models/qwen3
# Size: 450G

# Download model (using git-lfs or huggingface-cli)
mkdir -p /models
cd /models

# Option 1: Using git-lfs
git lfs install
git clone https://huggingface.co/Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8 qwen3

# Option 2: Using huggingface-cli
pip install huggingface-hub
huggingface-cli download Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8 --local-dir /models/qwen3

# Model files structure:
total 470870688
drwxr-xr-x 3 root root       4096 Jul 31 19:56 .
drwxr-xr-x 3 root root       4096 Jul 31 19:56 ..
drwxr-xr-x 3 root root       4096 Jul 31 19:02 .cache
-rw-r--r-- 1 root root       1570 Jul 31 19:02 .gitattributes
-rw-r--r-- 1 root root      11343 Jul 31 19:02 LICENSE
-rw-r--r-- 1 root root       6162 Jul 31 19:02 README.md
-rw-r--r-- 1 root root       6722 Jul 31 19:02 chat_template.jinja
-rw-r--r-- 1 root root       8971 Jul 31 19:02 config.json
-rw-r--r-- 1 root root        180 Jul 31 19:02 generation_config.json

# Model configuration:
# config.json excerpt:
{
  "model_type": "qwen3_moe",
  "hidden_size": 6144,
  "num_hidden_layers": 62,
  "num_attention_heads": 96,
  "max_position_embeddings": 262144,
  "vocab_size": 151936
}
```

## vLLM Installation
```bash
# vLLM version: 0.10.0
# Installation method:
pip install vllm==0.10.0

# Alternative: Install from source
# git clone https://github.com/vllm-project/vllm.git
# cd vllm
# git checkout v0.10.0
# pip install -e .

# Verify installation
python -c 'import vllm; print(vllm.__version__)'
```

## Working Configurations

### Configuration Results Summary
| Config | Max Context | Memory Used | Status |
|--------|-------------|-------------|---------|
| TP=4 | ~92k | Standard | ❌ Too small |
| TP=4 + FP8 KV | ~421k | FP8 KV cache | ❌ Still too small |
| TP=2 + PP=2 + FP8 KV | ~707k | FP8 KV cache | ✅ Close to target |
| TP=2 + PP=2 + FP8 KV + 0.98 util | 760k | FP8 KV cache | ❌ 1.54 GiB short |

### Best Working Configuration (700k context)
```bash
vllm serve /models/qwen3 \
    --tensor-parallel-size 2 \
    --pipeline-parallel-size 2 \
    --max-model-len 700000 \
    --kv-cache-dtype fp8 \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key YOUR_API_KEY_HERE \
    --gpu-memory-utilization 0.98 \
    --trust-remote-code
```

## Scripts and Tools

### All Created Scripts
#### fp.sh
```bash
#!/bin/bash
# Complete Server Recreation Fingerprint Script
# This script captures EVERYTHING needed to recreate this exact server setup

OUTPUT_FILE="/root/server_recreation_blueprint_$(date +%Y%m%d_%H%M%S).md"

cat > "$OUTPUT_FILE" << 'HEADER'
# Complete Server Recreation Blueprint
Generated: $(date)

This document contains everything needed to recreate this exact server setup.

HEADER

# Function to append to output
log() {
    echo "$1" | tee -a "$OUTPUT_FILE"
}

log "## Table of Contents"
# ... (truncated)
```

#### p.sh
```bash
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
# ... (truncated)
```

#### s.sh
```bash
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
# ... (truncated)
```

#### so.sh
```bash
omprehensive vLLM Debug and Start Script
# This will diagnose issues and try multiple approaches

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== vLLM Comprehensive Debug & Start Script ===${NC}"
echo "Time is money - let's fix this quickly!"
echo ""

# Function to print section headers
section() {
	    echo ""
	        echo -e "${YELLOW}>>> $1${NC}"
		    echo "----------------------------------------"
# ... (truncated)
```

#### start.sh
```bash
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
# ... (truncated)
```

#### start2.sh
```bash
#!/bin/bash
# Fix vLLM server based on nisten's configuration
# Run on remote server: ssh to it first with ./db.sh ssh

echo "=== Fixing vLLM for Qwen3-480B (FP8 weights, FP16 KV cache) ==="

# 1. Clean up crashed processes
pkill -f vllm || true
screen -ls | grep vllm | cut -d. -f1 | awk '{print $1}' | xargs -I {} screen -S {}.vllm -X quit 2>/dev/null || true

# 2. Create optimized vLLM startup script
cat > /root/start_vllm_optimized.sh << 'EOF'
#!/bin/bash
set -e

echo "=== Starting Qwen3-480B with nisten's configuration ==="
echo "Key: FP8 weights, FP16 KV cache, 760k context"

# Clean environment
pkill -f vllm || true
# ... (truncated)
```

#### start_700k_final.sh
```bash
#!/bin/bash
source /opt/vllm/bin/activate
export VLLM_API_KEY='YOUR_API_KEY_HERE'
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3

echo "Starting with 700k context - the maximum stable configuration"
vllm serve /models/qwen3 \
    --tensor-parallel-size 2 \
    --pipeline-parallel-size 2 \
    --max-model-len 700000 \
    --kv-cache-dtype fp8 \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.98 \
    --trust-remote-code \
    2>&1 | tee /root/vllm_700k_final.log
# ... (truncated)
```

#### start_basic.sh
```bash
								#!/bin/bash
								source /opt/vllm/bin/activate
								export VLLM_API_KEY='YOUR_API_KEY_HERE'

								echo "Starting vLLM with minimal options..."
								vllm serve /models/qwen3 \
									    --host 0.0.0.0 \
									        --port 8000 \
										    --api-key $VLLM_API_KEY \
										        2>&1 | tee /root/vllm_basic.log
								EOF

								# Script 2: Tensor Parallel (most likely to work)
								cat > /root/start_tensor_parallel.sh << 'EOF'
#!/bin/bash
source /opt/vllm/bin/activate
export VLLM_API_KEY='YOUR_API_KEY_HERE'
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3

# ... (truncated)
```

#### start_fp8_kv.sh
```bash
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
# ... (truncated)
```

#### start_nisten_pool.sh
```bash
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
# ... (truncated)
```

#### start_nisten_v0.sh
```bash
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
# ... (truncated)
```

#### start_now.sh
```bash
#!/bin/bash
source /opt/vllm/bin/activate
export VLLM_API_KEY='YOUR_API_KEY_HERE'
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3

echo "Starting vLLM (correct syntax, auto KV cache)..."
echo "Model: Qwen3-480B"
echo "GPUs: 4xH200"
echo ""

# MODEL PATH AS POSITIONAL ARGUMENT - NO --model FLAG!
vllm serve /models/qwen3 \
    --tensor-parallel-size 4 \
    --max-model-len 760000 \
    --kv-cache-dtype auto \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.90 \
# ... (truncated)
```

#### start_optimized.sh
```bash
#!/bin/bash
source /opt/vllm/bin/activate
export VLLM_API_KEY='YOUR_API_KEY_HERE'
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3
export VLLM_FP8_E4M3_KV_CACHE=0
export VLLM_FP8_KV_CACHE=0

echo "Starting vLLM with optimized settings (FP16 KV cache)..."
vllm serve /models/qwen3 \
	    --tensor-parallel-size 4 \
	        --max-model-len 760000 \
		    --kv-cache-dtype fp16 \
		        --host 0.0.0.0 \
			    --port 8000 \
			        --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.90 \
    --trust-remote-code \
    2>&1 | tee /root/vllm_optimized.log
# ... (truncated)
```

#### start_pipeline.sh
```bash
#!/bin/bash
source /opt/vllm/bin/activate
export VLLM_API_KEY='YOUR_API_KEY_HERE'
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3

echo "Starting vLLM with Pipeline + Tensor Parallelism..."
echo "This distributes layers across GPUs to free memory for KV cache"

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
# ... (truncated)
```

#### start_vllm.sh
```bash
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
# ... (truncated)
```

#### start_vllm_optimized.sh
```bash
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
# ... (truncated)
```

#### start_working.sh
```bash
#!/bin/bash
source /opt/vllm/bin/activate
export VLLM_API_KEY='YOUR_API_KEY_HERE'
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3

# Ensure KV cache is NOT quantized
export VLLM_FP8_E4M3_KV_CACHE=0
export VLLM_FP8_KV_CACHE=0

echo "Starting vLLM with auto KV cache (no quantization)..."
vllm serve /models/qwen3 \
    --tensor-parallel-size 4 \
    --max-model-len 760000 \
    --kv-cache-dtype auto \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.90 \
    --trust-remote-code \
# ... (truncated)
```

#### system_check.sh
```bash
#!/bin/bash

echo "=== Python Environment Check ==="
source /opt/vllm/bin/activate

echo "Python packages related to vLLM and ML:"
pip list | grep -E "vllm|torch|transformers|numpy|cuda|flash|triton|xformers" | sort

echo -e "\n=== vLLM Installation Details ==="
python -c "
import vllm
import os
print(f'vLLM version: {vllm.__version__}')
print(f'vLLM location: {vllm.__file__}')
print(f'vLLM install dir: {os.path.dirname(vllm.__file__)}')
"

echo -e "\n=== Model Details ==="
echo "Model directory contents:"
ls -lah /models/qwen3/ | head -20
# ... (truncated)
```

#### t.sh
```bash
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
# ... (truncated)
```

#### u.sh
```bash
SH to server
ssh -i ~/.ssh/your-ssh-key -p 22 root@YOUR_SERVER_IP

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
# ... (truncated)
```

#### v.sh
```bash
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
# ... (truncated)
```

#### vllm_launcher.sh
```bash
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
# ... (truncated)
```

#### vllm_server.sh
```bash
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
# ... (truncated)
```

### SSH Tunnel Script (for local machine)
```bash
#!/bin/bash
# Save as connect.sh on your local machine
SSH_KEY="$HOME/.ssh/your-key"
SERVER_IP="YOUR_SERVER_IP"
ssh -i "$SSH_KEY" -N -L 8000:localhost:8000 root@"$SERVER_IP" &
```

## Reproduction Steps

### Step-by-Step Setup
```bash
# 1. Provision server with 4x H200 GPUs (or 4x A100 80GB minimum)

# 2. Install Ubuntu 22.04 LTS

# 3. Run system updates
apt-get update && apt-get upgrade -y

# 4. Install NVIDIA drivers and CUDA
# Follow NVIDIA installation guide for your specific GPU

# 5. Create Python environment
python3 -m venv /opt/vllm
source /opt/vllm/bin/activate

# 6. Install packages
pip install torch==2.7.1+cu126 --index-url https://download.pytorch.org/whl/cu126
pip install vllm==0.10.0

# 7. Download model
mkdir -p /models
cd /models
# Use huggingface-cli or git-lfs as shown above

# 8. Start vLLM with 700k context
# Use the working configuration shown above
```

## Environment Variables
```bash
CUDA_VISIBLE_DEVICES=0,1,2,3
PATH=/opt/vllm/bin:/opt/vllm/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin
VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
VLLM_API_KEY=YOUR_API_KEY_HERE
```

## Network Configuration
```bash
# Open ports
ufw allow 22/tcp  # SSH
ufw allow 8000/tcp  # vLLM API

# Current network interfaces
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    inet 127.0.0.1/8 scope host lo
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9100 qdisc fq_codel state UP group default qlen 1000
    inet YOUR_SERVER_IP/32 metric 100 scope global eth0
3: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default 
    inet 172.17.0.1/16 brd 172.17.255.255 scope global docker0
```

## Troubleshooting

### Common Issues and Solutions
1. **Out of Memory**: Reduce max_model_len or use more pipeline stages
2. **NCCL Errors**: Check GPU visibility with CUDA_VISIBLE_DEVICES
3. **Connection Refused**: Ensure vLLM is fully loaded (takes 5-10 min)
4. **Import Errors**: Activate venv with 'source /opt/vllm/bin/activate'

## Final Notes

- Model loading takes 5-10 minutes
- FP8 KV cache reduces quality slightly but enables longer context
- Pipeline parallelism adds latency but enables larger context
- 700k tokens is the practical maximum with this hardware
- For 760k+ context, you need more GPU memory or different model

### Cost Optimization
- Keep model loaded to avoid repeated loading time
- Use --max-num-seqs to limit concurrent requests
- Monitor GPU usage with 'nvidia-smi' or 'nvtop'

## Additional Files Saved
- /root/requirements_full.txt - Complete pip package list
- /root/server_recreation_blueprint_*.md - This document
- /root/quick_setup.sh - Quick start script for vLLM

