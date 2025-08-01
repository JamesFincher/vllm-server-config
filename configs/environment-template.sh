#!/bin/bash
# Environment Configuration Template for vLLM + Client Setup
# Copy this file and customize for your specific deployment

# =============================================================================
# SERVER CONFIGURATION (for the GPU server running vLLM)
# =============================================================================

# vLLM Server Settings
export VLLM_API_KEY='YOUR_API_KEY_HERE'                # Change this to your secret key
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1                 # Enable extended context
export VLLM_USE_V1=0                                   # Use V0 engine for better memory efficiency
export VLLM_TORCH_COMPILE_LEVEL=0                      # Disable memory-hungry features

# GPU Configuration  
export CUDA_VISIBLE_DEVICES=0,1,2,3                    # Which GPUs to use
export NVIDIA_VISIBLE_DEVICES=0,1,2,3                  # Alternative GPU specification

# Model Configuration
export MODEL_PATH="/models/qwen3"                      # Path to model files
export MAX_MODEL_LENGTH=200000                         # Maximum context length
export GPU_MEMORY_UTILIZATION=0.95                     # GPU memory usage (0.95 = 95%)

# =============================================================================
# CLIENT CONFIGURATION (for local machine connecting via SSH tunnel)
# =============================================================================

# SSH Connection Settings
export SSH_KEY="$HOME/.ssh/YOUR_SSH_KEY"               # Path to SSH private key
export SERVER_IP="YOUR_SERVER_IP"                      # Remote server IP address
export SERVER_PORT="22"                                # SSH port
export API_PORT="8000"                                 # vLLM API port

# Local API Settings (after SSH tunnel is established)
export OPENAI_API_KEY="YOUR_API_KEY_HERE"              # Same as VLLM_API_KEY
export OPENAI_API_BASE="http://localhost:8000/v1"      # Local tunneled endpoint

# CRUSH Configuration Directory
export CRUSH_CONFIG_DIR="$HOME/.config/crush"          # CRUSH config location

# =============================================================================
# NETWORK CONFIGURATION
# =============================================================================

# SSH Tunnel Configuration
export TUNNEL_PID_FILE="$HOME/.vllm_tunnel.pid"        # PID file for tunnel process
export LOCAL_PORT=8000                                 # Local port for tunnel
export REMOTE_PORT=8000                                 # Remote port for tunnel

# =============================================================================
# PERFORMANCE TUNING
# =============================================================================

# vLLM Performance Settings
export VLLM_WORKER_MULTIPROC_METHOD=spawn             # Process spawning method
export VLLM_ENGINE_ITERATION_TIMEOUT_S=60             # Engine timeout

# System Performance
export OMP_NUM_THREADS=1                               # Reduce CPU thread contention
export TOKENIZERS_PARALLELISM=false                    # Disable tokenizer parallelism warnings

# =============================================================================
# LOGGING AND DEBUGGING
# =============================================================================

# Log Configuration
export VLLM_LOG_LEVEL=INFO                            # Logging level (DEBUG, INFO, WARNING, ERROR)
export LOG_DIR="/var/log/vllm"                        # Log directory
export ENABLE_DEBUG_LOGGING=false                     # Enable detailed debugging

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Function to validate required environment variables
validate_environment() {
    local missing_vars=()
    
    # Check server-side variables
    if [[ -z "$VLLM_API_KEY" || "$VLLM_API_KEY" == "YOUR_API_KEY_HERE" ]]; then
        missing_vars+=("VLLM_API_KEY")
    fi
    
    # Check client-side variables if applicable
    if [[ -n "$SSH_KEY" && "$SSH_KEY" == *"YOUR_SSH_KEY"* ]]; then
        missing_vars+=("SSH_KEY")
    fi
    
    if [[ -n "$SERVER_IP" && "$SERVER_IP" == "YOUR_SERVER_IP" ]]; then
        missing_vars+=("SERVER_IP")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo "❌ Missing required environment variables:"
        printf '   - %s\n' "${missing_vars[@]}"
        echo ""
        echo "Please update this file with your actual values before using."
        return 1
    fi
    
    echo "✅ Environment validation passed"
    return 0
}

# Function to show current configuration
show_config() {
    echo "=== Current vLLM Configuration ==="
    echo "API Key: ${VLLM_API_KEY:0:10}... (truncated)"
    echo "Model Path: $MODEL_PATH"
    echo "Max Context: $MAX_MODEL_LENGTH tokens"
    echo "GPU Memory: ${GPU_MEMORY_UTILIZATION}%"
    echo "GPUs: $CUDA_VISIBLE_DEVICES"
    echo ""
    echo "=== Client Configuration ==="
    echo "Server: $SERVER_IP:$SERVER_PORT"
    echo "API Endpoint: $OPENAI_API_BASE"
    echo "SSH Key: $SSH_KEY"
}

# Function to setup CRUSH configuration
setup_crush_config() {
    if ! validate_environment; then
        return 1
    fi
    
    mkdir -p "$CRUSH_CONFIG_DIR"
    
    cat > "$CRUSH_CONFIG_DIR/config.json" << EOF
{
  "\$schema": "https://charm.land/crush.json",
  "providers": {
    "vllm-local": {
      "type": "openai",
      "base_url": "$OPENAI_API_BASE",
      "api_key": "$OPENAI_API_KEY",
      "models": [
        {
          "id": "qwen3",
          "name": "Qwen3-480B Local",
          "context_window": $MAX_MODEL_LENGTH,
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
    "debug": $([[ "$ENABLE_DEBUG_LOGGING" == "true" ]] && echo "true" || echo "false")
  }
}
EOF
    
    echo "✅ CRUSH configuration created at $CRUSH_CONFIG_DIR/config.json"
}

# =============================================================================
# USAGE EXAMPLES
# =============================================================================

# To use this file:
# 1. Copy to your desired location: cp environment-template.sh my-environment.sh
# 2. Edit my-environment.sh with your actual values
# 3. Source the file: source my-environment.sh
# 4. Validate configuration: validate_environment
# 5. Setup CRUSH: setup_crush_config

# Example usage in scripts:
# source /path/to/my-environment.sh
# if validate_environment; then
#     # Start your vLLM server or client
# fi