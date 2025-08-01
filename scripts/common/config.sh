#!/bin/bash
#
# Configuration Management for vLLM Scripts
# Centralized configuration loading and validation
#
# Usage: source /path/to/scripts/common/config.sh
#
# Version: 1.0.0
# Author: Production Enhancement Script
# Created: $(date +"%Y-%m-%d")

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# =============================================================================
# CONFIGURATION PROFILES
# =============================================================================

# Default production configuration
setup_production_config() {
    export VLLM_ENV_PATH="/opt/vllm"
    export MODEL_PATH="/models/qwen3"
    export API_PORT=8000
    export GPU_MEMORY_UTIL=0.95
    export MAX_MODEL_LEN=200000
    export TENSOR_PARALLEL_SIZE=2
    export PIPELINE_PARALLEL_SIZE=2
    export KV_CACHE_DTYPE="fp8"
    export TRUST_REMOTE_CODE=true
    export DISABLE_LOG_REQUESTS=true
    export CUDA_VISIBLE_DEVICES="0,1,2,3"
    
    # Performance settings
    export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
    export VLLM_USE_V1=0
    export VLLM_TORCH_COMPILE_LEVEL=0
    
    log_debug "Production configuration loaded"
}

# Development/testing configuration
setup_development_config() {
    export VLLM_ENV_PATH="/opt/vllm"
    export MODEL_PATH="/models/qwen3"
    export API_PORT=8001
    export GPU_MEMORY_UTIL=0.85
    export MAX_MODEL_LEN=100000
    export TENSOR_PARALLEL_SIZE=2
    export PIPELINE_PARALLEL_SIZE=1
    export KV_CACHE_DTYPE="auto"
    export TRUST_REMOTE_CODE=true
    export DISABLE_LOG_REQUESTS=false
    export CUDA_VISIBLE_DEVICES="0,1"
    
    # Development settings
    export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
    export VLLM_USE_V1=0
    export VLLM_TORCH_COMPILE_LEVEL=0
    
    log_debug "Development configuration loaded"
}

# High-performance configuration for maximum throughput
setup_performance_config() {
    export VLLM_ENV_PATH="/opt/vllm"
    export MODEL_PATH="/models/qwen3"
    export API_PORT=8000
    export GPU_MEMORY_UTIL=0.98
    export MAX_MODEL_LEN=700000
    export TENSOR_PARALLEL_SIZE=2
    export PIPELINE_PARALLEL_SIZE=2
    export KV_CACHE_DTYPE="fp8"
    export TRUST_REMOTE_CODE=true
    export DISABLE_LOG_REQUESTS=true
    export CUDA_VISIBLE_DEVICES="0,1,2,3"
    
    # High-performance settings
    export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
    export VLLM_USE_V1=0
    export VLLM_TORCH_COMPILE_LEVEL=0
    export MAX_NUM_SEQS=256
    export SWAP_SPACE=0
    export ENABLE_CHUNKED_PREFILL=true
    export MAX_NUM_BATCHED_TOKENS=32768
    
    # NCCL optimizations
    export NCCL_DEBUG=INFO
    export NCCL_P2P_DISABLE=0
    export NCCL_IB_DISABLE=1
    export NCCL_SOCKET_IFNAME=lo
    export NCCL_ALGO=Tree
    export NCCL_PROTO=Simple
    
    log_debug "High-performance configuration loaded"
}

# Memory-optimized configuration for limited resources
setup_memory_config() {
    export VLLM_ENV_PATH="/opt/vllm"
    export MODEL_PATH="/models/qwen3"
    export API_PORT=8000
    export GPU_MEMORY_UTIL=0.90
    export MAX_MODEL_LEN=50000
    export TENSOR_PARALLEL_SIZE=4
    export PIPELINE_PARALLEL_SIZE=1
    export KV_CACHE_DTYPE="fp8"
    export TRUST_REMOTE_CODE=true
    export DISABLE_LOG_REQUESTS=true
    export CUDA_VISIBLE_DEVICES="0,1,2,3"
    
    # Memory optimization settings
    export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
    export VLLM_USE_V1=0
    export VLLM_TORCH_COMPILE_LEVEL=0
    export MAX_NUM_SEQS=64
    export SWAP_SPACE=4
    
    log_debug "Memory-optimized configuration loaded"
}

# =============================================================================
# CONFIGURATION VALIDATION
# =============================================================================

