# vLLM Qwen3-480B Performance Optimization Guide

## Table of Contents
1. [Performance Overview](#performance-overview)
2. [Hardware Optimization](#hardware-optimization)
3. [Configuration Tuning](#configuration-tuning)
4. [Memory Management](#memory-management)
5. [Context Length Optimization](#context-length-optimization)
6. [Parallelism Strategies](#parallelism-strategies)
7. [Monitoring and Benchmarking](#monitoring-and-benchmarking)
8. [Common Performance Issues](#common-performance-issues)
9. [Advanced Optimizations](#advanced-optimizations)
10. [Performance Testing Scripts](#performance-testing-scripts)

---

## Performance Overview

The vLLM Qwen3-480B server has been optimized for maximum performance on 4x NVIDIA H200 GPUs. Understanding the performance characteristics and optimization strategies is crucial for getting the best results.

### Key Performance Metrics

| Metric | Target Value | Production Range |
|--------|--------------|------------------|
| **Context Length** | 700,000 tokens | 200k - 700k tokens |
| **Generation Speed** | 15-20 tokens/sec | 10-25 tokens/sec |
| **Startup Time** | 5-10 minutes | 5-15 minutes |
| **GPU Utilization** | 95-98% | 90-99% |
| **Memory Usage** | ~560GB GPU VRAM | 500-575GB |
| **Latency (first token)** | 2-5 seconds | 1-10 seconds |

### Performance Factors

**Primary Factors:**
- Context length (longer = slower)
- Batch size (larger = more efficient)
- Parallelism configuration (TP vs PP)
- GPU memory utilization
- Model quantization settings

**Secondary Factors:**
- System RAM availability
- Storage I/O performance
- Network latency (for API requests)
- CPU performance
- Thermal throttling

---

## Hardware Optimization

### GPU Configuration

**Optimal GPU Settings:**
```bash
# Enable persistence mode (reduces latency)
sudo nvidia-smi -pm 1

# Set maximum performance mode
sudo nvidia-smi -ac 9501,2619  # Memory:Graphics clocks for H200

# Disable ECC if not needed (gains ~5% memory)
sudo nvidia-smi -e 0

# Set power limit to maximum
sudo nvidia-smi -pl 700  # 700W for H200
```

**Monitor GPU Performance:**
```bash
# Real-time monitoring
nvidia-smi -l 1

# Detailed GPU metrics
nvidia-smi --query-gpu=index,name,utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw --format=csv -l 1

# Check GPU topology
nvidia-smi topo -m
```

### System-Level Optimizations

**CPU Governor:**
```bash
# Set CPU to performance mode
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Verify setting
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
```

**Memory Settings:**
```bash
# Disable swap (critical for performance)
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Set kernel parameters
echo 'vm.swappiness=1' | sudo tee -a /etc/sysctl.conf
echo 'vm.overcommit_memory=1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

**Network Optimization:**
```bash
# Increase network buffer sizes
sudo sysctl -w net.core.rmem_max=134217728
sudo sysctl -w net.core.wmem_max=134217728
sudo sysctl -w net.ipv4.tcp_rmem="4096 87380 134217728"
sudo sysctl -w net.ipv4.tcp_wmem="4096 65536 134217728"

# Make permanent
cat >> /etc/sysctl.conf << EOF
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
EOF
```

**Storage Optimization:**
```bash
# For NVMe drives, optimize queue depth
echo mq-deadline | sudo tee /sys/block/nvme0n1/queue/scheduler

# Increase read-ahead
echo 4096 | sudo tee /sys/block/nvme0n1/queue/read_ahead_kb
```

---

## Configuration Tuning

### Context Length vs Performance Trade-offs

| Context Length | Config | Speed | Use Case |
|----------------|--------|-------|----------|
| 200k | TP=4, PP=1 | Fastest | Chat, short coding |
| 400k | TP=4, PP=1 | Fast | Document analysis |
| 600k | TP=2, PP=2 | Medium | Long documents |
| 700k | TP=2, PP=2 | Slower | Maximum context |

### Optimal Configurations by Use Case

**High-Speed Chat (200k context):**
```bash
vllm serve /models/qwen3 \
    --tensor-parallel-size 4 \
    --max-model-len 200000 \
    --gpu-memory-utilization 0.90 \
    --kv-cache-dtype auto \
    --max-num-batched-tokens 8192 \
    --max-num-seqs 32 \
    --host 0.0.0.0 \
    --port 8000 \
    --trust-remote-code
```

**Balanced Performance (400k context):**
```bash
vllm serve /models/qwen3 \
    --tensor-parallel-size 4 \
    --max-model-len 400000 \
    --gpu-memory-utilization 0.95 \
    --kv-cache-dtype fp8 \
    --max-num-batched-tokens 6144 \
    --max-num-seqs 16 \
    --host 0.0.0.0 \
    --port 8000 \
    --trust-remote-code
```

**Maximum Context (700k tokens):**
```bash
vllm serve /models/qwen3 \
    --tensor-parallel-size 2 \
    --pipeline-parallel-size 2 \
    --max-model-len 700000 \
    --gpu-memory-utilization 0.98 \
    --kv-cache-dtype fp8 \
    --max-num-batched-tokens 4096 \
    --max-num-seqs 8 \
    --host 0.0.0.0 \
    --port 8000 \
    --trust-remote-code
```

### Parameter Optimization Guide

**GPU Memory Utilization:**
```bash
# Conservative (safer)
--gpu-memory-utilization 0.85

# Balanced (recommended)
--gpu-memory-utilization 0.95

# Aggressive (maximum context)
--gpu-memory-utilization 0.98
```

**KV Cache Settings:**
```bash
# Best quality (uses more memory)
--kv-cache-dtype auto

# Balanced (good quality, less memory)
--kv-cache-dtype fp16

# Memory optimized (slight quality loss)
--kv-cache-dtype fp8
```

**Batch Size Optimization:**
```bash
# For short sequences
--max-num-batched-tokens 16384
--max-num-seqs 64

# For medium sequences
--max-num-batched-tokens 8192
--max-num-seqs 32

# For long sequences
--max-num-batched-tokens 4096
--max-num-seqs 8
```

---

## Memory Management

### GPU Memory Optimization

**Memory Usage Monitoring:**
```bash
#!/bin/bash
# monitor_gpu_memory.sh

while true; do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    gpu_memory=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits)
    
    echo "$timestamp - GPU Memory: $gpu_memory"
    
    # Alert if memory usage is too high
    used=$(echo $gpu_memory | cut -d',' -f1)
    total=$(echo $gpu_memory | cut -d',' -f2)
    usage_percent=$((used * 100 / total))
    
    if [ $usage_percent -gt 98 ]; then
        echo "WARNING: GPU memory usage at ${usage_percent}%"
    fi
    
    sleep 30
done
```

**Memory Fragmentation Prevention:**
```bash
# Clear GPU memory before starting
python -c "import torch; torch.cuda.empty_cache()"

# Use consistent batch sizes to avoid fragmentation
--max-num-batched-tokens 8192  # Use powers of 2

# Restart server periodically to clear fragmentation
# (Set up systemd timer for automated restarts)
```

### System Memory Optimization

**Monitor System Memory:**
```bash
#!/bin/bash
# monitor_system_memory.sh

watch -n 5 'free -h && echo "Swap usage:" && swapon -s'

# Alert script
threshold=90
current=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100)}')

if [ $current -gt $threshold ]; then
    echo "WARNING: System memory usage at ${current}%"
    # Log top memory consumers
    ps aux --sort=-%mem | head -10
fi
```

**Memory Usage Patterns:**

| Component | Typical Usage | Notes |
|-----------|---------------|-------|
| **Model Weights** | ~240GB | Fixed, loaded once |
| **KV Cache** | 200-320GB | Varies with context |
| **Activation Memory** | 50-100GB | Varies with batch size |
| **System Overhead** | 50-100GB | OS + other processes |

---

## Context Length Optimization

### Context Length Strategy

**Choosing Optimal Context Length:**
```python
def choose_context_length(use_case):
    context_recommendations = {
        "chat": 50000,           # Normal conversations
        "code_review": 100000,   # Code analysis
        "document_qa": 200000,   # Document questions
        "research": 400000,      # Research papers
        "book_analysis": 700000  # Entire books
    }
    return context_recommendations.get(use_case, 200000)

# Example usage
optimal_context = choose_context_length("document_qa")
print(f"Recommended context length: {optimal_context}")
```

**Dynamic Context Management:**
```python
def optimize_context_usage(messages, max_context=700000):
    """
    Dynamically manage context to fit within limits
    """
    total_tokens = estimate_tokens(messages)
    
    if total_tokens <= max_context:
        return messages
    
    # Strategy 1: Summarize older messages
    if len(messages) > 10:
        # Keep system message and recent messages
        system_msg = messages[0] if messages[0]["role"] == "system" else None
        recent_messages = messages[-8:]  # Keep last 8 messages
        
        # Summarize middle messages
        middle_messages = messages[1:-8] if system_msg else messages[:-8]
        summary = summarize_conversation(middle_messages)
        
        optimized_messages = []
        if system_msg:
            optimized_messages.append(system_msg)
        optimized_messages.append({
            "role": "assistant", 
            "content": f"[Previous conversation summary: {summary}]"
        })
        optimized_messages.extend(recent_messages)
        
        return optimized_messages
    
    # Strategy 2: Truncate if still too long
    return truncate_messages(messages, max_context)
```

### Context-Aware Performance Tuning

**Adjust Settings Based on Context:**
```bash
#!/bin/bash
# adaptive_start.sh - Adjust configuration based on expected context usage

CONTEXT_LENGTH=${1:-400000}

if [ $CONTEXT_LENGTH -le 200000 ]; then
    # High speed configuration
    CONFIG="--tensor-parallel-size 4 --gpu-memory-utilization 0.90 --kv-cache-dtype auto"
elif [ $CONTEXT_LENGTH -le 400000 ]; then
    # Balanced configuration
    CONFIG="--tensor-parallel-size 4 --gpu-memory-utilization 0.95 --kv-cache-dtype fp8"
elif [ $CONTEXT_LENGTH -le 600000 ]; then
    # High context configuration
    CONFIG="--tensor-parallel-size 2 --pipeline-parallel-size 2 --gpu-memory-utilization 0.97 --kv-cache-dtype fp8"
else
    # Maximum context configuration
    CONFIG="--tensor-parallel-size 2 --pipeline-parallel-size 2 --gpu-memory-utilization 0.98 --kv-cache-dtype fp8"
fi

echo "Starting vLLM with context length $CONTEXT_LENGTH"
echo "Configuration: $CONFIG"

source /opt/vllm/bin/activate
vllm serve /models/qwen3 \
    --max-model-len $CONTEXT_LENGTH \
    $CONFIG \
    --host 0.0.0.0 \
    --port 8000 \
    --trust-remote-code
```

---

## Parallelism Strategies

### Tensor Parallelism vs Pipeline Parallelism

**Tensor Parallelism (TP):**
- Splits model weights across GPUs
- Lower latency, higher throughput
- Better for shorter contexts
- All GPUs work on same batch

**Pipeline Parallelism (PP):**
- Splits model layers across GPUs
- Enables longer contexts
- Higher latency due to pipeline bubbles
- Sequential processing through stages

### Parallelism Configuration Guide

**4 GPUs Available - Configuration Options:**

| TP | PP | Total GPUs | Context Limit | Speed | Use Case |
|----|----|-----------:|---------------|-------|----------|
| 4 | 1 | 4 | ~400k | Fastest | Chat, coding |
| 2 | 2 | 4 | ~700k | Medium | Long documents |
| 1 | 4 | 4 | ~1M+ | Slowest | Experimental |

**8 GPUs Available - Advanced Configurations:**

| TP | PP | Total GPUs | Context Limit | Speed | Use Case |
|----|----|-----------:|---------------|-------|----------|
| 8 | 1 | 8 | ~500k | Fastest | High throughput |
| 4 | 2 | 8 | ~800k | Fast | Balanced |
| 2 | 4 | 8 | ~1.2M | Slow | Maximum context |

### NCCL Optimization for Multi-GPU

**NCCL Environment Variables:**
```bash
# For optimal H200 performance
export NCCL_DEBUG=WARN
export NCCL_P2P_DISABLE=0       # Enable P2P for H200
export NCCL_IB_DISABLE=1        # Disable InfiniBand if not available
export NCCL_SOCKET_IFNAME=eth0  # Specify network interface
export NCCL_ALGO=Tree           # Tree algorithm for 4 GPUs
export NCCL_PROTO=Simple        # Simple protocol
```

**Test GPU Communication:**
```python
# test_gpu_communication.py
import torch
import time

def test_multicast_communication():
    if torch.cuda.device_count() < 4:
        print("Need at least 4 GPUs for testing")
        return
    
    print(f"Testing communication across {torch.cuda.device_count()} GPUs")
    
    # Create tensors on each GPU
    tensors = []
    for i in range(4):
        with torch.cuda.device(i):
            tensor = torch.randn(1000, 1000, device=f'cuda:{i}')
            tensors.append(tensor)
    
    # Test P2P communication
    start_time = time.time()
    
    # Copy from GPU 0 to all others
    source_tensor = tensors[0]
    for i in range(1, 4):
        with torch.cuda.device(i):
            target_tensor = source_tensor.to(f'cuda:{i}')
            torch.cuda.synchronize()
    
    end_time = time.time()
    
    print(f"P2P communication test completed in {end_time - start_time:.2f} seconds")
    
    # Test all-reduce operation
    start_time = time.time()
    torch.distributed.all_reduce(tensors[0])
    torch.cuda.synchronize()
    end_time = time.time()
    
    print(f"All-reduce test completed in {end_time - start_time:.2f} seconds")

if __name__ == "__main__":
    test_multicast_communication()
```

---

## Monitoring and Benchmarking

### Performance Monitoring Dashboard

```bash
#!/bin/bash
# performance_dashboard.sh

# Clear screen and setup colors
clear
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

while true; do
    clear
    echo -e "${BLUE}=== vLLM Performance Dashboard ===${NC}"
    echo "Timestamp: $(date)"
    echo
    
    # GPU Status
    echo -e "${GREEN}GPU Status:${NC}"
    nvidia-smi --query-gpu=index,name,utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw --format=csv,noheader | \
    while IFS=',' read -r idx name gpu_util mem_util mem_used mem_total temp power; do
        gpu_util_clean=$(echo $gpu_util | xargs)
        mem_util_clean=$(echo $mem_util | xargs)
        temp_clean=$(echo $temp | xargs)
        power_clean=$(echo $power | xargs)
        
        printf "GPU %s: %s%% GPU, %s%% MEM, %s, %s\n" \
               "$idx" "$gpu_util_clean" "$mem_util_clean" "$temp_clean" "$power_clean"
    done
    echo
    
    # System Resources
    echo -e "${GREEN}System Resources:${NC}"
    
    # CPU usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    echo "CPU Usage: ${cpu_usage}%"
    
    # Memory usage
    mem_info=$(free -h | grep Mem)
    mem_used=$(echo $mem_info | awk '{print $3}')
    mem_total=$(echo $mem_info | awk '{print $2}')
    mem_percent=$(free | grep Mem | awk '{printf("%.1f", $3/$2 * 100)}')
    echo "System Memory: ${mem_used}/${mem_total} (${mem_percent}%)"
    
    # Load average
    load_avg=$(uptime | awk -F'load average:' '{print $2}')
    echo "Load Average:${load_avg}"
    echo
    
    # vLLM Process Status
    echo -e "${GREEN}vLLM Status:${NC}"
    if pgrep -f vllm > /dev/null; then
        pid=$(pgrep -f vllm)
        echo -e "${GREEN}✓${NC} vLLM running (PID: $pid)"
        
        # Process resource usage
        ps_info=$(ps -p $pid -o %cpu,%mem,rss,vsz --no-headers)
        cpu_proc=$(echo $ps_info | awk '{print $1}')
        mem_proc=$(echo $ps_info | awk '{print $2}')
        echo "Process CPU: ${cpu_proc}%, Memory: ${mem_proc}%"
    else
        echo -e "${RED}✗${NC} vLLM not running"
    fi
    
    # API Health Check
    if curl -s --connect-timeout 2 http://localhost:8000/health > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} API endpoint responding"
    else
        echo -e "${RED}✗${NC} API endpoint not responding"
    fi
    echo
    
    # Recent Performance (if log exists)
    if [ -f /var/log/vllm_performance.log ]; then
        echo -e "${GREEN}Recent Performance:${NC}"
        tail -5 /var/log/vllm_performance.log
    fi
    
    sleep 5
done
```

### Benchmarking Scripts

**Throughput Benchmark:**
```python
#!/usr/bin/env python3
# benchmark_throughput.py

import time
import requests
import threading
import statistics
from concurrent.futures import ThreadPoolExecutor
import json

class VLLMBenchmark:
    def __init__(self, api_key, base_url="http://localhost:8000"):
        self.api_key = api_key
        self.base_url = base_url
        self.results = []
    
    def single_request(self, prompt, max_tokens=100):
        """Make a single API request and measure performance"""
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        
        data = {
            "model": "qwen3",
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens,
            "temperature": 0.1
        }
        
        start_time = time.time()
        
        try:
            response = requests.post(
                f"{self.base_url}/v1/chat/completions",
                headers=headers,
                json=data,
                timeout=300
            )
            
            end_time = time.time()
            
            if response.status_code == 200:
                result = response.json()
                usage = result.get("usage", {})
                
                return {
                    "success": True,
                    "duration": end_time - start_time,
                    "prompt_tokens": usage.get("prompt_tokens", 0),
                    "completion_tokens": usage.get("completion_tokens", 0),
                    "total_tokens": usage.get("total_tokens", 0),
                    "tokens_per_second": usage.get("total_tokens", 0) / (end_time - start_time)
                }
            else:
                return {
                    "success": False,
                    "error": f"HTTP {response.status_code}: {response.text}",
                    "duration": end_time - start_time
                }
                
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "duration": time.time() - start_time
            }
    
    def concurrent_benchmark(self, num_requests=10, max_workers=5):
        """Run concurrent requests to test throughput"""
        print(f"Running concurrent benchmark: {num_requests} requests, {max_workers} workers")
        
        prompts = [
            "Write a short Python function to sort a list",
            "Explain the concept of machine learning",
            "Generate a creative story about space exploration",
            "Describe the process of photosynthesis",
            "Write a haiku about artificial intelligence"
        ]
        
        # Extend prompts to match num_requests
        test_prompts = (prompts * (num_requests // len(prompts) + 1))[:num_requests]
        
        start_time = time.time()
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = [
                executor.submit(self.single_request, prompt, 150)
                for prompt in test_prompts
            ]
            
            results = [future.result() for future in futures]
        
        end_time = time.time()
        
        # Analyze results
        successful_results = [r for r in results if r["success"]]
        failed_results = [r for r in results if not r["success"]]
        
        if successful_results:
            durations = [r["duration"] for r in successful_results]
            tokens_per_sec = [r["tokens_per_second"] for r in successful_results]
            total_tokens = sum(r["total_tokens"] for r in successful_results)
            
            print(f"\n=== Benchmark Results ===")
            print(f"Total requests: {num_requests}")
            print(f"Successful: {len(successful_results)}")
            print(f"Failed: {len(failed_results)}")
            print(f"Total duration: {end_time - start_time:.2f}s")
            print(f"Average request duration: {statistics.mean(durations):.2f}s")
            print(f"Request rate: {num_requests / (end_time - start_time):.2f} req/s")
            print(f"Average tokens/sec per request: {statistics.mean(tokens_per_sec):.2f}")
            print(f"Total tokens processed: {total_tokens}")
            print(f"Overall throughput: {total_tokens / (end_time - start_time):.2f} tokens/s")
            
            if len(durations) > 1:
                print(f"Duration std dev: {statistics.stdev(durations):.2f}s")
                print(f"Min/Max duration: {min(durations):.2f}s / {max(durations):.2f}s")
        
        if failed_results:
            print(f"\n=== Failures ===")
            for i, result in enumerate(failed_results):
                print(f"Request {i+1}: {result['error']}")
        
        return {
            "successful": len(successful_results),
            "failed": len(failed_results),
            "total_duration": end_time - start_time,
            "results": results
        }
    
    def latency_test(self, num_samples=20):
        """Test first-token latency"""
        print(f"Running latency test with {num_samples} samples")
        
        latencies = []
        
        for i in range(num_samples):
            print(f"Sample {i+1}/{num_samples}", end="\r")
            
            result = self.single_request("Hello", max_tokens=1)
            if result["success"]:
                latencies.append(result["duration"])
        
        if latencies:
            print(f"\n=== Latency Test Results ===")
            print(f"Samples: {len(latencies)}")
            print(f"Average latency: {statistics.mean(latencies):.3f}s")
            print(f"Median latency: {statistics.median(latencies):.3f}s")
            print(f"Min/Max latency: {min(latencies):.3f}s / {max(latencies):.3f}s")
            
            if len(latencies) > 1:
                print(f"Standard deviation: {statistics.stdev(latencies):.3f}s")
        
        return latencies

def main():
    import os
    
    api_key = os.getenv("VLLM_API_KEY")
    if not api_key:
        print("Please set VLLM_API_KEY environment variable")
        return
    
    benchmark = VLLMBenchmark(api_key)
    
    print("=== vLLM Performance Benchmark ===")
    
    # Test single request first
    print("Testing single request...")
    result = benchmark.single_request("Hello, how are you?", max_tokens=50)
    if result["success"]:
        print(f"✓ Single request successful: {result['tokens_per_second']:.2f} tokens/s")
    else:
        print(f"✗ Single request failed: {result['error']}")
        return
    
    # Latency test
    benchmark.latency_test(10)
    
    # Throughput test
    benchmark.concurrent_benchmark(20, 5)

if __name__ == "__main__":
    main()
```

**Context Length Stress Test:**
```python
#!/usr/bin/env python3
# stress_test_context.py

import requests
import time
import random
import string

def generate_long_text(target_tokens):
    """Generate text of approximately target_tokens length"""
    # Rough estimate: 1 token ≈ 4 characters
    target_chars = target_tokens * 4
    
    text_parts = []
    current_length = 0
    
    sentences = [
        "The quick brown fox jumps over the lazy dog.",
        "Machine learning algorithms process vast amounts of data.",
        "Artificial intelligence continues to advance rapidly.",
        "Deep neural networks learn complex patterns from data.",
        "Natural language processing enables computers to understand human language.",
    ]
    
    while current_length < target_chars:
        sentence = random.choice(sentences)
        text_parts.append(sentence)
        current_length += len(sentence) + 1
    
    return " ".join(text_parts)

def test_context_length(api_key, context_tokens, max_response_tokens=500):
    """Test specific context length"""
    print(f"Testing context length: {context_tokens:,} tokens")
    
    # Generate long context
    long_text = generate_long_text(context_tokens - 100)  # Leave room for prompt
    
    prompt = f"""
    Please analyze the following text and provide a summary:
    
    {long_text}
    
    What are the main themes and patterns you observe?
    """
    
    data = {
        "model": "qwen3",
        "messages": [
            {"role": "user", "content": prompt}
        ],
        "max_tokens": max_response_tokens,
        "temperature": 0.1
    }
    
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    
    start_time = time.time()
    
    try:
        response = requests.post(
            "http://localhost:8000/v1/chat/completions",
            headers=headers,
            json=data,
            timeout=600  # 10 minute timeout
        )
        
        end_time = time.time()
        
        if response.status_code == 200:
            result = response.json()
            usage = result.get("usage", {})
            
            print(f"✓ Success! Duration: {end_time - start_time:.2f}s")
            print(f"  Prompt tokens: {usage.get('prompt_tokens', 0):,}")
            print(f"  Completion tokens: {usage.get('completion_tokens', 0):,}")
            print(f"  Total tokens: {usage.get('total_tokens', 0):,}")
            print(f"  Speed: {usage.get('total_tokens', 0) / (end_time - start_time):.2f} tokens/s")
            
            return True
        else:
            print(f"✗ Failed: HTTP {response.status_code}")
            print(f"  Error: {response.text}")
            return False
            
    except Exception as e:
        print(f"✗ Exception: {str(e)}")
        return False

def main():
    import os
    
    api_key = os.getenv("VLLM_API_KEY")
    if not api_key:
        print("Please set VLLM_API_KEY environment variable")
        return
    
    print("=== Context Length Stress Test ===")
    
    # Test different context lengths
    test_lengths = [10000, 50000, 100000, 200000, 400000, 600000]
    
    successful_lengths = []
    
    for length in test_lengths:
        print(f"\n{'='*50}")
        success = test_context_length(api_key, length)
        
        if success:
            successful_lengths.append(length)
        else:
            print(f"Failed at {length:,} tokens")
            break
        
        # Wait between tests to avoid overwhelming the server
        time.sleep(10)
    
    print(f"\n=== Final Results ===")
    print(f"Maximum successful context length: {max(successful_lengths):,} tokens")
    print(f"All successful lengths: {[f'{l:,}' for l in successful_lengths]}")

if __name__ == "__main__":
    main()
```

---

## Common Performance Issues

### Issue 1: Low GPU Utilization

**Symptoms:**
- GPU utilization below 80%
- Slow token generation
- High latency

**Diagnostic:**
```bash
# Monitor GPU utilization
nvidia-smi -l 1

# Check batch size effectiveness
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3",
    "messages": [{"role": "user", "content": "Count to 100"}],
    "max_tokens": 200
  }' &

# While request is running, check GPU utilization
watch -n 1 nvidia-smi
```

**Solutions:**
```bash
# Increase batch size
--max-num-batched-tokens 16384
--max-num-seqs 32

# Optimize parallelism
--tensor-parallel-size 4  # For better GPU utilization

# Disable eager execution
--enforce-eager false
```

### Issue 2: Memory Fragmentation

**Symptoms:**
- Out of memory errors despite apparent available memory
- Performance degradation over time
- Inconsistent memory usage

**Diagnostic:**
```python
# memory_fragmentation_check.py
import torch

def check_memory_fragmentation():
    for i in range(torch.cuda.device_count()):
        print(f"GPU {i}:")
        print(f"  Allocated: {torch.cuda.memory_allocated(i)/1024**3:.2f} GB")
        print(f"  Reserved: {torch.cuda.memory_reserved(i)/1024**3:.2f} GB")
        print(f"  Free: {torch.cuda.mem_get_info(i)[0]/1024**3:.2f} GB")
        
        # Check for fragmentation
        allocated = torch.cuda.memory_allocated(i)
        reserved = torch.cuda.memory_reserved(i)
        fragmentation = (reserved - allocated) / reserved * 100
        print(f"  Fragmentation: {fragmentation:.1f}%")

if __name__ == "__main__":
    check_memory_fragmentation()
```

**Solutions:**
```bash
# Restart server periodically
sudo systemctl restart vllm-server

# Use consistent batch sizes
--max-num-batched-tokens 8192  # Use same value consistently

# Clear cache before restart
python -c "import torch; torch.cuda.empty_cache()"
```

### Issue 3: NCCL Communication Bottlenecks

**Symptoms:**
- Slower performance with multiple GPUs than expected
- NCCL timeout errors
- Uneven GPU utilization

**Diagnostic:**
```bash
# Enable NCCL debugging
export NCCL_DEBUG=INFO

# Check GPU topology
nvidia-smi topo -m

# Test communication bandwidth
python -c "
import torch
import time

# Test P2P bandwidth
if torch.cuda.device_count() >= 2:
    size = 100*1024*1024  # 100MB
    a = torch.randn(size, device='cuda:0')
    
    start = time.time()
    b = a.to('cuda:1')
    torch.cuda.synchronize()
    end = time.time()
    
    bandwidth = size * 4 / (end - start) / 1024**3  # GB/s
    print(f'P2P bandwidth: {bandwidth:.2f} GB/s')
"
```

**Solutions:**
```bash
# Optimize NCCL settings
export NCCL_P2P_DISABLE=0
export NCCL_IB_DISABLE=1
export NCCL_SOCKET_IFNAME=eth0

# Use optimal topology
--tensor-parallel-size 2 --pipeline-parallel-size 2  # For 4 GPUs

# Check network configuration
ethtool eth0  # Check network interface settings
```

---

## Advanced Optimizations

### Custom Memory Management

```python
# advanced_memory_management.py

import torch
import gc
import psutil
import nvidia_ml_py3 as nvml

class MemoryManager:
    def __init__(self):
        nvml.nvmlInit()
        self.device_count = nvml.nvmlDeviceGetCount()
    
    def get_memory_info(self):
        """Get detailed memory information"""
        info = {}
        
        # System memory
        system_mem = psutil.virtual_memory()
        info['system'] = {
            'total': system_mem.total / 1024**3,
            'used': system_mem.used / 1024**3,
            'available': system_mem.available / 1024**3,
            'percent': system_mem.percent
        }
        
        # GPU memory
        info['gpus'] = []
        for i in range(self.device_count):
            handle = nvml.nvmlDeviceGetHandleByIndex(i)
            mem_info = nvml.nvmlDeviceGetMemoryInfo(handle)
            
            info['gpus'].append({
                'id': i,
                'total': mem_info.total / 1024**3,
                'used': mem_info.used / 1024**3,
                'free': mem_info.free / 1024**3,
                'utilization': mem_info.used / mem_info.total * 100
            })
        
        return info
    
    def optimize_memory(self):
        """Perform memory optimization"""
        # Clear Python garbage collector
        gc.collect()
        
        # Clear CUDA cache
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
            
            # Clear memory pool
            for i in range(torch.cuda.device_count()):
                with torch.cuda.device(i):
                    torch.cuda.empty_cache()
        
        print("Memory optimization completed")
    
    def monitor_memory_usage(self, interval=60):
        """Monitor memory usage continuously"""
        import time
        
        while True:
            info = self.get_memory_info()
            
            print(f"System Memory: {info['system']['percent']:.1f}% used")
            
            for gpu in info['gpus']:
                print(f"GPU {gpu['id']}: {gpu['utilization']:.1f}% "
                      f"({gpu['used']:.1f}GB/{gpu['total']:.1f}GB)")
            
            print("-" * 40)
            time.sleep(interval)

# Usage
if __name__ == "__main__":
    manager = MemoryManager()
    manager.optimize_memory()
    manager.monitor_memory_usage()
```

### Dynamic Configuration Adjustment

```python
# dynamic_config.py

import psutil
import nvidia_ml_py3 as nvml
import subprocess
import json

class DynamicConfig:
    def __init__(self):
        nvml.nvmlInit()
        self.gpu_count = nvml.nvmlDeviceGetCount()
    
    def assess_system_resources(self):
        """Assess current system resources"""
        # System memory
        system_mem = psutil.virtual_memory()
        
        # GPU memory
        gpu_memories = []
        for i in range(self.gpu_count):
            handle = nvml.nvmlDeviceGetHandleByIndex(i)
            mem_info = nvml.nvmlDeviceGetMemoryInfo(handle)
            gpu_memories.append(mem_info.total / 1024**3)
        
        return {
            'system_memory_gb': system_mem.total / 1024**3,
            'gpu_memories_gb': gpu_memories,
            'gpu_count': self.gpu_count
        }
    
    def recommend_configuration(self, target_context=None):
        """Recommend optimal configuration based on resources"""
        resources = self.assess_system_resources()
        
        # Determine optimal context length if not specified
        if target_context is None:
            avg_gpu_memory = sum(resources['gpu_memories_gb']) / len(resources['gpu_memories_gb'])
            
            if avg_gpu_memory >= 140:  # H200 class
                target_context = 700000
            elif avg_gpu_memory >= 80:  # A100 class
                target_context = 400000
            else:
                target_context = 200000
        
        # Determine parallelism strategy
        if target_context <= 300000:
            config = {
                'tensor_parallel_size': min(4, self.gpu_count),
                'pipeline_parallel_size': 1,
                'max_model_len': target_context,
                'gpu_memory_utilization': 0.90,
                'kv_cache_dtype': 'auto',
                'max_num_batched_tokens': 8192
            }
        elif target_context <= 500000:
            config = {
                'tensor_parallel_size': min(4, self.gpu_count),
                'pipeline_parallel_size': 1,
                'max_model_len': target_context,
                'gpu_memory_utilization': 0.95,
                'kv_cache_dtype': 'fp8',
                'max_num_batched_tokens': 6144
            }
        else:
            # High context configuration
            if self.gpu_count >= 4:
                config = {
                    'tensor_parallel_size': 2,
                    'pipeline_parallel_size': 2,
                    'max_model_len': target_context,
                    'gpu_memory_utilization': 0.98,
                    'kv_cache_dtype': 'fp8',
                    'max_num_batched_tokens': 4096
                }
            else:
                config = {
                    'tensor_parallel_size': self.gpu_count,
                    'pipeline_parallel_size': 1,
                    'max_model_len': min(target_context, 400000),
                    'gpu_memory_utilization': 0.95,
                    'kv_cache_dtype': 'fp8',
                    'max_num_batched_tokens': 4096
                }
        
        return config
    
    def generate_start_script(self, config, output_file='optimized_start.sh'):
        """Generate optimized start script"""
        script_content = f"""#!/bin/bash
# Auto-generated optimized vLLM configuration
# Generated based on system resources assessment

source /opt/vllm/bin/activate
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export VLLM_API_KEY="${{VLLM_API_KEY:-your-api-key-here}}"
export CUDA_VISIBLE_DEVICES=0,1,2,3

echo "Starting vLLM with optimized configuration:"
echo "  Context Length: {config['max_model_len']:,} tokens"
echo "  Tensor Parallel: {config['tensor_parallel_size']}"
echo "  Pipeline Parallel: {config['pipeline_parallel_size']}"
echo "  KV Cache: {config['kv_cache_dtype']}"
echo "  GPU Memory Util: {config['gpu_memory_utilization']}"

vllm serve /models/qwen3 \\
    --tensor-parallel-size {config['tensor_parallel_size']} \\
    --pipeline-parallel-size {config['pipeline_parallel_size']} \\
    --max-model-len {config['max_model_len']} \\
    --gpu-memory-utilization {config['gpu_memory_utilization']} \\
    --kv-cache-dtype {config['kv_cache_dtype']} \\
    --max-num-batched-tokens {config['max_num_batched_tokens']} \\
    --host 0.0.0.0 \\
    --port 8000 \\
    --api-key $VLLM_API_KEY \\
    --trust-remote-code \\
    2>&1 | tee /var/log/vllm/optimized.log
"""
        
        with open(output_file, 'w') as f:
            f.write(script_content)
        
        subprocess.run(['chmod', '+x', output_file])
        print(f"Optimized start script generated: {output_file}")
        
        return output_file

def main():
    config_manager = DynamicConfig()
    
    print("=== System Resource Assessment ===")
    resources = config_manager.assess_system_resources()
    print(f"System Memory: {resources['system_memory_gb']:.1f} GB")
    print(f"GPU Count: {resources['gpu_count']}")
    for i, gpu_mem in enumerate(resources['gpu_memories_gb']):
        print(f"GPU {i}: {gpu_mem:.1f} GB")
    
    print("\n=== Configuration Recommendations ===")
    
    # Generate configurations for different context lengths
    for context in [200000, 400000, 700000]:
        print(f"\nFor {context:,} token context:")
        config = config_manager.recommend_configuration(context)
        for key, value in config.items():
            print(f"  {key}: {value}")
    
    # Generate optimized start script
    optimal_config = config_manager.recommend_configuration()
    script_file = config_manager.generate_start_script(optimal_config)
    print(f"\nOptimized start script: {script_file}")

if __name__ == "__main__":
    main()
```

This performance guide provides comprehensive optimization strategies for the vLLM Qwen3-480B setup. The key to optimal performance is balancing context length requirements with available hardware resources, and continuously monitoring system performance to identify bottlenecks.