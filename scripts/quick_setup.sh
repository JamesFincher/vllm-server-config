#!/bin/bash
#
# Quick Setup Script for vLLM with Qwen3-480B
# Enhanced with comprehensive error handling, logging, and user feedback
#
# Usage: ./quick_setup.sh [OPTIONS]
# Options:
#   --api-key <key>           Set API key (required if not in environment)
#   --port <port>             Set server port (default: 8000)
#   --context-length <length> Set max context length (default: 700000)
#   --gpu-util <ratio>        Set GPU memory utilization (default: 0.98)
#   --profile <name>          Use configuration profile (performance|production|dev|memory)
#   --verbose                 Enable verbose output
#   --debug                   Enable debug mode
#   --dry-run                 Show what would be done without executing
#   --help                    Show this help message
#
# Environment Variables:
#   VLLM_API_KEY             API key for authentication
#   CUDA_VISIBLE_DEVICES     GPU devices to use (default: 0,1,2,3)
#
# Version: 2.0.0
# Author: Production Enhancement Script

set -euo pipefail

# =============================================================================
# INITIALIZATION
# =============================================================================

# Get script directory and source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$SCRIPT_DIR/common"

# Source common utilities if available, otherwise use simplified functions
if [[ -f "$COMMON_DIR/utils.sh" ]]; then
    source "$COMMON_DIR/utils.sh"
    source "$COMMON_DIR/config.sh"
    USE_COMMON_UTILS=true
else
    USE_COMMON_UTILS=false
    
    # Simplified logging functions for standalone operation
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
    
    log_info() {
        echo -e "${BLUE}[INFO]${NC} $1"
    }
    
    log_success() {
        echo -e "${GREEN}[SUCCESS]${NC} $1"
    }
    
    log_warning() {
        echo -e "${YELLOW}[WARNING]${NC} $1"
    }
    
    log_error() {
        echo -e "${RED}[ERROR]${NC} $1"
    }
    
    confirm() {
        local message="${1:-Are you sure?}"
        local default="${2:-n}"
        
        local prompt
        if [[ "$default" == "y" ]]; then
            prompt="$message [Y/n]: "
        else
            prompt="$message [y/N]: "
        fi
        
        while true; do
            read -p "$prompt" -n 1 -r
            echo
            
            if [[ -z "$REPLY" ]]; then
                REPLY="$default"
            fi
            
            case "$REPLY" in
                [Yy]* ) return 0;;
                [Nn]* ) return 1;;
                * ) echo "Please answer yes or no.";;
            esac
        done
    }
fi

# Script configuration
readonly SCRIPT_NAME="quick_setup"
readonly SCRIPT_VERSION="2.0.0"
readonly DEFAULT_CONTEXT_LENGTH=700000
readonly DEFAULT_PORT=8000
readonly DEFAULT_GPU_UTIL=0.98
readonly DEFAULT_PROFILE="performance"

# =============================================================================
# COMMAND LINE ARGUMENT PARSING
# =============================================================================

