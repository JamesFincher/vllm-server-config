# vLLM Server Configuration for Qwen3-480B

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.10+](https://img.shields.io/badge/python-3.10+-blue.svg)](https://www.python.org/downloads/)
[![vLLM](https://img.shields.io/badge/vLLM-0.10.0-green.svg)](https://github.com/vllm-project/vllm)

A production-ready setup for running the Qwen3-Coder-480B-A35B-Instruct-FP8 model using vLLM with optimized configurations for maximum performance and context length. This configuration has been tested and optimized for 4x NVIDIA H200 GPUs, achieving up to 700,000 token context length.

## 📋 Table of Contents

- [Quick Start](#-quick-start)
- [Requirements](#-requirements)
- [Architecture](#️-architecture)
- [Repository Structure](#-repository-structure)
- [Configuration Options](#-configuration-options)
- [Alternative Configurations](#-alternative-configurations)
- [Monitoring](#-monitoring)
- [Troubleshooting](#-troubleshooting)
- [Security](#-security)
- [Documentation](#-documentation)
- [Contributing](#-contributing)
- [License](#-license)

## 🚀 Quick Start

### One-Command Deployment (Recommended)

The fastest way to get started with a complete automated deployment:

```bash
# Complete deployment with monitoring, backup, CI/CD, and recovery systems
sudo ./deploy.sh --api-key "your-secret-api-key"
```

### Master Control Interface

Use the unified control interface for all operations:

```bash
# Deployment
sudo ./vllm-control.sh deploy full --api-key "your-key"

# Monitoring
sudo ./vllm-control.sh monitor start
sudo ./vllm-control.sh monitor dashboard  # http://localhost:3000

# Backup Management
sudo ./vllm-control.sh backup create snapshot
sudo ./vllm-control.sh backup list

# System Information
sudo ./vllm-control.sh info system
sudo ./vllm-control.sh status

# Emergency Operations
sudo ./vllm-control.sh emergency
```

### Traditional Setup

```bash
# 1. Clone the repository
git clone <repository-url>
cd vllm-server-config

# 2. Run the automated setup (requires root)
sudo ./setup.sh

# 3. Set your API key
export VLLM_API_KEY='your-secret-api-key'

# 4. Start the server
./scripts/production/start-vllm-server.sh
```

Server will be available at `http://localhost:8000`

## 📋 Requirements

### Hardware
- **GPUs**: 4x NVIDIA H200 (140GB VRAM each) or equivalent
- **CPU**: High-core count CPU (tested with AMD EPYC 9654 96-Core)
- **RAM**: 700GB+ system memory
- **Storage**: 1TB+ (450GB for model files)

### Software
- **OS**: Ubuntu 22.04.5 LTS
- **CUDA**: 12.6+ 
- **Python**: 3.10+
- **NVIDIA Driver**: 570.133.20+

## 🏗️ Architecture

### Optimal Configuration (700k context)
Based on extensive testing, the production configuration uses:

- **Tensor Parallelism**: 2 (distributes model across 2 GPUs)
- **Pipeline Parallelism**: 2 (layers distributed across 2 stages)
- **KV Cache**: FP8 quantized (memory efficient)
- **Model Weights**: FP8 quantized
- **GPU Memory Utilization**: 98%
- **Max Context Length**: 700,000 tokens

### Performance Results
| Configuration | Max Context | Memory Usage | Status |
|---------------|-------------|--------------|---------|
| TP=4 | ~92k | Standard | ❌ Too small |
| TP=4 + FP8 KV | ~421k | FP8 KV cache | ❌ Insufficient |
| TP=2 + PP=2 + FP8 KV | **700k** | Optimized | ✅ **Production** |

## 📁 Repository Structure

```
├── setup.sh                          # Automated server setup
├── requirements.txt                  # Python dependencies
├── scripts/
│   ├── production/
│   │   ├── start-vllm-server.sh      # Production server startup
│   │   ├── start_700k_final.sh       # Tested 700k configuration
│   │   ├── start_pipeline.sh         # Pipeline parallelism config
│   │   └── start_qwen3.sh            # Basic startup script
│   ├── experimental/                 # Various tested configurations
│   ├── quick_setup.sh                # Rapid deployment script
│   └── system_check.sh               # System validation
├── configs/
│   ├── crush-config.json             # CRUSH client configuration
│   └── environment-template.sh       # Environment variables template
├── docs/
│   ├── setup-guide.md                # Comprehensive setup guide
│   └── api-reference.md              # API usage documentation
├── .gitignore                        # Git ignore patterns
└── README.md                         # This file
```

## 🔧 Configuration Options

### Environment Variables
```bash
export VLLM_API_KEY='your-api-key'           # Required: API authentication
export CUDA_VISIBLE_DEVICES='0,1,2,3'        # GPUs to use
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1       # Enable extended context
```

### Production Script Options
```bash
./scripts/production/start-vllm-server.sh \
    --context-length 700000 \
    --port 8000 \
    --api-key your-key
```

## 🐳 Alternative Configurations

### Basic Setup (Lower Memory)
```bash
# For systems with less GPU memory
./scripts/experimental/start_basic.sh
```

### Experimental Configurations
Various tested configurations available in `scripts/experimental/`:
- `start_fp8_kv.sh` - Aggressive FP8 quantization
- `start_nisten_*.sh` - High-performance variants
- `start_optimized.sh` - Memory-optimized setup

## 📊 Monitoring

### Real-time Monitoring
```bash
# Server logs
tail -f /var/log/vllm/vllm-*.log

# GPU usage
nvidia-smi -l 1
# or
nvtop

# Attach to server session
screen -r vllm_server
```

### System Service
```bash
# Start as system service
sudo systemctl start vllm-server
sudo systemctl enable vllm-server  # Auto-start on boot

# Check status
sudo systemctl status vllm-server
```

## 🔍 Troubleshooting

### Common Issues

**Out of Memory**
- Reduce `--max-model-len` (try 500000 or 400000)
- Lower `--gpu-memory-utilization` to 0.90
- Use more pipeline stages

**NCCL Communication Errors**
- Check `CUDA_VISIBLE_DEVICES`
- Verify all GPUs are visible: `nvidia-smi`
- Ensure GPUs support P2P communication

**Model Loading Failures**
- Verify model files in `/models/qwen3/`
- Check disk space (450GB+ required)
- Validate model integrity

**Slow Startup**
- Model loading takes 5-10 minutes (normal)
- Monitor GPU memory usage during startup
- Check system RAM availability

### Performance Optimization

**Network Tuning**
```bash
# Already included in setup.sh
echo 'net.core.rmem_max = 134217728' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 134217728' >> /etc/sysctl.conf
```

**GPU Settings**
```bash
# Enable persistence mode (auto-configured)
nvidia-smi -pm 1

# Check GPU topology
nvidia-smi topo -m
```

## 🔐 Security

All sensitive information has been sanitized:
- API keys → `YOUR_API_KEY_HERE`
- Server IPs → `YOUR_SERVER_IP`
- SSH keys → `your-ssh-key`

**Important**: Replace placeholders with your actual values before deployment.

## 📖 Documentation

- **[Setup Guide](docs/setup-guide.md)**: Comprehensive deployment instructions
- **[API Reference](docs/api-reference.md)**: API usage and examples
- **[Requirements](requirements.txt)**: Complete Python dependencies
- **[Environment Template](configs/environment-template.sh)**: Configuration template
- **Model Info**: Qwen3-Coder-480B-A35B-Instruct-FP8 from Hugging Face

## 🤝 Contributing

This configuration is based on production testing and optimization. Feel free to:
- Report issues with specific hardware configurations
- Submit optimizations for different GPU setups
- Add support for other large language models

## 📄 License

This configuration is provided for educational and development purposes. Please ensure compliance with:
- Model licensing terms (Qwen3 license)
- vLLM licensing (Apache 2.0)
- Your organization's deployment policies

## 🙏 Acknowledgments

Configuration optimized through extensive testing and based on:
- vLLM documentation and best practices
- Community feedback and optimizations
- Production deployment experience with 4x H200 GPUs

---

**Performance Note**: With the optimized configuration, expect:
- **Startup Time**: 5-10 minutes for model loading
- **Context Length**: Up to 700,000 tokens
- **Throughput**: ~15-20 tokens/second (depending on sequence length)
- **Memory Usage**: ~98% GPU utilization across 4x H200 GPUs