# Validate vLLM environment
validate_vllm_environment() {
    log_info "Validating vLLM environment..."
    
    # Check virtual environment
    if ! validate_directory "$VLLM_ENV_PATH" "vLLM environment"; then
        return 1
    fi
    
    if ! validate_file "$VLLM_ENV_PATH/bin/activate" "vLLM activation script"; then
        return 1
    fi
    
    # Check if vLLM is installed
    if ! "$VLLM_ENV_PATH/bin/python" -c "import vllm" 2>/dev/null; then
        log_error "vLLM not installed in environment: $VLLM_ENV_PATH"
        return 1
    fi
    
    log_success "vLLM environment validation passed"
    return 0
}

# Validate model configuration
validate_model_config() {
    log_info "Validating model configuration..."
    
    # Check model directory
    if ! validate_directory "$MODEL_PATH" "Model directory"; then
        return 1
    fi
    
    # Check for required model files
    local required_files=(
        "config.json"
        "tokenizer.json"
        "tokenizer_config.json"
    )
    
    for file in "${required_files[@]}"; do
        if ! validate_file "$MODEL_PATH/$file" "Model file ($file)"; then
            log_warning "Model file missing: $file (may still work)"
        fi
    done
    
    # Check model size
    local model_size
    model_size=$(du -sb "$MODEL_PATH" 2>/dev/null | cut -f1)
    if [[ -n "$model_size" ]]; then
        local human_size
        human_size=$(human_readable_size "$model_size")
        log_info "Model size: $human_size"
        
        # Warn if model seems too small
        if (( model_size < 100000000000 )); then  # Less than 100GB
            log_warning "Model size seems small for Qwen3-480B ($human_size)"
        fi
    fi
    
    log_success "Model configuration validation passed"
    return 0
}

# Validate system resources
validate_system_resources() {
    log_info "Validating system resources..."
    
    # Check GPU requirements
    local required_gpus=4
    if [[ -n "${CUDA_VISIBLE_DEVICES:-}" ]]; then
        # Count GPUs in CUDA_VISIBLE_DEVICES
        IFS=',' read -ra gpu_array <<< "$CUDA_VISIBLE_DEVICES"
        required_gpus=${#gpu_array[@]}
    fi
    
    if ! validate_gpus "$required_gpus"; then
        return 1
    fi
    
    # Check GPU memory
    if command -v nvidia-smi &> /dev/null; then
        log_info "Checking GPU memory..."
        local gpu_count=0
        local total_gpu_memory=0
        
        while IFS= read -r memory; do
            ((gpu_count++))
            total_gpu_memory=$((total_gpu_memory + memory))
            
            if (( memory < 80000 )); then  # Less than 80GB
                log_warning "GPU $gpu_count has limited memory: ${memory}MB"
            fi
        done < <(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)
        
        log_info "Total GPU memory: ${total_gpu_memory}MB across $gpu_count GPUs"
        
        # Estimate memory requirements
        local estimated_model_memory=500000  # ~500GB for Qwen3-480B
        local available_memory=$((total_gpu_memory * GPU_MEMORY_UTIL))
        available_memory=${available_memory%.*}  # Remove decimal part
        
        if (( available_memory < estimated_model_memory )); then
            log_warning "GPU memory may be insufficient"
            log_warning "  Estimated model needs: ${estimated_model_memory}MB"
            log_warning "  Available (${GPU_MEMORY_UTIL}% util): ${available_memory}MB"
        fi
    fi
    
    # Check system memory
    local total_ram_gb
    total_ram_gb=$(free -g | awk '/^Mem:/ {print $2}')
    if (( total_ram_gb < 200 )); then
        log_warning "System RAM may be insufficient: ${total_ram_gb}GB (recommended: 500GB+)"
    fi
    
    # Check disk space
    local model_disk_usage
    model_disk_usage=$(df "$MODEL_PATH" | awk 'NR==2 {print $4}')
    if (( model_disk_usage < 1000000000 )); then  # Less than 1TB available
        log_warning "Low disk space available: $(human_readable_size $((model_disk_usage * 1024)))"
    fi
    
    log_success "System resources validation completed"
    return 0
}

# Validate network configuration
validate_network_config() {
    log_info "Validating network configuration..."
    
    # Check if port is available
    if ! validate_port "$API_PORT" "API port"; then
        log_warning "Port $API_PORT may be in use - server startup may fail"
    fi
    
    # Check firewall status (if applicable)
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        log_info "UFW firewall is active - ensure port $API_PORT is allowed"
    fi
    
    log_success "Network configuration validation passed"
    return 0
}

# Comprehensive configuration validation
validate_full_config() {
    log_info "Starting comprehensive configuration validation..."
    
    local validation_errors=0
    
    # Run all validations
    validate_vllm_environment || ((validation_errors++))
    validate_model_config || ((validation_errors++))
    validate_system_resources || ((validation_errors++))
    validate_network_config || ((validation_errors++))
    
    if (( validation_errors == 0 )); then
        log_success "All configuration validations passed"
        return 0
    else
        log_error "Configuration validation failed with $validation_errors errors"
        return 1
    fi
}

# =============================================================================
# CONFIGURATION LOADING
# =============================================================================

# Load configuration by profile name
load_config_profile() {
    local profile="${1:-production}"
    
    log_info "Loading configuration profile: $profile"
    
    case "$profile" in
        "production"|"prod")
            setup_production_config
            ;;
        "development"|"dev")
            setup_development_config
            ;;
        "performance"|"perf"|"high-perf")
            setup_performance_config
            ;;
        "memory"|"mem")
            setup_memory_config
            ;;
        *)
            log_error "Unknown configuration profile: $profile"
            log_error "Available profiles: production, development, performance, memory"
            return 1
            ;;
    esac
    
    # Set profile name for reference
    export CONFIG_PROFILE="$profile"
    
    log_success "Configuration profile loaded: $profile"
    return 0
}