show_help() {
    cat << EOF
Quick Setup Script for vLLM with Qwen3-480B v$SCRIPT_VERSION

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --api-key <key>           Set API key (required if not in environment)
    --port <port>             Set server port (default: $DEFAULT_PORT)
    --context-length <length> Set max context length (default: $DEFAULT_CONTEXT_LENGTH)
    --gpu-util <ratio>        Set GPU memory utilization (default: $DEFAULT_GPU_UTIL)
    --profile <name>          Use configuration profile:
                              - performance: High-throughput (700k context, FP8 cache)
                              - production: Stable settings (200k context, FP8 cache)
                              - dev: Development (100k context, auto cache)
                              - memory: Memory-optimized (50k context, FP8 cache)
    --verbose                 Enable verbose output
    --debug                   Enable debug mode
    --dry-run                 Show what would be done without executing
    --help                    Show this help message

ENVIRONMENT VARIABLES:
    VLLM_API_KEY             API key for authentication
    CUDA_VISIBLE_DEVICES     GPU devices to use (default: 0,1,2,3)

EXAMPLES:
    # Quick start with API key
    $0 --api-key mykey123

    # Start with custom settings
    $0 --api-key mykey123 --port 8001 --context-length 500000

    # Start with production profile
    $0 --profile production --api-key mykey123

    # Test configuration without starting
    $0 --dry-run --api-key mykey123

DESCRIPTION:
    This script provides a quick way to start vLLM with Qwen3-480B using
    optimized default settings. It performs basic validation and starts
    the server with high-performance configuration suitable for most use cases.

REQUIREMENTS:
    - vLLM environment at /opt/vllm
    - Qwen3 model at /models/qwen3
    - At least 4 GPUs with 140GB+ VRAM each
    - 700GB+ system RAM

For more advanced configuration options, use the production scripts:
    - ./production/start_qwen3.sh
    - ./production/start-vllm-server.sh
EOF
}

