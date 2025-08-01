# Technical Insights Documentation

This repository contains comprehensive technical documentation and proven configurations extracted from production deployment of Qwen3-480B with vLLM.

## 📋 Documentation Overview

### Core Documentation
- **[Technical Insights](docs/technical-insights.md)** - Comprehensive analysis of vLLM configuration, performance metrics, and troubleshooting
- **[Environment Configuration](configs/environment-proven.sh)** - Proven environment variables and launch parameters
- **[CRUSH Configuration](configs/crush-config.json)** - Working CRUSH CLI configuration with performance notes

### Production Scripts
- **[Standard Start Script](scripts/production/start_qwen3.sh)** - 200k context, optimal performance
- **[High-Context Script](scripts/production/start_700k_final.sh)** - 700k context, memory optimized
- **[Troubleshooting Script](scripts/troubleshoot-vllm.sh)** - Comprehensive diagnostic tool
- **[Performance Test Suite](scripts/performance-test-suite.sh)** - Complete performance benchmarking

## 🚀 Key Performance Metrics (Proven in Production)

| Metric | Value | Notes |
|--------|-------|-------|
| **Response Time** | 0.87 seconds | Excellent for 480B model |
| **Token Generation** | 75 tokens/second | Sustained performance |
| **Context Window** | 200k tokens | Standard configuration |
| **Max Context** | 700k tokens | With FP8 optimization |
| **Memory Usage** | 15.62 GiB | KV cache at 200k context |
| **GPU Utilization** | 95-98% | Optimal range |

## 🔧 Quick Start Guide

### 1. Server Setup (H200 Machine)
```bash
# Use proven environment configuration
source configs/environment-proven.sh

# Start with standard configuration (recommended)
start_vllm_standard

# OR start with high-context configuration
start_vllm_highcontext
```

### 2. Client Setup (Local Machine)
```bash
# Setup CRUSH configuration
source configs/environment-proven.sh
setup_crush_config

# Launch CRUSH
crush
```

### 3. Testing and Troubleshooting
```bash
# Test API functionality
./scripts/troubleshoot-vllm.sh

# Run performance benchmarks
./scripts/performance-test-suite.sh
```

## 🛠️ Proven Configurations

### Standard Production (200k Context)
- **Tensor Parallelism**: 4 GPUs
- **Context Window**: 200,000 tokens
- **GPU Memory**: 95% utilization
- **Performance**: 75 tokens/sec, 0.87s response time

### High-Context Production (700k Context)
- **Tensor Parallelism**: 2 GPUs
- **Pipeline Parallelism**: 2 stages
- **Context Window**: 700,000 tokens
- **KV Cache**: FP8 for memory efficiency
- **GPU Memory**: 98% utilization

## 🐛 Common Issues and Solutions

| Issue | Symptoms | Solution |
|-------|----------|----------|
| **HTTP 400 Bad Request** | CRUSH reaches server but fails | Use model ID `qwen3`, not `/models/qwen3` |
| **HTTP 401 Unauthorized** | Authentication failures | Verify API key format: `Bearer qwen3-secret-key` |
| **No providers configured** | CRUSH configuration warnings | Create config at `~/.config/crush/config.json` |
| **Memory issues** | OOM errors, crashes | Use `--kv-cache-dtype fp8` for large contexts |

## 📊 Performance Optimization Guidelines

### For Maximum Speed (200k tokens)
```bash
--tensor-parallel-size 4
--max-model-len 200000
--gpu-memory-utilization 0.95
--enforce-eager
```

### For Maximum Context (700k tokens)
```bash
--tensor-parallel-size 2
--pipeline-parallel-size 2
--kv-cache-dtype fp8
--gpu-memory-utilization 0.98
```

## 🔍 API Testing Commands

### Quick API Test
```bash
# Test model availability
curl -s http://localhost:8000/v1/models -H "Authorization: Bearer qwen3-secret-key" | jq

# Test chat completion
curl -s http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer qwen3-secret-key" \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen3", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 20}' \
  | jq -r '.choices[0].message.content'
```

### Performance Test
```bash
# Measure token generation speed
time curl -s http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer qwen3-secret-key" \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen3", "messages": [{"role": "user", "content": "Write a Python function"}], "max_tokens": 200}' \
  | jq '.usage'
```

## 📁 File Structure

```
├── docs/
│   └── technical-insights.md          # Comprehensive technical documentation
├── configs/
│   ├── crush-config.json              # Working CRUSH configuration
│   ├── environment-template.sh        # Template environment variables
│   └── environment-proven.sh          # Proven environment configuration
├── scripts/
│   ├── production/
│   │   ├── start_qwen3.sh             # Standard 200k context
│   │   └── start_700k_final.sh        # High-context 700k
│   ├── troubleshoot-vllm.sh           # Diagnostic and troubleshooting
│   └── performance-test-suite.sh      # Comprehensive performance tests
└── README-technical-insights.md       # This file
```

## 🎯 Next Steps

1. **Deployment**: Use proven configurations for consistent results
2. **Monitoring**: Implement performance monitoring based on benchmarks
3. **Optimization**: Fine-tune based on specific use cases
4. **Scaling**: Consider multi-instance deployment for higher throughput

## 📝 Notes

- All configurations are based on production deployment analysis
- Performance metrics are measured on 4x H200 GPU setup
- CRUSH CLI integration tested and working
- Troubleshooting scripts include common issue resolution

---

*Documentation generated from production deployment analysis - Last updated: July 31, 2025*