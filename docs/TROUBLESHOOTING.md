# vLLM Qwen3-480B Troubleshooting Guide

## Table of Contents
1. [Quick Diagnostics](#quick-diagnostics)
2. [Server Startup Issues](#server-startup-issues)
3. [Memory and Performance Issues](#memory-and-performance-issues)
4. [API and Connection Issues](#api-and-connection-issues)
5. [Model Loading Problems](#model-loading-problems)
6. [Hardware and Driver Issues](#hardware-and-driver-issues)
7. [Configuration Problems](#configuration-problems)
8. [Debugging Tools and Commands](#debugging-tools-and-commands)
9. [Recovery Procedures](#recovery-procedures)
10. [Performance Optimization](#performance-optimization)

---

## Quick Diagnostics

### Essential Health Check Commands

Run these commands first to get an overview of system status:

```bash
#!/bin/bash
# quick_health_check.sh - Run this first when troubleshooting

echo "=== Quick vLLM Health Check ==="
echo "Timestamp: $(date)"
echo

# 1. Check if vLLM process is running
echo "1. Process Status:"
if pgrep -f vllm > /dev/null; then
    echo "   ✅ vLLM process running (PID: $(pgrep -f vllm))"
    ps aux | grep vllm | grep -v grep
else
    echo "   ❌ vLLM process not running"
fi
echo

# 2. Check GPU status
echo "2. GPU Status:"
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv,noheader
else
    echo "   ❌ nvidia-smi not available"
fi
echo

# 3. Check API endpoint
echo "3. API Status:"
if curl -s --connect-timeout 5 http://localhost:8000/health > /dev/null 2>&1; then
    echo "   ✅ API endpoint responding"
else
    echo "   ❌ API endpoint not responding"
fi
echo

# 4. Check disk space
echo "4. Disk Space:"
df -h /models 2>/dev/null || df -h /
echo

# 5. Check memory usage
echo "5. Memory Usage:"
free -h
echo

# 6. Check recent logs
echo "6. Recent Errors (last 5):"
if [ -f /var/log/vllm/vllm-*.log ]; then
    tail -50 /var/log/vllm/vllm-*.log | grep -i error | tail -5
else
    echo "   No vLLM logs found"
fi
echo

echo "=== Health Check Complete ==="
```

### Immediate Actions Checklist

When vLLM isn't working, follow this checklist:

- [ ] **Process Running?** `pgrep -f vllm`
- [ ] **GPUs Visible?** `nvidia-smi`
- [ ] **Model Files Present?** `ls -la /models/qwen3/config.json`
- [ ] **Environment Active?** `source /opt/vllm/bin/activate`
- [ ] **API Key Set?** `echo $VLLM_API_KEY`
- [ ] **Port Available?** `netstat -tlnp | grep 8000`
- [ ] **Recent Logs?** `tail -20 /var/log/vllm/vllm-*.log`

---

## Server Startup Issues

### Issue: Server Won't Start

**Symptoms:**
- vLLM command exits immediately
- "Command not found" errors
- Import errors on startup

**Diagnostic Commands:**
```bash
# Check if vLLM is properly installed
source /opt/vllm/bin/activate
python -c "import vllm; print(f'vLLM version: {vllm.__version__}')"

# Check CUDA availability
python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"

# Verify model path
ls -la /models/qwen3/

# Check environment variables
env | grep VLLM
```

**Solutions:**

1. **Reinstall vLLM:**
```bash
source /opt/vllm/bin/activate
pip uninstall vllm -y
pip install vllm==0.10.0
```

2. **Fix Python Environment:**
```bash
# Recreate virtual environment if corrupted
sudo rm -rf /opt/vllm
sudo python3 -m venv /opt/vllm
source /opt/vllm/bin/activate
pip install --upgrade pip
pip install torch==2.7.1+cu126 --index-url https://download.pytorch.org/whl/cu126
pip install vllm==0.10.0
```

3. **Check Model Files:**
```bash
# Verify model integrity
python -c "
from transformers import AutoConfig
config = AutoConfig.from_pretrained('/models/qwen3')
print('Model config loaded successfully')
"
```

### Issue: Server Starts But Crashes During Model Loading

**Symptoms:**
- Server starts, then crashes after a few minutes
- "CUDA out of memory" during loading
- Segmentation faults

**Diagnostic Commands:**
```bash
# Monitor memory usage during startup
watch -n 1 'nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader'

# Check available GPU memory before starting
nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits

# Monitor system logs during startup
sudo journalctl -f | grep -i cuda
```

**Solutions:**

1. **Reduce Memory Usage:**
```bash
# Start with lower GPU memory utilization
vllm serve /models/qwen3 \
    --tensor-parallel-size 4 \
    --max-model-len 200000 \
    --gpu-memory-utilization 0.85 \
    --kv-cache-dtype fp8 \
    --host 0.0.0.0 \
    --port 8000 \
    --trust-remote-code
```

2. **Clear GPU Memory:**
```bash
# Kill any remaining CUDA processes
sudo pkill -f python
sudo nvidia-smi --gpu-reset

# Clear CUDA cache
python -c "import torch; torch.cuda.empty_cache()"
```

3. **Use Pipeline Parallelism:**
```bash
# Distribute model layers across GPUs
vllm serve /models/qwen3 \
    --tensor-parallel-size 2 \
    --pipeline-parallel-size 2 \
    --max-model-len 400000 \
    --gpu-memory-utilization 0.90 \
    --trust-remote-code
```

### Issue: Long Startup Times

**Symptoms:**
- Server takes more than 15 minutes to start
- No response for extended periods
- Model loading appears stuck

**Diagnostic Commands:**
```bash
# Monitor model loading progress
tail -f /var/log/vllm/vllm-*.log | grep -i "loading\|progress"

# Check I/O usage
iostat -x 1

# Monitor CPU usage
htop
```

**Solutions:**

1. **Enable Model Loading Optimization:**
```bash
export HF_HUB_ENABLE_HF_TRANSFER=1
export HF_HOME=/tmp/huggingface_cache
```

2. **Use Local Model Path:**
```bash
# Ensure using local path (not downloading)
ls -la /models/qwen3/pytorch_model*.bin
```

3. **Check Storage Performance:**
```bash
# Test disk I/O
dd if=/dev/zero of=/models/test_file bs=1G count=1 oflag=direct
rm /models/test_file
```

---

## Memory and Performance Issues

### Issue: CUDA Out of Memory

**Error Messages:**
```
RuntimeError: CUDA out of memory. Tried to allocate X.XX GiB
OutOfMemoryError: CUDA out of memory
```

**Diagnostic Commands:**
```bash
# Check current GPU memory usage
nvidia-smi

# Check memory fragmentation
nvidia-smi --query-gpu=memory.used,memory.free --format=csv

# Monitor memory during inference
watch -n 1 nvidia-smi
```

**Solutions by Context Length:**

**For 200k-400k context:**
```bash
vllm serve /models/qwen3 \
    --tensor-parallel-size 4 \
    --max-model-len 400000 \
    --gpu-memory-utilization 0.90 \
    --kv-cache-dtype fp8 \
    --trust-remote-code
```

**For 400k-600k context:**
```bash
vllm serve /models/qwen3 \
    --tensor-parallel-size 2 \
    --pipeline-parallel-size 2 \
    --max-model-len 600000 \
    --gpu-memory-utilization 0.95 \
    --kv-cache-dtype fp8 \
    --trust-remote-code
```

**For maximum context (700k):**
```bash
vllm serve /models/qwen3 \
    --tensor-parallel-size 2 \
    --pipeline-parallel-size 2 \
    --max-model-len 700000 \
    --gpu-memory-utilization 0.98 \
    --kv-cache-dtype fp8 \
    --trust-remote-code
```

### Issue: Slow Generation Speed

**Symptoms:**
- Very low tokens/second
- Long response times
- High latency for short prompts

**Diagnostic Commands:**
```bash
# Monitor GPU utilization
nvidia-smi -l 1

# Check batch processing
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3",
    "messages": [{"role": "user", "content": "Count to 10"}],
    "max_tokens": 50
  }' \
  -w "Time: %{time_total}s\n"
```

**Performance Optimizations:**

1. **Optimize Parallelism for Speed:**
```bash
# Use tensor parallelism for faster inference
--tensor-parallel-size 4
--pipeline-parallel-size 1
```

2. **Increase Batch Size:**
```bash
--max-num-batched-tokens 8192
--max-num-seqs 32
```

3. **Disable Eager Mode:**
```bash
--enforce-eager false
```

4. **Use Appropriate KV Cache:**
```bash
# For speed over memory
--kv-cache-dtype auto

# For memory over speed
--kv-cache-dtype fp8
```

### Issue: Memory Leaks

**Symptoms:**
- GPU memory usage increases over time
- Eventually runs out of memory
- Needs periodic restarts

**Diagnostic Commands:**
```bash
# Monitor memory usage over time
while true; do
    echo "$(date): $(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)"
    sleep 60
done

# Check for memory fragmentation
nvidia-smi --query-gpu=memory.free --format=csv,noheader
```

**Solutions:**
```bash
# Restart server periodically (systemd timer)
sudo tee /etc/systemd/system/vllm-restart.service << EOF
[Unit]
Description=Restart vLLM server

[Service]
Type=oneshot
ExecStart=/bin/systemctl restart vllm-server
EOF

sudo tee /etc/systemd/system/vllm-restart.timer << EOF
[Unit]
Description=Restart vLLM every 24 hours

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl enable vllm-restart.timer
sudo systemctl start vllm-restart.timer
```

---

## API and Connection Issues

### Issue: Connection Refused

**Symptoms:**
- `curl: (7) Failed to connect to localhost port 8000: Connection refused`
- API client timeouts
- Cannot reach server endpoint

**Diagnostic Commands:**
```bash
# Check if port is open
netstat -tlnp | grep 8000
ss -tlnp | grep 8000

# Check if server is binding to correct interface
lsof -i :8000

# Test local connectivity
telnet localhost 8000
```

**Solutions:**

1. **Check Server Binding:**
```bash
# Ensure server binds to all interfaces
--host 0.0.0.0
--port 8000
```

2. **Firewall Configuration:**
```bash
# Allow traffic on port 8000
sudo ufw allow 8000/tcp
sudo ufw reload
```

3. **Check Process Status:**
```bash
# Verify vLLM is actually running
ps aux | grep vllm | grep -v grep

# Restart if needed
sudo systemctl restart vllm-server
```

### Issue: API Authentication Errors

**Symptoms:**
- `401 Unauthorized` responses
- "Invalid API key" errors
- Authentication header issues

**Diagnostic Commands:**
```bash
# Test with correct API key
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen3", "messages": [{"role": "user", "content": "test"}]}'

# Check environment variable
echo "API Key: $VLLM_API_KEY"
```

**Solutions:**

1. **Set API Key Correctly:**
```bash
export VLLM_API_KEY='your-actual-api-key-here'
echo $VLLM_API_KEY  # Verify it's set
```

2. **Update Server Configuration:**
```bash
# Restart server with correct API key
vllm serve /models/qwen3 --api-key $VLLM_API_KEY
```

3. **Check API Key in Requests:**
```bash
# Correct format
-H "Authorization: Bearer your-api-key"

# Not this
-H "Authorization: your-api-key"
```

### Issue: Slow API Responses

**Symptoms:**
- Requests take a very long time
- Timeouts on large requests
- Inconsistent response times

**Diagnostic Commands:**
```bash
# Test response time with minimal request
time curl -s -X POST http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen3", "messages": [{"role": "user", "content": "Hi"}], "max_tokens": 1}'

# Monitor server load during requests
htop
```

**Solutions:**

1. **Optimize Request Parameters:**
```bash
# Reduce max_tokens for testing
"max_tokens": 100

# Lower temperature for faster inference
"temperature": 0.1

# Use streaming for long responses
"stream": true
```

2. **Server Optimizations:**
```bash
# Increase batch size
--max-num-batched-tokens 8192

# Optimize for latency
--disable-log-requests
```

---

## Model Loading Problems

### Issue: Model Files Not Found

**Symptoms:**
- "No such file or directory" errors
- "Model config not found"
- Path-related errors

**Diagnostic Commands:**
```bash
# Check model directory structure
ls -la /models/qwen3/
find /models/qwen3 -name "*.json" -o -name "*.bin" -o -name "*.safetensors"

# Verify model size
du -sh /models/qwen3/
```

**Solutions:**

1. **Re-download Model:**
```bash
rm -rf /models/qwen3
mkdir -p /models/qwen3

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

2. **Fix Permissions:**
```bash
sudo chown -R root:root /models/qwen3
sudo chmod -R 755 /models/qwen3
```

3. **Verify Model Integrity:**
```bash
python -c "
from transformers import AutoConfig, AutoTokenizer
config = AutoConfig.from_pretrained('/models/qwen3')
tokenizer = AutoTokenizer.from_pretrained('/models/qwen3')
print('Model files are valid')
"
```

### Issue: Corrupted Model Files

**Symptoms:**
- Checksum errors during loading
- Unexpected EOF errors
- Model loading fails partway through

**Diagnostic Commands:**
```bash
# Check file sizes
ls -lah /models/qwen3/*.bin /models/qwen3/*.safetensors

# Verify no zero-byte files
find /models/qwen3 -size 0 -ls

# Check disk space and errors
dmesg | grep -i error
df -h /models
```

**Solutions:**

1. **Resume Download:**
```bash
# Use resume capability
python -c "
from huggingface_hub import snapshot_download
snapshot_download(
    'Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8',
    local_dir='/models/qwen3',
    local_dir_use_symlinks=False,
    resume_download=True,  # This will resume partial downloads
    force_download=False   # Only download missing files
)
"
```

2. **Clean and Re-download:**
```bash
# Remove corrupted files and re-download
rm -rf /models/qwen3
# Run download script again
```

3. **Use Git LFS (Alternative):**
```bash
cd /models
git lfs clone https://huggingface.co/Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8 qwen3
```

---

## Hardware and Driver Issues

### Issue: NVIDIA Driver Problems

**Symptoms:**
- `nvidia-smi` command not found
- CUDA errors
- GPU not detected

**Diagnostic Commands:**
```bash
# Check driver installation
nvidia-smi
lsmod | grep nvidia

# Check CUDA installation
nvcc --version
ls /usr/local/cuda/

# Check GPU detection
lspci | grep -i nvidia
```

**Solutions:**

1. **Install/Reinstall NVIDIA Drivers:**
```bash
# Remove old drivers
sudo apt-get purge nvidia-driver-*
sudo apt-get autoremove

# Install latest drivers
sudo apt-get update
sudo apt-get install nvidia-driver-545

# Reboot system
sudo reboot
```

2. **Install CUDA Toolkit:**
```bash
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt-get update
sudo apt-get install cuda-toolkit-12-6
```

3. **Set Persistence Mode:**
```bash
sudo nvidia-smi -pm 1
```

### Issue: GPU Communication Problems

**Symptoms:**
- NCCL initialization errors
- Peer-to-peer communication failures
- Multi-GPU setup not working

**Diagnostic Commands:**
```bash
# Check GPU topology
nvidia-smi topo -m

# Test GPU communication
python -c "
import torch
print(f'CUDA devices: {torch.cuda.device_count()}')
for i in range(torch.cuda.device_count()):
    print(f'GPU {i}: {torch.cuda.get_device_name(i)}')
"

# Check NCCL
export NCCL_DEBUG=INFO
```

**Solutions:**

1. **Configure NCCL Environment:**
```bash
export NCCL_P2P_DISABLE=0
export NCCL_IB_DISABLE=1
export NCCL_SOCKET_IFNAME=lo
export NCCL_DEBUG=INFO
```

2. **Verify GPU Connectivity:**
```bash
# Ensure all GPUs are on the same PCIe switch
nvidia-smi topo -m

# Check for ECC errors
nvidia-smi -q -d ECC
```

3. **Test Multi-GPU Setup:**
```bash
python -c "
import torch
if torch.cuda.device_count() >= 4:
    # Test all GPUs can allocate memory
    for i in range(4):
        with torch.cuda.device(i):
            x = torch.randn(1000, 1000).cuda()
            print(f'GPU {i}: OK')
else:
    print('Need at least 4 GPUs')
"
```

---

## Configuration Problems

### Issue: Environment Variable Conflicts

**Symptoms:**
- Inconsistent behavior between runs
- Settings not taking effect
- Unexpected configuration values

**Diagnostic Commands:**
```bash
# Check all VLLM-related environment variables
env | grep -i vllm
env | grep -i cuda
env | grep -i nccl

# Check current shell environment
echo $SHELL
which python
```

**Solutions:**

1. **Clean Environment Setup:**
```bash
# Create clean environment script
cat > /opt/vllm/setup_env.sh << 'EOF'
#!/bin/bash
# Clean VLLM environment setup

# Clear conflicting variables
unset PYTHONPATH
unset CUDA_HOME

# Set required variables
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3
export VLLM_API_KEY='your-api-key-here'

# Optional optimizations
export NCCL_DEBUG=WARN
export VLLM_FP8_KV_CACHE=0

# Activate environment
source /opt/vllm/bin/activate
EOF

chmod +x /opt/vllm/setup_env.sh
```

2. **Use Consistent Startup:**
```bash
# Always source environment before starting
source /opt/vllm/setup_env.sh
vllm serve /models/qwen3 [options]
```

### Issue: Configuration Parameter Conflicts

**Symptoms:**
- Server rejects configuration
- Warnings about incompatible settings
- Suboptimal performance

**Common Conflicts:**

1. **Context Length vs Memory:**
```bash
# ❌ Too high context for available memory
--max-model-len 1000000 --gpu-memory-utilization 0.95

# ✅ Balanced configuration
--max-model-len 700000 --gpu-memory-utilization 0.98
```

2. **Parallelism Conflicts:**
```bash
# ❌ Too much total parallelism
--tensor-parallel-size 4 --pipeline-parallel-size 4  # Total: 16 GPUs needed

# ✅ Appropriate for 4 GPUs
--tensor-parallel-size 2 --pipeline-parallel-size 2  # Total: 4 GPUs
```

3. **Batch Size Issues:**
```bash
# ❌ Batch size too large for context
--max-model-len 700000 --max-num-batched-tokens 32768

# ✅ Appropriate batch size
--max-model-len 700000 --max-num-batched-tokens 8192
```

---

## Debugging Tools and Commands

### Essential Debugging Commands

```bash
#!/bin/bash
# debug_vllm.sh - Comprehensive debugging script

echo "=== vLLM Debug Information ==="
echo "Date: $(date)"
echo

echo "=== System Information ==="
uname -a
lsb_release -a
free -h
df -h /models
echo

echo "=== GPU Information ==="
nvidia-smi
nvidia-smi --query-gpu=index,name,driver_version,memory.total,memory.used --format=csv
echo

echo "=== Process Information ==="
ps aux | grep vllm | grep -v grep
pgrep -fa vllm
echo

echo "=== Network Information ==="
netstat -tlnp | grep 8000
ss -tlnp | grep 8000
echo

echo "=== Python Environment ==="
source /opt/vllm/bin/activate
python --version
pip list | grep -E "vllm|torch|transformers|cuda"
echo

echo "=== Environment Variables ==="
env | grep -E "VLLM|CUDA|NCCL" | sort
echo

echo "=== Model Information ==="
ls -la /models/qwen3/ | head -10
du -sh /models/qwen3/
echo

echo "=== Recent Logs ==="
if [ -f /var/log/vllm/vllm-*.log ]; then
    echo "Last 20 log entries:"
    tail -20 /var/log/vllm/vllm-*.log
else
    echo "No vLLM log files found"
fi
echo

echo "=== Memory Usage ==="
free -h
nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader
echo

echo "=== Disk I/O ==="
iostat -x 1 1
echo

echo "=== Debug Complete ==="
```

### Performance Monitoring

```bash
#!/bin/bash
# monitor_performance.sh

# Monitor in real-time
watch -n 1 'echo "=== GPU Usage ==="; nvidia-smi --query-gpu=index,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader; echo; echo "=== System ==="; free -h | grep Mem; echo "Load: $(uptime | cut -d, -f3-5)"'

# Log performance data
while true; do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    gpu_usage=$(nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader,nounits)
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    
    echo "$timestamp,GPU: $gpu_usage,CPU: $cpu_usage%,MEM: $mem_usage%" >> /var/log/vllm_performance.log
    sleep 60
done
```

### Log Analysis Tools

```bash
# Extract error patterns
grep -E "(error|Error|ERROR|exception|Exception)" /var/log/vllm/vllm-*.log | tail -20

# Find memory-related issues
grep -E "(memory|Memory|OOM|out of memory)" /var/log/vllm/vllm-*.log | tail -10

# Check startup sequence
grep -E "(loading|Loading|initialized|Initialized)" /var/log/vllm/vllm-*.log | tail -15

# Performance metrics
grep -E "(tokens/s|throughput|latency)" /var/log/vllm/vllm-*.log | tail -10
```

---

## Recovery Procedures

### Emergency Recovery Steps

When vLLM is completely unresponsive:

```bash
#!/bin/bash
# emergency_recovery.sh

echo "=== Emergency vLLM Recovery ==="

# 1. Kill all vLLM processes
echo "Killing vLLM processes..."
sudo pkill -9 -f vllm
sudo pkill -9 -f python.*qwen

# 2. Clear GPU memory
echo "Clearing GPU memory..."
sudo nvidia-smi --gpu-reset

# 3. Clean screen sessions
echo "Cleaning screen sessions..."
screen -wipe

# 4. Clear shared memory
echo "Clearing shared memory..."
sudo rm -f /dev/shm/vllm*

# 5. Reset CUDA context
echo "Resetting CUDA..."
python -c "import torch; torch.cuda.empty_cache()" 2>/dev/null || echo "CUDA reset failed"

# 6. Wait for GPUs to initialize
echo "Waiting for GPU reset..."
sleep 10

# 7. Start with minimal configuration
echo "Starting vLLM with minimal config..."
source /opt/vllm/bin/activate
export VLLM_API_KEY='your-api-key-here'
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1

# Start in screen session with basic config
screen -dmS vllm_recovery bash -c "
vllm serve /models/qwen3 \
    --tensor-parallel-size 4 \
    --max-model-len 200000 \
    --gpu-memory-utilization 0.85 \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --trust-remote-code \
    2>&1 | tee /tmp/vllm_recovery.log
"

echo "Recovery started. Monitor with: screen -r vllm_recovery"
echo "Logs available at: /tmp/vllm_recovery.log"
```

### Gradual Recovery Process

```bash
#!/bin/bash
# gradual_recovery.sh - Step-by-step recovery

recovery_step() {
    echo "=== Recovery Step $1: $2 ==="
    if eval "$3"; then
        echo "✅ Step $1 successful"
        return 0
    else
        echo "❌ Step $1 failed"
        return 1
    fi
}

# Step 1: Basic system check
recovery_step 1 "System Check" "
    nvidia-smi > /dev/null && 
    [ -d /models/qwen3 ] && 
    [ -f /models/qwen3/config.json ]
"

# Step 2: Environment setup
recovery_step 2 "Environment Setup" "
    source /opt/vllm/bin/activate && 
    python -c 'import vllm, torch' && 
    export VLLM_API_KEY='your-api-key-here'
"

# Step 3: Start with minimal config
recovery_step 3 "Minimal Start" "
    timeout 300 vllm serve /models/qwen3 \
        --tensor-parallel-size 2 \
        --max-model-len 100000 \
        --gpu-memory-utilization 0.8 \
        --host 0.0.0.0 \
        --port 8000 \
        --trust-remote-code &
    sleep 60 && 
    curl -s http://localhost:8000/health > /dev/null
"

# Step 4: Test API
recovery_step 4 "API Test" "
    curl -X POST http://localhost:8000/v1/chat/completions \
        -H 'Authorization: Bearer $VLLM_API_KEY' \
        -H 'Content-Type: application/json' \
        -d '{\"model\": \"qwen3\", \"messages\": [{\"role\": \"user\", \"content\": \"test\"}], \"max_tokens\": 1}' \
        -s | grep -q choices
"

echo "Gradual recovery complete. Server should be functional."
```

### Configuration Reset

```bash
#!/bin/bash
# reset_config.sh - Reset to known good configuration

# Backup current configuration
cp /opt/vllm/setup_env.sh /opt/vllm/setup_env.sh.backup 2>/dev/null

# Create clean configuration
cat > /opt/vllm/setup_env.sh << 'EOF'
#!/bin/bash
# Known good vLLM configuration

# Clear environment
unset PYTHONPATH
unset CUDA_HOME

# Essential variables
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3
export VLLM_API_KEY='your-api-key-here'

# Conservative NCCL settings
export NCCL_DEBUG=WARN
export NCCL_P2P_DISABLE=0
export NCCL_IB_DISABLE=1

# Activate environment
source /opt/vllm/bin/activate
EOF

chmod +x /opt/vllm/setup_env.sh

# Create known good startup script
cat > /opt/vllm/start_conservative.sh << 'EOF'
#!/bin/bash
source /opt/vllm/setup_env.sh

vllm serve /models/qwen3 \
    --tensor-parallel-size 4 \
    --max-model-len 300000 \
    --gpu-memory-utilization 0.90 \
    --kv-cache-dtype auto \
    --host 0.0.0.0 \
    --port 8000 \
    --api-key $VLLM_API_KEY \
    --trust-remote-code \
    2>&1 | tee /var/log/vllm/conservative.log
EOF

chmod +x /opt/vllm/start_conservative.sh

echo "Configuration reset complete. Use: /opt/vllm/start_conservative.sh"
```

---

This troubleshooting guide covers the most common issues you'll encounter with the vLLM Qwen3-480B setup. Always start with the quick diagnostics, then work through the specific issue sections based on your symptoms. Remember to check logs and monitor system resources during troubleshooting.