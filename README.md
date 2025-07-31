# vLLM Server Configuration for Large Language Models

This repository contains configuration files and scripts for running large language models (specifically Qwen3-480B) using vLLM on GPU servers.

## Contents

- **start_qwen3.sh** - Main startup script for Qwen3-480B model
- **server_recreation_blueprint_20250731_210707.md** - Comprehensive setup guide
- Various configuration scripts for different deployment scenarios
- System setup and optimization scripts

## Quick Start

1. Set up your environment variables:
   ```bash
   export VLLM_API_KEY='your-api-key-here'
   ```

2. Make the start script executable:
   ```bash
   chmod +x start_qwen3.sh
   ```

3. Run the server:
   ```bash
   ./start_qwen3.sh
   ```

## Requirements

- 4x NVIDIA H200 GPUs (or equivalent with sufficient VRAM)
- Ubuntu 22.04 LTS
- Python 3.10+
- CUDA 12.6+
- vLLM 0.10.0

## Configuration

The main configuration script (`start_qwen3.sh`) includes:

- Tensor parallelism across 4 GPUs
- 200k token context length
- FP8 model weights with FP16 KV cache
- Optimized GPU memory utilization

## Documentation

See `server_recreation_blueprint_20250731_210707.md` for complete setup instructions and troubleshooting guide.

## Security Note

All sensitive information (API keys, server IPs, SSH keys) has been replaced with placeholders. Update these with your actual values before deployment.

## License

This configuration is provided as-is for educational and development purposes.