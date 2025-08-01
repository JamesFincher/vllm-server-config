# Complete Installation Guide - vLLM Qwen3-480B Server

## Table of Contents
1. [System Requirements](#system-requirements)
2. [Pre-Installation Checklist](#pre-installation-checklist)
3. [Automated Installation](#automated-installation)
4. [Manual Installation](#manual-installation)
5. [Post-Installation Setup](#post-installation-setup)
6. [Verification and Testing](#verification-and-testing)
7. [Configuration Options](#configuration-options)
8. [Troubleshooting Installation](#troubleshooting-installation)
9. [Alternative Installation Methods](#alternative-installation-methods)
10. [Uninstallation Guide](#uninstallation-guide)

---

## System Requirements

### Minimum Hardware Requirements

| Component | Minimum | Recommended | Notes |
|-----------|---------|-------------|-------|
| **GPU** | 4x NVIDIA A100 80GB | 4x NVIDIA H200 144GB | H200 provides optimal performance |
| **CPU** | 32 cores | 64+ cores (AMD EPYC preferred) | High core count improves throughput |
| **RAM** | 512GB | 700GB+ | More RAM enables larger contexts |
| **Storage** | 1TB NVMe SSD | 2TB+ NVMe SSD | Model requires ~450GB |
| **Network** | 1Gbps | 10Gbps+ | For model download and API access |
| **Power** | 3000W | 4000W+ | Includes UPS recommendation |

### Software Requirements

| Software | Version | Required | Notes |
|----------|---------|----------|-------|
| **Ubuntu** | 22.04.5 LTS | Yes | Other Linux distros may work but untested |
| **Python** | 3.10+ | Yes | 3.11+ recommended |
| **NVIDIA Driver** | 570.133.20+ | Yes | Supports CUDA 12.6+ |
| **CUDA** | 12.6+ | Yes | Included with modern drivers |
| **Git** | 2.0+ | Yes | For model and code management |
| **Docker** | 20.10+ | Optional | For containerized deployment |

### Network Requirements

```bash
# Required ports
22/tcp     # SSH access
8000/tcp   # vLLM API endpoint

# Bandwidth requirements
# Model download: ~450GB (one-time)
# API usage: Minimal (local processing)

# DNS requirements
# Access to huggingface.co for model download
# Access to PyPI for package installation
```

---

## Pre-Installation Checklist

### 1. Hardware Verification

```bash
#!/bin/bash
# hardware_check.sh - Verify hardware requirements

echo "=== Hardware Requirements Check ==="

# Check CPU cores
cpu_cores=$(nproc)
echo "CPU Cores: $cpu_cores"
if [ $cpu_cores -lt 32 ]; then
    echo "⚠️  Warning: Less than 32 CPU cores detected"
else
    echo "✅ CPU cores sufficient"
fi

# Check RAM
ram_gb=$(free -g | awk '/^Mem:/{print $2}')
echo "System RAM: ${ram_gb}GB"
if [ $ram_gb -lt 512 ]; then
    echo "❌ Error: Insufficient RAM (need 512GB+)"
    exit 1
else
    echo "✅ RAM sufficient"
fi

# Check GPUs
if command -v nvidia-smi &> /dev/null; then
    gpu_count=$(nvidia-smi --list-gpus | wc -l)
    echo "GPU Count: $gpu_count"
    
    if [ $gpu_count -lt 4 ]; then
        echo "❌ Error: Need at least 4 GPUs"
        exit 1
    else
        echo "✅ GPU count sufficient"
    fi
    
    # Check GPU memory
    echo "GPU Memory Details:"
    nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader,nounits | while read line; do
        gpu_mem=$(echo $line | cut -d',' -f3)
        gpu_name=$(echo $line | cut -d',' -f2)
        echo "  GPU $(echo $line | cut -d',' -f1): $gpu_name - ${gpu_mem}MB"
        
        if [ $gpu_mem -lt 75000 ]; then  # 75GB minimum
            echo "  ⚠️  Warning: GPU memory may be insufficient"
        fi
    done
else
    echo "❌ Error: nvidia-smi not found"
    exit 1
fi

# Check storage
available_space=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
echo "Available Storage: ${available_space}GB"
if [ $available_space -lt 1000 ]; then
    echo "❌ Error: Need at least 1TB free space"
    exit 1
else
    echo "✅ Storage sufficient"
fi

echo "✅ Hardware requirements check passed"
```

### 2. Software Prerequisites

```bash
#!/bin/bash
# prereq_check.sh - Check software prerequisites

echo "=== Software Prerequisites Check ==="

# Check OS version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "OS: $PRETTY_NAME"
    
    if [[ "$ID" != "ubuntu" ]] || [[ "${VERSION_ID%.*}" -lt 22 ]]; then
        echo "⚠️  Warning: Ubuntu 22.04+ recommended"
    else
        echo "✅ OS version compatible"
    fi
else
    echo "⚠️  Warning: Cannot determine OS version"
fi

# Check Python version
if command -v python3 &> /dev/null; then
    python_version=$(python3 --version | cut -d' ' -f2)
    echo "Python: $python_version"
    
    python_major=$(echo $python_version | cut -d'.' -f1)
    python_minor=$(echo $python_version | cut -d'.' -f2)
    
    if [ $python_major -eq 3 ] && [ $python_minor -ge 10 ]; then
        echo "✅ Python version compatible"
    else
        echo "❌ Error: Python 3.10+ required"
        exit 1
    fi
else
    echo "❌ Error: Python3 not found"
    exit 1
fi

# Check NVIDIA driver
if command -v nvidia-smi &> /dev/null; then
    driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -1)
    echo "NVIDIA Driver: $driver_version"
    echo "✅ NVIDIA driver detected"
else
    echo "❌ Error: NVIDIA driver not found"
    exit 1
fi

# Check CUDA
if command -v nvcc &> /dev/null; then
    cuda_version=$(nvcc --version | grep "release" | sed 's/.*release \([0-9.]*\).*/\1/')
    echo "CUDA: $cuda_version"
    echo "✅ CUDA toolkit detected"
else
    echo "⚠️  Warning: CUDA toolkit not found (will be installed)"
fi

# Check internet connectivity
if ping -c 1 google.com &> /dev/null; then
    echo "✅ Internet connectivity available"
else
    echo "❌ Error: No internet connectivity"
    exit 1
fi

echo "✅ Software prerequisites check passed"
```

### 3. Permissions and Access

```bash
#!/bin/bash
# permissions_check.sh - Verify required permissions

echo "=== Permissions Check ==="

# Check sudo access
if sudo -n true 2>/dev/null; then
    echo "✅ Sudo access available"
else
    echo "❌ Error: Sudo access required"
    exit 1
fi

# Check write permissions for installation directories
for dir in /opt /models /var/log; do
    if sudo test -w "$dir" 2>/dev/null || sudo mkdir -p "$dir" 2>/dev/null; then
        echo "✅ Write access to $dir"
    else
        echo "❌ Error: Cannot write to $dir"
        exit 1
    fi
done

# Check if ports are available
for port in 8000; do
    if ! ss -tuln | grep ":$port " > /dev/null; then
        echo "✅ Port $port available"
    else
        echo "⚠️  Warning: Port $port in use"
    fi
done

echo "✅ Permissions check passed"
```

---

## Automated Installation

### Using the Setup Script (Recommended)

The repository includes a comprehensive setup script that handles the entire installation process:

```bash
# 1. Clone the repository
git clone https://github.com/your-repo/vllm-qwen3-server.git
cd vllm-qwen3-server

# 2. Run hardware and software checks
./scripts/prereq_check.sh

# 3. Execute automated installation
sudo ./setup.sh

# 4. Follow the prompts for model download and configuration
```

### What the Setup Script Does

The `setup.sh` script performs these actions:

1. **System Package Installation**
   - Updates package repositories
   - Installs Python, build tools, and dependencies
   - Configures system settings

2. **NVIDIA Driver Setup**
   - Installs CUDA toolkit if needed
   - Configures GPU settings
   - Sets persistence mode

3. **Python Environment Creation**
   - Creates virtual environment at `/opt/vllm`
   - Installs PyTorch with CUDA support
   - Installs vLLM and dependencies

4. **Model Download**
   - Downloads Qwen3-480B model (~450GB)
   - Verifies model integrity
   - Sets up model directory structure

5. **System Configuration**
   - Optimizes kernel parameters
   - Sets up systemd service
   - Configures logging

6. **Security Setup**
   - Generates default API key
   - Sets up firewall rules
   - Configures access controls

### Installation Progress Monitoring

```bash
#!/bin/bash
# monitor_installation.sh - Monitor setup progress

tail -f /var/log/vllm/setup.log &
LOG_PID=$!

# Monitor system resources during installation
while pgrep -f "setup.sh" > /dev/null; do
    echo "=== Installation Progress ==="
    echo "Time: $(date)"
    echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')"
    echo "Memory Usage: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
    echo "Disk Usage: $(df -h / | awk 'NR==2 {print $3 "/" $2}')"
    
    if pgrep -f "download" > /dev/null; then
        echo "Status: Downloading model..."
    elif pgrep -f "pip install" > /dev/null; then
        echo "Status: Installing Python packages..."
    else
        echo "Status: System configuration..."
    fi
    
    echo "========================"
    sleep 30
done

kill $LOG_PID 2>/dev/null
echo "Installation monitoring complete"
```

---

## Manual Installation

For users who prefer step-by-step manual installation or need custom configurations:

### Step 1: System Preparation

```bash
# Update system packages
sudo apt-get update && sudo apt-get upgrade -y

# Install essential packages
sudo apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    build-essential \
    git \
    wget \
    curl \
    vim \
    screen \
    htop \
    nvtop \
    software-properties-common

# Install additional utilities
sudo apt-get install -y \
    tree \
    jq \
    unzip \
    lsof \
    net-tools
```

### Step 2: NVIDIA Driver and CUDA Installation

```bash
# Remove any existing NVIDIA packages
sudo apt-get remove --purge nvidia-* -y
sudo apt-get autoremove -y

# Add NVIDIA repository
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt-get update

# Install CUDA toolkit (includes drivers)
sudo apt-get install -y cuda-toolkit-12-8

# Add CUDA to PATH
echo 'export PATH=/usr/local/cuda/bin:$PATH' | sudo tee -a /etc/environment
echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' | sudo tee -a /etc/environment

# Reload environment
source /etc/environment

# Verify installation
nvidia-smi
nvcc --version
```

### Step 3: Python Environment Setup

```bash
# Create vLLM directory
sudo mkdir -p /opt/vllm
sudo chown $USER:$USER /opt/vllm

# Create virtual environment
python3 -m venv /opt/vllm
source /opt/vllm/bin/activate

# Upgrade pip
pip install --upgrade pip setuptools wheel

# Install PyTorch with CUDA support
pip install torch==2.7.1+cu126 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126

# Verify PyTorch CUDA support
python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"
python -c "import torch; print(f'CUDA devices: {torch.cuda.device_count()}')"
```

### Step 4: vLLM Installation

```bash
# Ensure virtual environment is active
source /opt/vllm/bin/activate

# Install vLLM
pip install vllm==0.10.0

# Install additional dependencies
pip install huggingface-hub[hf_transfer]
pip install transformers
pip install accelerate

# Verify vLLM installation
python -c "import vllm; print(f'vLLM version: {vllm.__version__}')"
```

### Step 5: Model Download

```bash
# Create model directory
sudo mkdir -p /models/qwen3
sudo chown $USER:$USER /models/qwen3

# Activate environment
source /opt/vllm/bin/activate

# Method 1: Using huggingface-hub (recommended)
python -c "
from huggingface_hub import snapshot_download
import os

model_id = 'Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8'
local_dir = '/models/qwen3'

print(f'Downloading {model_id}...')
print('This will download approximately 450GB')

# Enable fast downloads
os.environ['HF_HUB_ENABLE_HF_TRANSFER'] = '1'

snapshot_download(
    repo_id=model_id,
    local_dir=local_dir,
    local_dir_use_symlinks=False,
    resume_download=True
)

print('Download complete!')
"

# Method 2: Using git-lfs (alternative)
# cd /models
# git lfs install
# git clone https://huggingface.co/Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8 qwen3

# Verify model files
ls -la /models/qwen3/
du -sh /models/qwen3/
```

### Step 6: System Configuration

```bash
# Disable swap for better performance
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Set GPU persistence mode
sudo nvidia-smi -pm 1

# Increase file descriptor limits
echo '* soft nofile 65535' | sudo tee -a /etc/security/limits.conf
echo '* hard nofile 65535' | sudo tee -a /etc/security/limits.conf

# Optimize network settings
sudo tee -a /etc/sysctl.conf << EOF

# vLLM optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
EOF

# Apply sysctl changes
sudo sysctl -p
```

### Step 7: Create Start Scripts

```bash
# Create production start script
sudo tee /opt/vllm/start_production.sh << 'EOF'
#!/bin/bash
# Production vLLM startup script

source /opt/vllm/bin/activate

# Environment variables
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export VLLM_API_KEY="${VLLM_API_KEY:-your-api-key-here}"
export CUDA_VISIBLE_DEVICES=0,1,2,3

# Start vLLM with optimal settings
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
    2>&1 | tee /var/log/vllm/production.log
EOF

sudo chmod +x /opt/vllm/start_production.sh
```

### Step 8: Systemd Service Setup

```bash
# Create systemd service file
sudo tee /etc/systemd/system/vllm-server.service << EOF
[Unit]
Description=vLLM Server for Qwen3-480B
After=network.target nvidia-persistenced.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/vllm
Environment=CUDA_VISIBLE_DEVICES=0,1,2,3
Environment=VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
Environment=VLLM_API_KEY=your-api-key-here
ExecStart=/opt/vllm/bin/python -m vllm.entrypoints.openai.api_server \
    --model /models/qwen3 \
    --tensor-parallel-size 2 \
    --pipeline-parallel-size 2 \
    --max-model-len 700000 \
    --kv-cache-dtype fp8 \
    --host 0.0.0.0 \
    --port 8000 \
    --gpu-memory-utilization 0.98 \
    --trust-remote-code
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=mixed
Restart=on-failure
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
sudo systemctl daemon-reload
sudo systemctl enable vllm-server
```

### Step 9: Logging Setup

```bash
# Create log directory
sudo mkdir -p /var/log/vllm
sudo chown $USER:$USER /var/log/vllm

# Configure log rotation
sudo tee /etc/logrotate.d/vllm << EOF
/var/log/vllm/*.log {
    daily
    rotate 7
    compress
    delaycompress
    copytruncate
    notifempty
    missingok
    create 644 root root
}
EOF
```

---

## Post-Installation Setup

### 1. Environment Configuration

```bash
# Create environment setup script
cat > /opt/vllm/setup_env.sh << 'EOF'
#!/bin/bash
# vLLM Environment Setup

# Activate virtual environment
source /opt/vllm/bin/activate

# Set environment variables
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3

# Optional optimizations
export NCCL_DEBUG=WARN
export VLLM_FP8_KV_CACHE=0  # Set to 1 to enable FP8 KV cache

# Add to PATH if needed
export PATH=/opt/vllm/bin:$PATH

echo "vLLM environment configured"
echo "Virtual environment: $(which python)"
echo "CUDA devices: $CUDA_VISIBLE_DEVICES"
EOF

chmod +x /opt/vllm/setup_env.sh
```

### 2. API Key Configuration

```bash
# Generate secure API key
API_KEY=$(openssl rand -hex 32)

# Set in environment
echo "export VLLM_API_KEY='$API_KEY'" >> ~/.bashrc

# Update systemd service
sudo sed -i "s/your-api-key-here/$API_KEY/g" /etc/systemd/system/vllm-server.service

# Reload systemd
sudo systemctl daemon-reload

echo "API Key generated: $API_KEY"
echo "Make sure to save this key securely!"
```

### 3. Firewall Configuration

```bash
# Configure UFW firewall
sudo ufw allow ssh
sudo ufw allow 8000/tcp
sudo ufw --force enable

# Verify firewall status
sudo ufw status
```

### 4. Create Utility Scripts

```bash
# Server management script
sudo tee /usr/local/bin/vllm-manage << 'EOF'
#!/bin/bash
# vLLM Server Management Script

case "$1" in
    start)
        echo "Starting vLLM server..."
        sudo systemctl start vllm-server
        ;;
    stop)
        echo "Stopping vLLM server..."
        sudo systemctl stop vllm-server
        ;;
    restart)
        echo "Restarting vLLM server..."
        sudo systemctl restart vllm-server
        ;;
    status)
        sudo systemctl status vllm-server
        ;;
    logs)
        sudo journalctl -u vllm-server -f
        ;;
    health)
        curl -s http://localhost:8000/health || echo "Server not responding"
        ;;
    test)
        curl -X POST http://localhost:8000/v1/chat/completions \
          -H "Authorization: Bearer $VLLM_API_KEY" \
          -H "Content-Type: application/json" \
          -d '{"model": "qwen3", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 10}'
        ;;
    *)
        echo "Usage: vllm-manage {start|stop|restart|status|logs|health|test}"
        exit 1
        ;;
esac
EOF

sudo chmod +x /usr/local/bin/vllm-manage
```

---

## Verification and Testing

### 1. Installation Verification

```bash
#!/bin/bash
# verify_installation.sh - Comprehensive installation verification

echo "=== vLLM Installation Verification ==="

# Check Python environment
echo "1. Python Environment:"
source /opt/vllm/bin/activate
python --version
which python

# Check vLLM installation
echo -e "\n2. vLLM Installation:"
python -c "import vllm; print(f'vLLM version: {vllm.__version__}')"

# Check PyTorch and CUDA
echo -e "\n3. PyTorch and CUDA:"
python -c "import torch; print(f'PyTorch version: {torch.__version__}')"
python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"
python -c "import torch; print(f'CUDA devices: {torch.cuda.device_count()}')"

# Check model files
echo -e "\n4. Model Files:"
if [ -f /models/qwen3/config.json ]; then
    echo "✅ Model config found"
    model_size=$(du -sh /models/qwen3 | cut -f1)
    echo "✅ Model size: $model_size"
else
    echo "❌ Model config not found"
fi

# Check GPU status
echo -e "\n5. GPU Status:"
nvidia-smi --query-gpu=index,name,memory.total,driver_version --format=csv,noheader

# Check system service
echo -e "\n6. System Service:"
if systemctl is-enabled vllm-server &>/dev/null; then
    echo "✅ Systemd service enabled"
else
    echo "⚠️  Systemd service not enabled"
fi

# Check network connectivity
echo -e "\n7. Network Test:"
if ss -tuln | grep ":8000 " &>/dev/null; then
    echo "⚠️  Port 8000 already in use"
else
    echo "✅ Port 8000 available"
fi

echo -e "\n=== Verification Complete ==="
```

### 2. Startup Test

```bash
#!/bin/bash
# startup_test.sh - Test server startup

echo "=== Server Startup Test ==="

# Set API key if not set
if [ -z "$VLLM_API_KEY" ]; then
    export VLLM_API_KEY="test-key-$(date +%s)"
    echo "Using temporary API key: $VLLM_API_KEY"
fi

# Start server in background
echo "Starting vLLM server..."
source /opt/vllm/setup_env.sh

vllm serve /models/qwen3 \
    --tensor-parallel-size 2 \
    --pipeline-parallel-size 2 \
    --max-model-len 200000 \
    --kv-cache-dtype fp8 \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.90 \
    --trust-remote-code &

SERVER_PID=$!

echo "Server started with PID: $SERVER_PID"
echo "Waiting for server to initialize..."

# Wait for server to be ready
timeout=600  # 10 minutes
counter=0

while [ $counter -lt $timeout ]; do
    if curl -s http://localhost:8000/health > /dev/null 2>&1; then
        echo "✅ Server is responding!"
        break
    fi
    
    echo "Waiting... ($counter/$timeout seconds)"
    sleep 10
    counter=$((counter + 10))
done

if [ $counter -ge $timeout ]; then
    echo "❌ Server failed to start within timeout"
    kill $SERVER_PID
    exit 1
fi

# Test API endpoint
echo "Testing API endpoint..."
response=$(curl -s -X POST http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3",
    "messages": [{"role": "user", "content": "Hello, testing!"}],
    "max_tokens": 50
  }')

if echo "$response" | grep -q "choices"; then
    echo "✅ API test successful!"
    echo "Response preview: $(echo "$response" | jq -r '.choices[0].message.content' 2>/dev/null | head -c 50)..."
else
    echo "❌ API test failed"
    echo "Response: $response"
fi

# Cleanup
echo "Stopping test server..."
kill $SERVER_PID
wait $SERVER_PID 2>/dev/null

echo "=== Startup Test Complete ==="
```

### 3. Performance Benchmark

```bash
#!/bin/bash
# performance_benchmark.sh - Basic performance test

echo "=== Performance Benchmark ==="

# Start server if not running
if ! curl -s http://localhost:8000/health > /dev/null; then
    echo "Server not running. Please start the server first."
    exit 1
fi

# Set API key
if [ -z "$VLLM_API_KEY" ]; then
    echo "Please set VLLM_API_KEY environment variable"
    exit 1
fi

echo "Running performance tests..."

# Test 1: Latency test
echo "1. Latency Test (first token time):"
start_time=$(date +%s.%N)
curl -s -X POST http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3",
    "messages": [{"role": "user", "content": "Hi"}],
    "max_tokens": 1
  }' > /dev/null
end_time=$(date +%s.%N)

latency=$(echo "$end_time - $start_time" | bc)
echo "   First token latency: ${latency}s"

# Test 2: Throughput test
echo "2. Throughput Test (100 tokens):"
start_time=$(date +%s.%N)
response=$(curl -s -X POST http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3",
    "messages": [{"role": "user", "content": "Count from 1 to 50"}],
    "max_tokens": 100
  }')
end_time=$(date +%s.%N)

total_time=$(echo "$end_time - $start_time" | bc)
total_tokens=$(echo "$response" | jq -r '.usage.total_tokens' 2>/dev/null || echo "unknown")
if [ "$total_tokens" != "unknown" ]; then
    tokens_per_sec=$(echo "scale=2; $total_tokens / $total_time" | bc)
    echo "   Total tokens: $total_tokens"
    echo "   Total time: ${total_time}s"
    echo "   Throughput: ${tokens_per_sec} tokens/s"
else
    echo "   Could not determine token count"
fi

# Test 3: Memory usage
echo "3. GPU Memory Usage:"
nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits | \
while read line; do
    used=$(echo $line | cut -d',' -f1)
    total=$(echo $line | cut -d',' -f2)
    usage_percent=$(echo "scale=1; $used * 100 / $total" | bc)
    echo "   GPU Memory: ${used}MB / ${total}MB (${usage_percent}%)"
done

echo "=== Benchmark Complete ==="
```

---

## Configuration Options

### Environment Variables

```bash
# Core settings
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1      # Enable extended context
export VLLM_API_KEY="your-secure-api-key"   # API authentication
export CUDA_VISIBLE_DEVICES="0,1,2,3"       # GPU selection

# Performance tuning
export VLLM_FP8_KV_CACHE=0                  # KV cache quantization (0=disabled, 1=enabled)
export VLLM_USE_V1=1                        # Engine version (0=v0, 1=v1)
export NCCL_DEBUG=WARN                      # NCCL logging level

# Memory management
export PYTORCH_CUDA_ALLOC_CONF="max_split_size_mb:512"
export CUDA_LAUNCH_BLOCKING=0               # CUDA kernel launching

# Network optimization
export NCCL_P2P_DISABLE=0                  # P2P communication
export NCCL_IB_DISABLE=1                   # InfiniBand (disable if not available)
```

### Configuration Profiles

Create different configuration profiles for various use cases:

```bash
# ~/.vllm/profiles/high_speed.env
export VLLM_TENSOR_PARALLEL_SIZE=4
export VLLM_PIPELINE_PARALLEL_SIZE=1
export VLLM_MAX_MODEL_LEN=200000
export VLLM_GPU_MEMORY_UTILIZATION=0.90
export VLLM_KV_CACHE_DTYPE="auto"

# ~/.vllm/profiles/high_context.env
export VLLM_TENSOR_PARALLEL_SIZE=2
export VLLM_PIPELINE_PARALLEL_SIZE=2
export VLLM_MAX_MODEL_LEN=700000
export VLLM_GPU_MEMORY_UTILIZATION=0.98
export VLLM_KV_CACHE_DTYPE="fp8"

# ~/.vllm/profiles/balanced.env
export VLLM_TENSOR_PARALLEL_SIZE=4
export VLLM_PIPELINE_PARALLEL_SIZE=1
export VLLM_MAX_MODEL_LEN=400000
export VLLM_GPU_MEMORY_UTILIZATION=0.95
export VLLM_KV_CACHE_DTYPE="fp8"
```

### Server Configuration Templates

```bash
# Production configuration
cat > /opt/vllm/configs/production.json << 'EOF'
{
  "model": "/models/qwen3",
  "tensor_parallel_size": 2,
  "pipeline_parallel_size": 2,
  "max_model_len": 700000,
  "gpu_memory_utilization": 0.98,
  "kv_cache_dtype": "fp8",
  "host": "0.0.0.0",
  "port": 8000,
  "trust_remote_code": true,
  "max_num_batched_tokens": 4096,
  "max_num_seqs": 8
}
EOF

# Development configuration
cat > /opt/vllm/configs/development.json << 'EOF'
{
  "model": "/models/qwen3",
  "tensor_parallel_size": 4,
  "pipeline_parallel_size": 1,
  "max_model_len": 200000,
  "gpu_memory_utilization": 0.85,
  "kv_cache_dtype": "auto",
  "host": "0.0.0.0",
  "port": 8000,
  "trust_remote_code": true,
  "max_num_batched_tokens": 8192,
  "max_num_seqs": 16
}
EOF
```

---

## Troubleshooting Installation

### Common Installation Issues

#### 1. CUDA Installation Problems

**Symptoms:**
- `nvidia-smi` command not found
- CUDA version mismatch
- Driver installation failures

**Solutions:**
```bash
# Remove conflicting drivers
sudo apt-get remove --purge '^nvidia-.*' -y
sudo apt-get remove --purge '^libnvidia-.*' -y
sudo apt-get remove --purge '^cuda-.*' -y

# Clean package database
sudo apt-get autoremove -y
sudo apt-get autoclean

# Reinstall from scratch
sudo ubuntu-drivers autoinstall
sudo reboot

# Or install specific version
sudo apt-get install nvidia-driver-545 cuda-toolkit-12-6
```

#### 2. Python Environment Issues

**Symptoms:**
- Import errors
- Package conflicts
- Permission errors

**Solutions:**
```bash
# Recreate virtual environment
sudo rm -rf /opt/vllm
sudo mkdir -p /opt/vllm
sudo chown $USER:$USER /opt/vllm
python3 -m venv /opt/vllm

# Install with specific versions
source /opt/vllm/bin/activate
pip install --upgrade pip==23.3.1
pip install torch==2.7.1+cu126 --index-url https://download.pytorch.org/whl/cu126
pip install vllm==0.10.0 --no-deps
pip install -r requirements_full.txt
```

#### 3. Model Download Issues

**Symptoms:**
- Download timeouts
- Corrupted files
- Authentication errors

**Solutions:**
```bash
# Set up authentication (if needed)
huggingface-cli login

# Enable resume downloads
export HF_HUB_ENABLE_HF_TRANSFER=1

# Download with retry
python -c "
import time
from huggingface_hub import snapshot_download

for attempt in range(3):
    try:
        snapshot_download(
            'Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8',
            local_dir='/models/qwen3',
            resume_download=True
        )
        break
    except Exception as e:
        print(f'Attempt {attempt + 1} failed: {e}')
        time.sleep(60)
"
```

#### 4. Memory and Resource Issues

**Symptoms:**
- Out of memory during installation
- System becomes unresponsive
- Installation hangs

**Solutions:**
```bash
# Monitor resources during installation
watch -n 5 'free -h && df -h && nvidia-smi'

# Reduce parallel downloads
export HF_DATASETS_CACHE="/tmp/huggingface"

# Increase swap temporarily (if needed)
sudo fallocate -l 32G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### Installation Log Analysis

```bash
#!/bin/bash
# analyze_installation_logs.sh

echo "=== Installation Log Analysis ==="

# System logs
echo "1. System Installation Logs:"
sudo grep -i "vllm\|cuda\|nvidia" /var/log/dpkg.log | tail -20

# Package installation logs
echo -e "\n2. Package Installation Status:"
dpkg -l | grep -E "nvidia|cuda|python3"

# Service logs
echo -e "\n3. Service Logs:"
sudo journalctl -u vllm-server --no-pager | tail -20

# Python package logs
echo -e "\n4. Python Package Status:"
source /opt/vllm/bin/activate
pip list | grep -E "vllm|torch|transformers"

# GPU status
echo -e "\n5. GPU Status:"
nvidia-smi --query-gpu=index,name,driver_version,memory.total --format=csv

echo -e "\n=== Analysis Complete ==="
```

---

## Alternative Installation Methods

### Docker Installation

```dockerfile
# Dockerfile for vLLM Qwen3-480B
FROM nvidia/cuda:12.6-devel-ubuntu22.04

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    git \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create vLLM environment
RUN python3 -m venv /opt/vllm
ENV PATH="/opt/vllm/bin:$PATH"

# Install PyTorch and vLLM
RUN pip install --upgrade pip
RUN pip install torch==2.7.1+cu126 --index-url https://download.pytorch.org/whl/cu126
RUN pip install vllm==0.10.0

# Set up model directory
RUN mkdir -p /models/qwen3

# Copy model files (assumes model is downloaded)
COPY models/qwen3/ /models/qwen3/

# Expose port
EXPOSE 8000

# Set environment variables
ENV VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
ENV CUDA_VISIBLE_DEVICES=0,1,2,3

# Start command
CMD ["vllm", "serve", "/models/qwen3", \
     "--tensor-parallel-size", "2", \
     "--pipeline-parallel-size", "2", \
     "--max-model-len", "700000", \
     "--kv-cache-dtype", "fp8", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--gpu-memory-utilization", "0.98", \
     "--trust-remote-code"]
```

```bash
# Build and run Docker container
docker build -t vllm-qwen3 .
docker run --gpus all -p 8000:8000 \
  -e VLLM_API_KEY="your-api-key" \
  -v /models/qwen3:/models/qwen3:ro \
  vllm-qwen3
```

### Conda Installation

```bash
# Create conda environment
conda create -n vllm python=3.10 -y
conda activate vllm

# Install PyTorch with CUDA
conda install pytorch torchvision torchaudio pytorch-cuda=12.6 -c pytorch -c nvidia

# Install vLLM from pip (not available in conda)
pip install vllm==0.10.0

# Install additional dependencies
conda install -c huggingface transformers tokenizers
pip install huggingface-hub[hf_transfer]
```

### Distributed Installation

For multi-server deployments:

```bash
#!/bin/bash
# distributed_install.sh - Install on multiple servers

SERVERS=("server1.example.com" "server2.example.com" "server3.example.com")
SSH_KEY="~/.ssh/id_rsa"

for server in "${SERVERS[@]}"; do
    echo "Installing on $server..."
    
    # Copy installation files
    scp -i $SSH_KEY setup.sh user@$server:/tmp/
    
    # Run installation
    ssh -i $SSH_KEY user@$server "sudo /tmp/setup.sh"
    
    # Verify installation
    ssh -i $SSH_KEY user@$server "nvidia-smi && python3 -c 'import vllm; print(vllm.__version__)'"
done

echo "Distributed installation complete"
```

---

## Uninstallation Guide

### Complete Removal

```bash
#!/bin/bash
# uninstall_vllm.sh - Complete vLLM removal

echo "=== vLLM Uninstallation ==="

# Stop and disable service
sudo systemctl stop vllm-server
sudo systemctl disable vllm-server
sudo rm -f /etc/systemd/system/vllm-server.service
sudo systemctl daemon-reload

# Remove Python environment
sudo rm -rf /opt/vllm

# Remove model files (optional - comment out to keep)
# sudo rm -rf /models/qwen3

# Remove log files
sudo rm -rf /var/log/vllm

# Remove utility scripts
sudo rm -f /usr/local/bin/vllm-manage

# Remove systemd configuration
sudo rm -f /etc/systemd/system/vllm-server.service

# Remove logrotate configuration
sudo rm -f /etc/logrotate.d/vllm

# Remove from PATH (manual removal from shell config needed)
echo "Please manually remove vLLM entries from ~/.bashrc or ~/.profile"

# Revert system changes (optional)
read -p "Revert system optimizations? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo sed -i '/vLLM optimizations/,+4d' /etc/sysctl.conf
    sudo sysctl -p
fi

echo "=== Uninstallation Complete ==="
echo "Note: NVIDIA drivers and CUDA toolkit were not removed"
echo "Note: Model files were preserved (if you want to remove them: sudo rm -rf /models/qwen3)"
```

### Partial Removal (Keep Models)

```bash
#!/bin/bash
# partial_uninstall.sh - Remove vLLM but keep models

# Stop service
sudo systemctl stop vllm-server
sudo systemctl disable vllm-server

# Remove Python environment only
sudo rm -rf /opt/vllm

# Remove service configuration
sudo rm -f /etc/systemd/system/vllm-server.service
sudo systemctl daemon-reload

echo "vLLM removed, models preserved in /models/qwen3"
```

---

This comprehensive installation guide covers all aspects of setting up the vLLM Qwen3-480B server, from initial requirements checking through complete deployment and testing. Choose the installation method that best fits your environment and requirements.