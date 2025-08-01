#!/bin/bash

# Proven Environment Configuration for vLLM + Qwen3-480B
# Based on production deployment analysis from chathistory5.md

# =============================================================================
# CORE VLLM ENVIRONMENT VARIABLES (TESTED AND PROVEN)
# =============================================================================

# Force V0 engine for better memory efficiency (CRITICAL)
export VLLM_USE_V1=0

# API authentication key (tested working)
export VLLM_API_KEY='qwen3-secret-key'

# Enable long context support (required for >32k tokens)
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1

# GPU configuration for 4x H200 setup
export CUDA_VISIBLE_DEVICES=0,1,2,3

# Disable memory-hungry compilation features for stability
export VLLM_TORCH_COMPILE_LEVEL=0

# =============================================================================
# PROVEN VLLM LAUNCH PARAMETERS
# =============================================================================

# Standard Production Configuration (200k context)
# Performance: ~75 tokens/second, 0.87s response time
VLLM_STANDARD_ARGS=(
    --served-model-name qwen3                # Simplified model name (CRITICAL)
    --tensor-parallel-size 4                 # 4-GPU tensor parallelism
    --max-model-len 200000                   # 200k token context window
    --host 0.0.0.0                          # Accept external connections
    --port 8000                              # Standard port
    --gpu-memory-utilization 0.95           # Stable GPU memory usage
    --enforce-eager                          # Disable graph compilation
    --trust-remote-code                      # Allow custom model code
)

# High-Context Configuration (700k context)
# Memory optimized with FP8 cache and pipeline parallelism
VLLM_HIGHCONTEXT_ARGS=(
    --tensor-parallel-size 2                 # Lower TP for memory efficiency
    --pipeline-parallel-size 2               # Pipeline parallelism
    --max-model-len 700000                   # Maximum stable context
    --kv-cache-dtype fp8                     # FP8 KV cache for memory efficiency
    --host 0.0.0.0
    --port 8000
    --gpu-memory-utilization 0.98           # Maximum GPU memory usage
    --trust-remote-code
)

# =============================================================================
# CLIENT CONFIGURATION (CRUSH CLI)
# =============================================================================

# OpenAI-compatible API settings for CRUSH
export OPENAI_API_KEY='qwen3-secret-key'
export OPENAI_API_BASE='http://localhost:8000/v1'

# =============================================================================
# PERFORMANCE BENCHMARKS (PROVEN IN PRODUCTION)
# =============================================================================

# Response latency: 0.87 seconds (excellent for 480B model)
# Token generation: ~75 tokens/second sustained
# Context windows: 200k standard, 700k maximum with optimizations
# Memory usage: 15.62 GiB KV cache at 200k context
# GPU utilization: 95-98% optimal range

# =============================================================================
# TROUBLESHOOTING REFERENCE
# =============================================================================

# Common Issues and Solutions:
# 1. HTTP 400 Bad Request: Use model ID 'qwen3', not '/models/qwen3'
# 2. HTTP 401 Unauthorized: Verify API key in both env var and --api-key
# 3. Memory issues: Use --kv-cache-dtype fp8 for large contexts
# 4. CRUSH "No providers": Create config at ~/.config/crush/config.json

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

start_vllm_standard() {
    echo "Starting vLLM with PROVEN standard configuration (200k context)..."
    echo "Expected performance: ~75 tokens/sec, 0.87s response time"
    
    source /opt/vllm/bin/activate
    vllm serve /models/qwen3 "${VLLM_STANDARD_ARGS[@]}" 2>&1 | tee /root/vllm_standard.log
}

start_vllm_highcontext() {
    echo "Starting vLLM with PROVEN high-context configuration (700k context)..."
    echo "Memory optimization: FP8 KV cache, Pipeline parallelism"
    
    source /opt/vllm/bin/activate
    vllm serve /models/qwen3 "${VLLM_HIGHCONTEXT_ARGS[@]}" 2>&1 | tee /root/vllm_highcontext.log
}

test_vllm_api() {
    echo "Testing vLLM API with proven working configuration..."
    
    # Test model endpoint
    curl -s http://localhost:8000/v1/models \
        -H "Authorization: Bearer qwen3-secret-key" | jq
    
    echo ""
    echo "Testing chat completion..."
    
    # Test chat completion
    curl -s http://localhost:8000/v1/chat/completions \
        -H "Authorization: Bearer qwen3-secret-key" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "qwen3",
            "messages": [{"role": "user", "content": "Hello, are you working?"}],
            "max_tokens": 20
        }' | jq -r '.choices[0].message.content'
}

setup_crush_config() {
    echo "Creating CRUSH configuration with proven settings..."
    
    mkdir -p ~/.config/crush
    cat > ~/.config/crush/config.json << 'EOF'
{
  "$schema": "https://charm.land/crush.json",
  "providers": {
    "vllm-local": {
      "type": "openai",
      "base_url": "http://localhost:8000/v1",
      "api_key": "qwen3-secret-key",
      "models": [
        {
          "id": "qwen3",
          "name": "Qwen3-480B Local (200k context)",
          "context_window": 200000,
          "default_max_tokens": 8192,
          "cost_per_1m_in": 0,
          "cost_per_1m_out": 0
        }
      ]
    }
  },
  "default_provider": "vllm-local",
  "default_model": "qwen3",
  "options": {
    "debug": false
  }
}
EOF
    
    echo "CRUSH configuration created at ~/.config/crush/config.json"
}

# =============================================================================
# USAGE EXAMPLES
# =============================================================================

# To use this configuration:
# 1. Source this file: source environment-proven.sh
# 2. Start vLLM: start_vllm_standard
# 3. Test API: test_vllm_api
# 4. Setup CRUSH: setup_crush_config
# 5. Launch CRUSH: crush

echo "Proven vLLM environment configuration loaded."
echo "Available functions:"
echo "  - start_vllm_standard    # Start with 200k context (recommended)"
echo "  - start_vllm_highcontext # Start with 700k context (memory intensive)"
echo "  - test_vllm_api         # Test API functionality"
echo "  - setup_crush_config    # Configure CRUSH CLI"
echo ""
echo "Performance expectations:"
echo "  - Response time: ~0.87 seconds"
echo "  - Token generation: ~75 tokens/second"
echo "  - Context window: 200k standard, 700k maximum"