# Load configuration from file with fallback to profile
load_config_with_fallback() {
    local config_file="${1:-}"
    local fallback_profile="${2:-production}"
    
    if [[ -n "$config_file" ]]; then
        if load_config "$config_file"; then
            log_success "Configuration loaded from file: $config_file"
            return 0
        else
            log_warning "Failed to load config file, falling back to profile: $fallback_profile"
        fi
    fi
    
    load_config_profile "$fallback_profile"
}

# Show current configuration
show_current_config() {
    echo "=== Current vLLM Configuration ==="
    echo "Profile: ${CONFIG_PROFILE:-custom}"
    echo "Environment Path: ${VLLM_ENV_PATH:-unset}"
    echo "Model Path: ${MODEL_PATH:-unset}"
    echo "API Port: ${API_PORT:-unset}"
    echo "GPU Memory Utilization: ${GPU_MEMORY_UTIL:-unset}"
    echo "Max Model Length: ${MAX_MODEL_LEN:-unset}"
    echo "Tensor Parallel Size: ${TENSOR_PARALLEL_SIZE:-unset}"
    echo "Pipeline Parallel Size: ${PIPELINE_PARALLEL_SIZE:-unset}"
    echo "KV Cache Dtype: ${KV_CACHE_DTYPE:-unset}"
    echo "CUDA Visible Devices: ${CUDA_VISIBLE_DEVICES:-unset}"
    echo "Trust Remote Code: ${TRUST_REMOTE_CODE:-unset}"
    echo "================================="
}

# Generate configuration file from current settings
generate_config_file() {
    local output_file="${1:-vllm_config_${TIMESTAMP}.sh}"
    
    log_info "Generating configuration file: $output_file"
    
    cat > "$output_file" << EOF
#!/bin/bash
# vLLM Configuration File
# Generated on: $(date -Iseconds)
# Profile: ${CONFIG_PROFILE:-custom}

# =============================================================================
# CORE CONFIGURATION
# =============================================================================

export VLLM_ENV_PATH="${VLLM_ENV_PATH:-/opt/vllm}"
export MODEL_PATH="${MODEL_PATH:-/models/qwen3}"
export API_PORT="${API_PORT:-8000}"
export GPU_MEMORY_UTIL="${GPU_MEMORY_UTIL:-0.95}"
export MAX_MODEL_LEN="${MAX_MODEL_LEN:-200000}"

# =============================================================================
# PARALLELIZATION SETTINGS
# =============================================================================

export TENSOR_PARALLEL_SIZE="${TENSOR_PARALLEL_SIZE:-2}"
export PIPELINE_PARALLEL_SIZE="${PIPELINE_PARALLEL_SIZE:-2}"
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0,1,2,3}"

# =============================================================================
# MODEL SETTINGS
# =============================================================================

export KV_CACHE_DTYPE="${KV_CACHE_DTYPE:-fp8}"
export TRUST_REMOTE_CODE="${TRUST_REMOTE_CODE:-true}"
export DISABLE_LOG_REQUESTS="${DISABLE_LOG_REQUESTS:-true}"

# =============================================================================
# PERFORMANCE SETTINGS
# =============================================================================

export VLLM_ALLOW_LONG_MAX_MODEL_LEN="${VLLM_ALLOW_LONG_MAX_MODEL_LEN:-1}"
export VLLM_USE_V1="${VLLM_USE_V1:-0}"
export VLLM_TORCH_COMPILE_LEVEL="${VLLM_TORCH_COMPILE_LEVEL:-0}"

