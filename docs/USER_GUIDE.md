# vLLM Qwen3-480B Server - Complete User Guide

## Table of Contents
1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Prerequisites](#prerequisites)
4. [Installation Guide](#installation-guide)
5. [Configuration Options](#configuration-options)
6. [API Usage Examples](#api-usage-examples)
7. [CRUSH Integration](#crush-integration)
8. [Performance Tuning](#performance-tuning)
9. [Troubleshooting](#troubleshooting)
10. [Monitoring and Maintenance](#monitoring-and-maintenance)
11. [Common Pitfalls](#common-pitfalls)
12. [FAQ](#faq)

---

## Overview

This repository provides a production-ready setup for running the **Qwen3-Coder-480B-A35B-Instruct-FP8** model using vLLM on high-end GPU hardware. The configuration has been extensively tested and optimized for:

- **Maximum context length**: 700,000 tokens (stable configuration)
- **Hardware**: 4x NVIDIA H200 GPUs (144GB VRAM each)
- **Performance**: ~15-20 tokens/second generation speed
- **Memory efficiency**: 98% GPU utilization with FP8 quantization

### Key Features
- ✅ **700k context length** - Process extremely long documents
- ✅ **Production tested** - Extensively validated configuration
- ✅ **Auto-recovery** - Built-in error handling and restart capabilities
- ✅ **CRUSH integration** - Ready for local AI development workflows
- ✅ **API compatible** - OpenAI-compatible REST API
- ✅ **Monitoring tools** - Comprehensive logging and system monitoring

---

## Quick Start

For users who want to get started immediately:

```bash
# 1. Clone and enter the repository
cd /path/to/vllm-server-config

# 2. Run automated setup (requires root access)
sudo ./setup.sh

# 3. Set your API key
export VLLM_API_KEY='your-secret-api-key-here'

# 4. Start the server with optimal configuration
./scripts/production/start_700k_final.sh

# 5. Test the server
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-secret-api-key-here" \
  -d '{
    "model": "qwen3",
    "messages": [{"role": "user", "content": "Hello, how are you?"}],
    "max_tokens": 100
  }'
```

**Expected startup time**: 5-10 minutes for model loading

---

## Prerequisites

### Hardware Requirements

| Component | Minimum | Recommended | Notes |
|-----------|---------|-------------|--------|
| **GPU** | 4x NVIDIA A100 80GB | 4x NVIDIA H200 144GB | H200 provides optimal performance |
| **CPU** | 32+ cores | AMD EPYC 9654 96-Core | High core count improves throughput |
| **RAM** | 500GB | 700GB+ | More RAM = better performance |
| **Storage** | 1TB NVMe | 2TB+ NVMe | Model requires ~450GB |
| **Network** | 10Gbps | 25Gbps+ | For model download and API access |

### Software Requirements

| Software | Version | Installation Method |
|----------|---------|-------------------|
| **Ubuntu** | 22.04.5 LTS | Fresh OS installation |
| **NVIDIA Driver** | 570.133.20+ | `setup.sh` handles this |
| **CUDA** | 12.6+ | Included with driver |
| **Python** | 3.10+ | System package |
| **Docker** | Latest | Optional, for containerized deployment |

### Network Configuration

```bash
# Required open ports
22/tcp    # SSH access
8000/tcp  # vLLM API endpoint

# Firewall setup (if needed)
sudo ufw allow 22/tcp
sudo ufw allow 8000/tcp
sudo ufw enable
```

---

## Installation Guide

### Method 1: Automated Installation (Recommended)

The provided `setup.sh` script handles the complete installation:

```bash
# Download the repository
git clone https://github.com/your-repo/vllm-server-config.git
cd vllm-server-config

# Make setup script executable
chmod +x setup.sh

# Run automated setup (requires root)
sudo ./setup.sh
```

**What the setup script does:**
1. Installs system packages and dependencies
2. Sets up NVIDIA drivers and CUDA
3. Creates Python virtual environment at `/opt/vllm`
4. Installs vLLM 0.10.0 and PyTorch 2.7.1
5. Downloads the Qwen3-480B model (optional prompt)
6. Configures system settings for optimal performance
7. Creates systemd service for auto-start

### Method 2: Manual Installation

If you prefer manual control or need to customize the installation:

#### Step 1: System Setup
```bash
# Update system packages
sudo apt-get update && sudo apt-get upgrade -y

# Install required packages
sudo apt-get install -y python3-pip python3-dev python3-venv \
  build-essential git wget curl vim screen htop nvtop
```

#### Step 2: NVIDIA Setup
```bash
# Download and install CUDA keyring
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt-get update

# Install CUDA toolkit
sudo apt-get install -y cuda-toolkit-12-8

# Verify installation
nvidia-smi
nvcc --version
```

#### Step 3: Python Environment
```bash
# Create virtual environment
sudo python3 -m venv /opt/vllm
source /opt/vllm/bin/activate

# Upgrade pip
pip install --upgrade pip

# Install PyTorch with CUDA support
pip install torch==2.7.1+cu126 --index-url https://download.pytorch.org/whl/cu126

# Install vLLM
pip install vllm==0.10.0

# Install additional dependencies
pip install huggingface-hub[hf_transfer]
```

#### Step 4: Model Download
```bash
# Create model directory
sudo mkdir -p /models/qwen3

# Download using huggingface-hub
python -c "
from huggingface_hub import snapshot_download
snapshot_download(
    'Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8',
    local_dir='/models/qwen3',
    local_dir_use_symlinks=False,
    resume_download=True
)
"
```

---

## Configuration Options

### Environment Variables

Set these variables before starting the server:

```bash
# Required
export VLLM_API_KEY='your-secret-api-key-here'      # API authentication
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1              # Enable extended context

# Optional optimizations
export CUDA_VISIBLE_DEVICES='0,1,2,3'               # GPUs to use
export NCCL_DEBUG=INFO                               # NCCL debugging
export VLLM_FP8_KV_CACHE=0                         # Disable FP8 KV cache for quality
```

### Server Configurations

#### Production Configuration (700k context - Recommended)
```bash
vllm serve /models/qwen3 \
    --tensor-parallel-size 2 \
    --pipeline-parallel-size 2 \
    --max-model-len 700000 \
    --kv-cache-dtype fp8 \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.98 \
    --trust-remote-code
```

#### Alternative Configurations

**Basic Configuration (Lower memory usage)**
```bash
vllm serve /models/qwen3 \
    --tensor-parallel-size 4 \
    --max-model-len 200000 \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.90 \
    --trust-remote-code
```

**High Context Configuration (Experimental - 760k)**
```bash
vllm serve /models/qwen3 \
    --tensor-parallel-size 4 \
    --max-model-len 760000 \
    --kv-cache-dtype auto \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.95 \
    --trust-remote-code
```

### Configuration Parameters Explained

| Parameter | Description | Recommended Value | Notes |
|-----------|-------------|-------------------|-------|
| `tensor-parallel-size` | Distribute model across GPUs | 2 or 4 | 2 for max context, 4 for speed |
| `pipeline-parallel-size` | Layer distribution | 2 | Enables longer context |
| `max-model-len` | Maximum context length | 700000 | Stable maximum |
| `kv-cache-dtype` | KV cache precision | fp8 or auto | fp8 saves memory, auto for quality |
| `gpu-memory-utilization` | GPU memory usage | 0.98 | Higher = more context |
| `trust-remote-code` | Allow model code execution | Required | Needed for Qwen3 |

---

## API Usage Examples

The server provides an OpenAI-compatible API. Here are practical examples:

### Basic Chat Completion

```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-api-key-here" \
  -d '{
    "model": "qwen3",
    "messages": [
      {"role": "user", "content": "Explain quantum computing in simple terms"}
    ],
    "max_tokens": 500,
    "temperature": 0.7
  }'
```

### Code Generation

```python
import requests

def generate_code(prompt, max_tokens=1000):
    url = "http://localhost:8000/v1/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer your-api-key-here"
    }
    data = {
        "model": "qwen3",
        "messages": [
            {"role": "system", "content": "You are an expert programmer."},
            {"role": "user", "content": prompt}
        ],
        "max_tokens": max_tokens,
        "temperature": 0.1
    }
    
    response = requests.post(url, json=data, headers=headers)
    return response.json()["choices"][0]["message"]["content"]

# Example usage
code = generate_code("Write a Python function to calculate fibonacci numbers")
print(code)
```

### Long Document Processing

```python
import requests

def process_long_document(document_text, question):
    """Process documents up to 700k tokens"""
    url = "http://localhost:8000/v1/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer your-api-key-here"
    }
    
    prompt = f"""
    Document:
    {document_text}
    
    Question: {question}
    
    Please analyze the document and answer the question.
    """
    
    data = {
        "model": "qwen3",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 2000,
        "temperature": 0.3
    }
    
    response = requests.post(url, json=data, headers=headers)
    return response.json()

# Example with very long document
with open("large_document.txt", "r") as f:
    document = f.read()  # Can be up to ~500k tokens
    
result = process_long_document(document, "What are the main conclusions?")
print(result["choices"][0]["message"]["content"])
```

### Streaming Responses

```python
import requests
import json

def stream_response(prompt):
    url = "http://localhost:8000/v1/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer your-api-key-here"
    }
    data = {
        "model": "qwen3",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 1000,
        "stream": True
    }
    
    response = requests.post(url, json=data, headers=headers, stream=True)
    
    for line in response.iter_lines():
        if line:
            line = line.decode('utf-8')
            if line.startswith('data: '):
                json_str = line[6:]  # Remove 'data: ' prefix
                if json_str != '[DONE]':
                    try:
                        data = json.loads(json_str)
                        content = data['choices'][0]['delta'].get('content', '')
                        if content:
                            print(content, end='', flush=True)
                    except json.JSONDecodeError:
                        pass

# Example usage
stream_response("Write a detailed explanation of machine learning")
```

---

## CRUSH Integration

CRUSH (Command Line AI Tool) integration allows seamless local AI development workflows.

### Setup CRUSH Configuration

The repository includes a pre-configured CRUSH config file:

```json
{
  "$schema": "https://charm.land/crush.json",
  "providers": {
    "vllm-local": {
      "type": "openai",
      "base_url": "http://localhost:8000/v1",
      "api_key": "YOUR_API_KEY_HERE",
      "models": [
        {
          "id": "qwen3",
          "name": "Qwen3-480B Local (700k context)",
          "context_window": 700000,
          "default_max_tokens": 8192,
          "cost_per_1m_in": 0,
          "cost_per_1m_out": 0
        }
      ]
    }
  },
  "default_provider": "vllm-local",
  "default_model": "qwen3"
}
```

### Installation and Setup

```bash
# 1. Install CRUSH (if not already installed)
curl -sSL https://install.charm.sh/crush | bash

# 2. Copy the configuration
cp configs/crush-config.json ~/.crush/config.json

# 3. Update API key in config
sed -i 's/YOUR_API_KEY_HERE/your-actual-api-key/' ~/.crush/config.json

# 4. Test the connection
crush "Hello from local Qwen3!"
```

### CRUSH Usage Examples

```bash
# Basic chat
crush "Explain how neural networks work"

# Code generation
crush "Write a Python script to parse JSON files"

# Long document analysis
crush -f large_document.txt "Summarize this document"

# Multi-turn conversation
crush --interactive

# Specific model selection (if you have multiple)
crush -m qwen3 "Complex coding question here"
```

### Advanced CRUSH Workflows

**Code Review Workflow:**
```bash
# Review code changes
git diff | crush "Review these code changes and suggest improvements"

# Generate commit messages
git diff --cached | crush "Generate a commit message for these changes"

# Code documentation
crush -f src/main.py "Generate comprehensive documentation for this code"
```

**Document Processing:**
```bash
# Process research papers
crush -f research_paper.pdf "Extract key findings and methodology"

# Meeting notes analysis
crush -f meeting_notes.txt "Create action items from these meeting notes"

# Contract analysis
crush -f contract.txt "Identify potential risks and key terms"
```

---

## Performance Tuning

### Hardware Optimization

**GPU Settings:**
```bash
# Enable persistence mode (reduces initialization time)
sudo nvidia-smi -pm 1

# Set maximum performance mode
sudo nvidia-smi -ac 9501,2619  # Adjust values for your GPU

# Monitor GPU topology
nvidia-smi topo -m
```

**System Tuning:**
```bash
# Disable CPU frequency scaling
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Increase network buffers
sudo sysctl -w net.core.rmem_max=134217728
sudo sysctl -w net.core.wmem_max=134217728

# Disable swap for consistent performance
sudo swapoff -a
```

### Memory Optimization

**Monitor Memory Usage:**
```bash
# GPU memory
nvidia-smi -l 1

# System memory
watch -n 1 'free -h'

# Process memory
ps aux --sort=-%mem | head -20
```

**Memory Tuning Options:**
```bash
# Reduce batch size for lower memory usage
--max-num-batched-tokens 8192

# Adjust KV cache block size
--block-size 16

# Enable CPU offloading (if needed)
--cpu-offload-gb 100
```

### Context Length vs Performance Trade-offs

| Context Length | Tensor Parallel | Pipeline Parallel | Memory Usage | Speed | Use Case |
|----------------|----------------|-------------------|--------------|-------|----------|
| 200k | 4 | 1 | ~85% | Fastest | General chat, coding |
| 400k | 4 | 1 | ~92% | Fast | Document analysis |
| 700k | 2 | 2 | ~98% | Medium | Long documents, research |
| 760k | 4 | 1 | ~99% | Slower | Maximum context needs |

### Benchmarking Commands

```bash
# Throughput test
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3",
    "messages": [{"role": "user", "content": "Count from 1 to 100"}],
    "max_tokens": 500
  }' \
  -w "Total time: %{time_total}s\n"

# Latency test
time curl -s -X POST http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 1
  }' > /dev/null
```

---

## Troubleshooting

### Common Issues and Solutions

#### 1. Server Won't Start

**Symptoms:** vLLM fails to start or crashes immediately

**Diagnostic Commands:**
```bash
# Check GPU availability
nvidia-smi

# Check CUDA installation
nvcc --version

# Check Python environment
source /opt/vllm/bin/activate
python -c "import vllm; import torch; print(f'vLLM: {vllm.__version__}, CUDA: {torch.cuda.is_available()}')"

# Check model files
ls -la /models/qwen3/
```

**Solutions:**
```bash
# Solution 1: Restart with minimal config
./scripts/experimental/start_basic.sh

# Solution 2: Check environment variables
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3

# Solution 3: Clear CUDA cache
python -c "import torch; torch.cuda.empty_cache()"
```

#### 2. Out of Memory Errors

**Error Messages:**
- "CUDA out of memory"
- "Cannot allocate GPU memory"

**Solutions:**
```bash
# Reduce context length
--max-model-len 400000

# Lower GPU memory utilization
--gpu-memory-utilization 0.85

# Use FP8 KV cache
--kv-cache-dtype fp8

# Enable pipeline parallelism
--pipeline-parallel-size 2
```

#### 3. Slow Performance

**Diagnostic:**
```bash
# Check GPU utilization
nvidia-smi -l 1

# Monitor network
iftop -i eth0

# Check system load
htop
```

**Optimizations:**
```bash
# Increase batch size
--max-num-batched-tokens 16384

# Optimize tensor parallelism
--tensor-parallel-size 4

# Enable efficient attention
--enforce-eager false
```

#### 4. API Connection Issues

**Symptoms:** Connection refused, timeout errors

**Diagnostic:**
```bash
# Check if server is running
ps aux | grep vllm

# Check port binding
netstat -tlnp | grep 8000

# Test local connection
curl http://localhost:8000/health
```

**Solutions:**
```bash
# Restart server
pkill -f vllm
./scripts/production/start_700k_final.sh

# Check firewall
sudo ufw status
sudo ufw allow 8000/tcp

# Verify API key
export VLLM_API_KEY='correct-api-key'
```

#### 5. Model Loading Issues

**Error Messages:**
- "Model not found"
- "Corrupted model files"

**Solutions:**
```bash
# Verify model path
ls -la /models/qwen3/config.json

# Re-download model (if corrupted)
rm -rf /models/qwen3
python /tmp/download_model.py

# Check disk space
df -h /models
```

### Advanced Debugging

**Enable Debug Logging:**
```bash
export VLLM_LOGGING_LEVEL=DEBUG
export NCCL_DEBUG=INFO
```

**Monitor System Resources:**
```bash
# Real-time GPU monitoring
watch -n 1 nvidia-smi

# Memory usage
watch -n 1 'free -h && echo "GPU:" && nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader'

# I/O monitoring
iostat -x 1

# Network monitoring
nethogs
```

**Log Analysis:**
```bash
# vLLM logs
tail -f /var/log/vllm/vllm-*.log

# System logs
journalctl -u vllm-server -f

# CUDA errors
dmesg | grep -i cuda
```

---

## Monitoring and Maintenance

### Real-time Monitoring

**GPU Monitoring Dashboard:**
```bash
# Install and run nvtop for GPU monitoring
sudo apt-get install nvtop
nvtop

# Or use nvidia-smi in watch mode
watch -n 1 nvidia-smi
```

**Server Health Check Script:**
```bash
#!/bin/bash
# Save as monitor_vllm.sh

check_server_health() {
    echo "=== vLLM Server Health Check ==="
    echo "Time: $(date)"
    echo
    
    # Check if process is running
    if pgrep -f vllm > /dev/null; then
        echo "✅ vLLM process is running"
    else
        echo "❌ vLLM process not found"
        return 1
    fi
    
    # Check API endpoint
    if curl -s http://localhost:8000/health > /dev/null; then
        echo "✅ API endpoint responding"
    else
        echo "❌ API endpoint not responding"
        return 1
    fi
    
    # Check GPU memory
    GPU_MEM=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
    echo "🔋 GPU Memory Used: ${GPU_MEM}MB"
    
    # Check system memory
    SYS_MEM=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    echo "💾 System Memory Used: ${SYS_MEM}%"
    
    echo "✅ Server health check passed"
}

check_server_health
```

### Automated Monitoring

**Set up monitoring with systemd timer:**
```bash
# Create monitoring script
sudo cp monitor_vllm.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/monitor_vllm.sh

# Create systemd service
sudo tee /etc/systemd/system/vllm-monitor.service << EOF
[Unit]
Description=vLLM Health Monitor
After=vllm-server.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/monitor_vllm.sh
EOF

# Create timer
sudo tee /etc/systemd/system/vllm-monitor.timer << EOF
[Unit]
Description=Run vLLM monitor every 5 minutes

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable vllm-monitor.timer
sudo systemctl start vllm-monitor.timer
```

### Log Management

**Log Rotation Configuration:**
```bash
sudo tee /etc/logrotate.d/vllm << EOF
/var/log/vllm/*.log {
    daily
    rotate 7
    compress
    delaycompress
    copytruncate
    notifempty
    missingok
}
EOF
```

**Log Analysis Commands:**
```bash
# Recent errors
grep -i error /var/log/vllm/vllm-*.log | tail -20

# Performance metrics
grep -i "tokens/s" /var/log/vllm/vllm-*.log | tail -10

# Memory usage patterns
grep -i "memory" /var/log/vllm/vllm-*.log | tail -10
```

### Backup and Recovery

**Model and Configuration Backup:**
```bash
#!/bin/bash
# backup_vllm.sh

BACKUP_DIR="/backup/vllm-$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# Backup configurations
cp -r /opt/vllm $BACKUP_DIR/vllm-env
cp -r configs/ $BACKUP_DIR/configs
cp -r scripts/ $BACKUP_DIR/scripts

# Backup important logs
cp /var/log/vllm/*.log $BACKUP_DIR/ 2>/dev/null || true

# Create backup info
echo "Backup created: $(date)" > $BACKUP_DIR/backup_info.txt
echo "vLLM version: $(source /opt/vllm/bin/activate && python -c 'import vllm; print(vllm.__version__)')" >> $BACKUP_DIR/backup_info.txt
echo "Model path: /models/qwen3" >> $BACKUP_DIR/backup_info.txt

echo "Backup completed: $BACKUP_DIR"
```

**Recovery Procedures:**
```bash
# Quick restart
sudo systemctl restart vllm-server

# Full recovery from backup
tar -xzf vllm-backup-20250731.tar.gz
sudo cp -r backup/vllm-env /opt/vllm
sudo cp -r backup/configs .
sudo systemctl restart vllm-server
```

---

## Common Pitfalls

### 1. Memory Management Pitfalls

**❌ Common Mistake:**
```bash
# Setting context too high without adequate GPU memory
--max-model-len 1000000  # Will cause OOM
```

**✅ Correct Approach:**
```bash
# Start with smaller context and increase gradually
--max-model-len 400000   # Test first
--max-model-len 600000   # Then increase
--max-model-len 700000   # Maximum stable
```

### 2. Environment Variable Issues

**❌ Common Mistake:**
```bash
# Forgetting to set required environment variables
vllm serve /models/qwen3  # Missing critical env vars
```

**✅ Correct Approach:**
```bash
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export VLLM_API_KEY='your-key'
export CUDA_VISIBLE_DEVICES=0,1,2,3
vllm serve /models/qwen3 --max-model-len 700000
```

### 3. API Key Security

**❌ Common Mistake:**
```bash
# Hardcoding API keys in scripts
--api-key "secret-key-123"  # Visible in process list
```

**✅ Correct Approach:**
```bash
# Use environment variables
export VLLM_API_KEY='secret-key-123'
--api-key $VLLM_API_KEY
```

### 4. Resource Monitoring

**❌ Common Mistake:**
```bash
# Starting server without monitoring resources
./start_vllm.sh && exit  # No monitoring
```

**✅ Correct Approach:**
```bash
# Monitor startup and resources
./start_vllm.sh &
watch -n 1 nvidia-smi  # Monitor GPU usage
tail -f /var/log/vllm/vllm-*.log  # Monitor logs
```

### 5. Configuration Conflicts

**❌ Common Mistake:**
```bash
# Mixing incompatible configurations
--tensor-parallel-size 4 --pipeline-parallel-size 2 --max-model-len 800000
# Total parallelism too high for context length
```

**✅ Correct Approach:**
```bash
# Use tested configurations
--tensor-parallel-size 2 --pipeline-parallel-size 2 --max-model-len 700000
# Or
--tensor-parallel-size 4 --max-model-len 400000
```

---

## FAQ

### General Questions

**Q: How long does it take to start the server?**
A: Model loading typically takes 5-10 minutes. The larger the context length, the longer the startup time.

**Q: Can I run multiple models simultaneously?**
A: No, the Qwen3-480B model uses all available GPU memory. You would need additional GPUs to run multiple models.

**Q: What's the maximum context length I can achieve?**
A: With 4x H200 GPUs, 700,000 tokens is the stable maximum. 760k is possible but may be unstable.

### Technical Questions

**Q: Why use FP8 quantization?**
A: FP8 quantization reduces memory usage by ~50% while maintaining acceptable quality for most use cases.

**Q: What's the difference between tensor and pipeline parallelism?**
A: 
- **Tensor parallelism**: Splits model weights across GPUs (faster inference)
- **Pipeline parallelism**: Splits model layers across GPUs (enables larger context)

**Q: How do I update to a newer vLLM version?**
A: 
```bash
source /opt/vllm/bin/activate
pip install --upgrade vllm
# Test thoroughly before production use
```

### Performance Questions

**Q: Why is generation slow for long contexts?**
A: Long contexts require more GPU memory for the KV cache, reducing available memory for computation batches.

**Q: How can I improve throughput?**
A: 
- Reduce context length if possible
- Increase `--max-num-batched-tokens`
- Use tensor parallelism instead of pipeline parallelism
- Ensure sufficient system RAM

**Q: What affects token generation speed?**
A: Key factors:
1. Context length (longer = slower)
2. Batch size (larger = more efficient)
3. GPU memory utilization
4. Model configuration (TP vs PP)

### Troubleshooting Questions

**Q: Server crashes with "NCCL error"**
A: This usually indicates GPU communication issues. Check:
```bash
nvidia-smi topo -m  # Verify GPU connectivity
export NCCL_DEBUG=INFO  # Enable debug logging
```

**Q: API requests timeout**
A: Common causes:
- Server still loading model (wait 5-10 minutes)
- Out of memory (reduce context or batch size)
- Network connectivity issues
- Incorrect API key

**Q: Model quality seems poor**
A: Try these optimizations:
- Disable FP8 KV cache: `--kv-cache-dtype auto`
- Reduce GPU memory utilization: `--gpu-memory-utilization 0.90`
- Check temperature settings in API calls

### Deployment Questions

**Q: Can I run this in Docker?**
A: Yes, but you'll need to:
- Use `--runtime=nvidia` 
- Mount GPU devices
- Configure shared memory properly
- Handle CUDA compatibility

**Q: How do I deploy this in production?**
A: Recommended setup:
- Use systemd service for auto-restart
- Set up log rotation
- Configure monitoring and alerting
- Use a reverse proxy (nginx) for HTTPS
- Implement API rate limiting

**Q: What about scaling to multiple servers?**
A: For horizontal scaling:
- Use a load balancer (HAProxy/nginx)
- Deploy identical configurations
- Consider model sharding for very large deployments
- Implement session affinity if needed

---

## Support and Resources

### Documentation Links
- [vLLM Official Documentation](https://vllm.readthedocs.io/)
- [Qwen3 Model Documentation](https://huggingface.co/Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8)
- [NVIDIA vLLM Guide](https://docs.nvidia.com/deeplearning/nemo/user-guide/docs/en/stable/nlp/nemo_megatron/vllm_deployment.html)

### Community Resources
- [vLLM GitHub Issues](https://github.com/vllm-project/vllm/issues)
- [CRUSH Documentation](https://charm.sh/crush)
- [NVIDIA Developer Forums](https://forums.developer.nvidia.com/)

### Getting Help
1. Check the troubleshooting section above
2. Review server logs for error messages
3. Search existing GitHub issues
4. Join the community Discord/Slack channels
5. Create detailed bug reports with system information

Remember to sanitize any sensitive information (API keys, IP addresses) when asking for help publicly.