# Initialize variables with defaults
API_KEY="${VLLM_API_KEY:-}"
PORT="$DEFAULT_PORT"
CONTEXT_LENGTH="$DEFAULT_CONTEXT_LENGTH"
GPU_UTIL="$DEFAULT_GPU_UTIL"
PROFILE="$DEFAULT_PROFILE"
VERBOSE=false
DEBUG=false
DRY_RUN=false

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --api-key)
                API_KEY="$2"
                shift 2
                ;;
            --port)
                PORT="$2"
                shift 2
                ;;
            --context-length)
                CONTEXT_LENGTH="$2"
                shift 2
                ;;
            --gpu-util)
                GPU_UTIL="$2"
                shift 2
                ;;
            --profile)
                PROFILE="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --debug)
                DEBUG=true
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Validate required parameters
validate_parameters() {
    log_info "Validating parameters..."
    
    local errors=()
    
    # Check API key
    if [[ -z "$API_KEY" ]]; then
        errors+=("API key must be provided via --api-key or VLLM_API_KEY environment variable")
    elif [[ "$API_KEY" == "YOUR_API_KEY_HERE" ]]; then
        errors+=("Please set a real API key (not the placeholder)")
    fi
    
    # Check port
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
        errors+=("Invalid port: $PORT (must be 1-65535)")
    fi
    
    # Check context length
    if ! [[ "$CONTEXT_LENGTH" =~ ^[0-9]+$ ]] || (( CONTEXT_LENGTH < 1000 )); then
        errors+=("Invalid context length: $CONTEXT_LENGTH (must be >= 1000)")
    fi
    
    # Check GPU utilization
    if ! [[ "$GPU_UTIL" =~ ^0\.[0-9]+$ ]] && ! [[ "$GPU_UTIL" =~ ^1\.0+$ ]]; then
        errors+=("Invalid GPU utilization: $GPU_UTIL (must be 0.0-1.0)")
    fi
    
    # Check profile
    if [[ "$PROFILE" != "performance" && "$PROFILE" != "production" && 
          "$PROFILE" != "dev" && "$PROFILE" != "memory" ]]; then
        errors+=("Invalid profile: $PROFILE (must be performance|production|dev|memory)")
    fi
    
    if [[ ${#errors[@]} -ne 0 ]]; then
        log_error "Parameter validation failed:"
        printf "  - %s\n" "${errors[@]}"
        return 1
    fi
    
    log_success "Parameter validation passed"
    return 0
}

# Validate system requirements
validate_system() {
    log_info "Validating system requirements..."
    
    local warnings=()
    local errors=()
    
    # Check vLLM environment
    if [[ ! -f "/opt/vllm/bin/activate" ]]; then
        errors+=("vLLM virtual environment not found at /opt/vllm")
        errors+=("Please run the setup script first")
    fi
    
    # Check model directory
    if [[ ! -d "/models/qwen3" ]]; then
        errors+=("Model directory not found at /models/qwen3")
        errors+=("Please download the model first")
    fi
    
    # Check GPU availability
    if command -v nvidia-smi &> /dev/null; then
        local gpu_count
        gpu_count=$(nvidia-smi --list-gpus 2>/dev/null | wc -l || echo "0")
        
        if (( gpu_count == 0 )); then
            errors+=("No NVIDIA GPUs detected")
        elif (( gpu_count < 4 )); then
            warnings+=("Only $gpu_count GPU(s) detected. Qwen3-480B works best with 4+ GPUs")
        fi
        
        # Check GPU memory
        if (( gpu_count > 0 )); then
            local min_memory=0
            while IFS= read -r memory; do
                if (( memory > 0 && (min_memory == 0 || memory < min_memory) )); then
                    min_memory=$memory
                fi
            done < <(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null || echo "0")
            
            if (( min_memory > 0 && min_memory < 80000 )); then
                warnings+=("GPU memory may be insufficient (minimum: ${min_memory}MB, recommended: 140GB+)")
            fi
        fi
    else
        warnings+=("nvidia-smi not found - cannot verify GPU requirements")
    fi
    
    # Check system memory
    if command -v free &> /dev/null; then
        local total_ram_gb
        total_ram_gb=$(free -g | awk '/^Mem:/ {print $2}')
        if (( total_ram_gb < 200 )); then
            warnings+=("System RAM may be insufficient: ${total_ram_gb}GB (recommended: 500GB+)")
        fi
    fi
    
    # Check port availability
    if command -v netstat &> /dev/null; then
        if netstat -tuln 2>/dev/null | grep -q ":$PORT "; then
            warnings+=("Port $PORT is already in use")
        fi
    fi
    
    # Display results
    if [[ ${#warnings[@]} -ne 0 ]]; then
        log_warning "System validation warnings:"
        printf "  - %s\n" "${warnings[@]}"
    fi
    
    if [[ ${#errors[@]} -ne 0 ]]; then
        log_error "System validation failed:"
        printf "  - %s\n" "${errors[@]}"
        return 1
    fi
    
    log_success "System validation passed"
    return 0
}

# =============================================================================
# CONFIGURATION FUNCTIONS
# =============================================================================

# Apply profile-specific settings
apply_profile_settings() {
    log_info "Applying profile settings: $PROFILE"
    
    case "$PROFILE" in
        "performance")
            # High-performance settings (already defaults)
            TENSOR_PARALLEL=2
            PIPELINE_PARALLEL=2
            KV_CACHE_DTYPE="fp8"
            ;;
        "production")
            # Stable production settings
            CONTEXT_LENGTH=200000
            GPU_UTIL=0.95
            TENSOR_PARALLEL=4
            PIPELINE_PARALLEL=1
            KV_CACHE_DTYPE="fp8"
            ;;
        "dev")
            # Development settings
            CONTEXT_LENGTH=100000
            GPU_UTIL=0.85
            TENSOR_PARALLEL=2
            PIPELINE_PARALLEL=1
            KV_CACHE_DTYPE="auto"
            ;;
        "memory")
            # Memory-optimized settings
            CONTEXT_LENGTH=50000
            GPU_UTIL=0.90
            TENSOR_PARALLEL=4
            PIPELINE_PARALLEL=1
            KV_CACHE_DTYPE="fp8"
            ;;
    esac
    
    log_info "Profile settings applied"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Core vLLM settings
    export VLLM_API_KEY="$API_KEY"
    export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
    export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0,1,2,3}"
    
    # Performance optimizations for high-performance profiles
    if [[ "$PROFILE" == "performance" ]]; then
        export NCCL_P2P_DISABLE=0
        export NCCL_IB_DISABLE=1
        export NCCL_SOCKET_IFNAME=lo
        export NCCL_ALGO=Tree
        export NCCL_PROTO=Simple
        export VLLM_FP8_E4M3_KV_CACHE=0
        export VLLM_FP8_KV_CACHE=0
    fi
    
    log_success "Environment variables set"
}

# =============================================================================
# SERVER MANAGEMENT
# =============================================================================

# Check if server is already running
check_existing_server() {
    log_info "Checking for existing vLLM server..."
    
    if pgrep -f "vllm serve" >/dev/null 2>&1; then
        log_warning "vLLM server is already running"
        
        local pids
        pids=$(pgrep -f "vllm serve")
        echo "Running processes:"
        echo "$pids" | while read -r pid; do
            if ps -p "$pid" >/dev/null 2>&1; then
                echo "  PID $pid: $(ps -p "$pid" -o command= 2>/dev/null | cut -c1-80)..."
            fi
        done
        
        if confirm "Stop existing server and continue?"; then
            log_info "Stopping existing server..."
            pkill -f "vllm serve" || true
            sleep 3
            
            # Clean up screen sessions
            screen -ls 2>/dev/null | grep vllm | cut -d. -f1 | awk '{print $1}' | \
            xargs -I {} screen -S {}.vllm -X quit 2>/dev/null || true
            
            log_success "Existing server stopped"
        else
            log_info "Keeping existing server running"
            return 1
        fi
    fi
    
    return 0
}

# Build vLLM command
build_vllm_command() {
    local cmd=(
        "vllm" "serve" "/models/qwen3"
        "--tensor-parallel-size" "$TENSOR_PARALLEL"
        "--pipeline-parallel-size" "$PIPELINE_PARALLEL"
        "--max-model-len" "$CONTEXT_LENGTH"
        "--kv-cache-dtype" "$KV_CACHE_DTYPE"
        "--host" "0.0.0.0"
        "--port" "$PORT"
        "--api-key" "$API_KEY"
        "--gpu-memory-utilization" "$GPU_UTIL"
        "--trust-remote-code"
    )
    
    # Add additional arguments based on profile
    if [[ "$PROFILE" == "performance" ]]; then
        cmd+=("--enable-chunked-prefill")
        cmd+=("--max-num-batched-tokens" "32768")
        cmd+=("--disable-log-requests")
    elif [[ "$PROFILE" == "production" ]]; then
        cmd+=("--served-model-name" "qwen3")
        cmd+=("--enforce-eager")
        cmd+=("--disable-log-requests")
    fi
    
    printf "%s " "${cmd[@]}"
}

# Start vLLM server
start_vllm_server() {
    log_info "Starting vLLM server with quick setup..."
    
    # Activate environment
    log_info "Activating vLLM environment..."
    source /opt/vllm/bin/activate
    
    # Verify vLLM is available
    if ! python -c "import vllm" 2>/dev/null; then
        log_error "vLLM not available in environment"
        return 1
    fi
    
    local vllm_version
    vllm_version=$(python -c "import vllm; print(vllm.__version__)" 2>/dev/null)
    log_info "vLLM version: $vllm_version"
    
    # Build command
    local vllm_cmd
    vllm_cmd=$(build_vllm_command)
    
    # Show configuration summary
    echo ""
    echo "=== Quick Setup Configuration ==="
    echo "Profile: $PROFILE"
    echo "Model: Qwen3-480B (FP8)"
    echo "Context Length: $CONTEXT_LENGTH tokens"
    echo "Port: $PORT"
    echo "GPU Memory Utilization: $GPU_UTIL"
    echo "Tensor Parallel: $TENSOR_PARALLEL"
    echo "Pipeline Parallel: $PIPELINE_PARALLEL"
    echo "KV Cache: $KV_CACHE_DTYPE"
    echo "GPUs: ${CUDA_VISIBLE_DEVICES:-0,1,2,3}"
    echo "Command: $vllm_cmd"
    echo "================================"
    echo ""
    
    # Confirm start
    if ! confirm "Start vLLM server with this configuration?" "y"; then
        log_info "Server start cancelled by user"
        return 1
    fi
    
    # Dry run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would execute command above"
        return 0
    fi
    
    # Create log directory
    mkdir -p /var/log/vllm
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local log_file="/var/log/vllm/quick_setup_${timestamp}.log"
    
    log_info "Starting server..."
    log_info "Log file: $log_file"
    log_info "This may take 5-10 minutes for model loading..."
    
    # Start in screen session for easy monitoring
    screen -dmS vllm_quick bash -c "
        source /opt/vllm/bin/activate
        export VLLM_API_KEY='$API_KEY'
        export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
        export CUDA_VISIBLE_DEVICES='${CUDA_VISIBLE_DEVICES:-0,1,2,3}'
        $(declare -p | grep '^declare -x NCCL' 2>/dev/null || true)
        $(declare -p | grep '^declare -x VLLM_FP8' 2>/dev/null || true)
        
        echo 'vLLM Quick Setup Starting at \$(date)' | tee '$log_file'
        echo 'Profile: $PROFILE' | tee -a '$log_file'
        echo 'Command: $vllm_cmd' | tee -a '$log_file'
        echo '======================================' | tee -a '$log_file'
        $vllm_cmd 2>&1 | tee -a '$log_file'
    "
    
    # Wait for screen to start
    sleep 2
    
    # Check if process started
    local server_pid
    server_pid=$(pgrep -f "vllm serve" | head -1)
    if [[ -n "$server_pid" ]]; then
        log_success "vLLM server started with PID: $server_pid"
        
        echo ""
        echo "=== Server Started ==="
        echo "PID: $server_pid"
        echo "Log: $log_file"
        echo "Screen session: vllm_quick"
        echo ""
        echo "Monitor progress:"
        echo "  tail -f $log_file"
        echo "  screen -r vllm_quick"
        echo ""
        echo "API will be available at: http://localhost:$PORT"
        echo "Model loading typically takes 5-10 minutes..."
        echo "====================="
        
        return 0
    else
        log_error "Failed to start vLLM server"
        log_error "Check the log file: $log_file"
        return 1
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Main function
main() {
    echo "=== vLLM Quick Setup v$SCRIPT_VERSION ==="
    echo "Starting Qwen3-480B with optimized configuration"
    echo ""
    
    # Parse arguments
    parse_arguments "$@"
    
    # Apply profile settings
    apply_profile_settings
    
    # Validate parameters and system
    if ! validate_parameters; then
        exit 1
    fi
    
    if ! validate_system; then
        log_error "System validation failed. Please check the requirements above."
        exit 1
    fi
    
    # Set up environment
    setup_environment
    
    # Check for existing server
    if ! check_existing_server; then
        exit 1
    fi
    
    # Show debug information if requested
    if [[ "$DEBUG" == "true" ]]; then
        echo ""
        echo "=== Debug Information ==="
        echo "Script directory: $SCRIPT_DIR"
        echo "Common utilities: $([[ "$USE_COMMON_UTILS" == "true" ]] && echo "available" || echo "not available")"
        echo "Environment variables:"
        env | grep -E "^(VLLM_|CUDA_|NCCL_)" | sort || echo "  None set"
        echo "========================="
        echo ""
    fi
    
    # Start the server
    if ! start_vllm_server; then
        log_error "Failed to start vLLM server"
        exit 1
    fi
    
    log_success "Quick setup completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Wait for model loading to complete (watch the log)"
    echo "2. Test the API: curl http://localhost:$PORT/v1/models"
    echo "3. Use the API endpoint: http://localhost:$PORT"
    echo ""
    echo "For more advanced management, use the production scripts:"
    echo "  ./production/start_qwen3.sh --help"
    echo "  ./production/start-vllm-server.sh --help"
}

# Run main function
main "$@"