# =============================================================================
# OPTIONAL SETTINGS
# =============================================================================

# Uncomment and modify as needed
# export MAX_NUM_SEQS="${MAX_NUM_SEQS:-256}"
# export SWAP_SPACE="${SWAP_SPACE:-0}"
# export ENABLE_CHUNKED_PREFILL="${ENABLE_CHUNKED_PREFILL:-true}"
# export MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-32768}"

# =============================================================================
# NCCL SETTINGS (for multi-GPU setups)
# =============================================================================

# export NCCL_DEBUG="${NCCL_DEBUG:-INFO}"
# export NCCL_P2P_DISABLE="${NCCL_P2P_DISABLE:-0}"
# export NCCL_IB_DISABLE="${NCCL_IB_DISABLE:-1}"
# export NCCL_SOCKET_IFNAME="${NCCL_SOCKET_IFNAME:-lo}"
# export NCCL_ALGO="${NCCL_ALGO:-Tree}"
# export NCCL_PROTO="${NCCL_PROTO:-Simple}"

EOF
    
    chmod +x "$output_file"
    log_success "Configuration file generated: $output_file"
}

# =============================================================================
# ENVIRONMENT VARIABLE UTILITIES
# =============================================================================

# Set API key with validation
set_api_key() {
    local api_key="$1"
    
    if [[ -z "$api_key" ]]; then
        log_error "API key cannot be empty"
        return 1
    fi
    
    if [[ "$api_key" == "YOUR_API_KEY_HERE" ]]; then
        log_error "Please set a real API key (not the placeholder)"
        return 1
    fi
    
    export VLLM_API_KEY="$api_key"
    log_success "API key set (${api_key:0:8}...)"
    return 0
}

# Get build arguments for vLLM command
get_vllm_args() {
    local args=()
    
    # Model path (positional argument)
    args+=("$MODEL_PATH")
    
    # Core settings
    args+=("--host" "0.0.0.0")
    args+=("--port" "$API_PORT")
    args+=("--gpu-memory-utilization" "$GPU_MEMORY_UTIL")
    args+=("--max-model-len" "$MAX_MODEL_LEN")
    
    # Parallelization settings
    if [[ -n "${TENSOR_PARALLEL_SIZE:-}" && "$TENSOR_PARALLEL_SIZE" -gt 1 ]]; then
        args+=("--tensor-parallel-size" "$TENSOR_PARALLEL_SIZE")
    fi
    
    if [[ -n "${PIPELINE_PARALLEL_SIZE:-}" && "$PIPELINE_PARALLEL_SIZE" -gt 1 ]]; then
        args+=("--pipeline-parallel-size" "$PIPELINE_PARALLEL_SIZE")
    fi
    
    # Model settings
    if [[ -n "${KV_CACHE_DTYPE:-}" ]]; then
        args+=("--kv-cache-dtype" "$KV_CACHE_DTYPE")
    fi
    
    if [[ "${TRUST_REMOTE_CODE:-}" == "true" ]]; then
        args+=("--trust-remote-code")
    fi
    
    # API settings
    if [[ -n "${VLLM_API_KEY:-}" ]]; then
        args+=("--api-key" "$VLLM_API_KEY")
    fi
    
    if [[ "${DISABLE_LOG_REQUESTS:-}" == "true" ]]; then
        args+=("--disable-log-requests")
    fi
    
    # Optional performance settings
    if [[ -n "${MAX_NUM_SEQS:-}" ]]; then
        args+=("--max-num-seqs" "$MAX_NUM_SEQS")
    fi
    
    if [[ -n "${SWAP_SPACE:-}" ]]; then
        args+=("--swap-space" "$SWAP_SPACE")
    fi
    
    if [[ "${ENABLE_CHUNKED_PREFILL:-}" == "true" ]]; then
        args+=("--enable-chunked-prefill")
    fi
    
    if [[ -n "${MAX_NUM_BATCHED_TOKENS:-}" ]]; then
        args+=("--max-num-batched-tokens" "$MAX_NUM_BATCHED_TOKENS")
    fi
    
    printf "%s\n" "${args[@]}"
}

# =============================================================================
# EXPORTS
# =============================================================================

# Export configuration functions
export -f setup_production_config setup_development_config setup_performance_config setup_memory_config
export -f validate_vllm_environment validate_model_config validate_system_resources validate_network_config validate_full_config
export -f load_config_profile load_config_with_fallback show_current_config generate_config_file
export -f set_api_key get_vllm_args

log_debug "Configuration management library loaded"