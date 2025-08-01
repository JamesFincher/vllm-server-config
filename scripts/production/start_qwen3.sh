#!/bin/bash
#
# Production vLLM Server Startup Script for Qwen3-480B
# Enhanced with comprehensive error handling, logging, and configuration management
#
# Usage: ./start_qwen3.sh [OPTIONS]
# Options:
#   --config <file>           Use custom configuration file
#   --profile <name>          Use configuration profile (production|dev|performance|memory)
#   --api-key <key>           Set API key (overrides config)
#   --port <port>             Set server port (overrides config)
#   --max-len <tokens>        Set maximum model length (overrides config)
#   --gpu-util <ratio>        Set GPU memory utilization (overrides config)
#   --verbose                 Enable verbose output
#   --debug                   Enable debug mode
#   --force                   Skip confirmations
#   --dry-run                 Show what would be done without executing
#   --help                    Show this help message
#
# Environment Variables:
#   VLLM_API_KEY             API key for authentication
#   CONFIG_PROFILE           Configuration profile to use
#   LOG_LEVEL                Logging level (DEBUG|INFO|WARNING|ERROR)
#
# Version: 2.0.0
# Author: Production Enhancement Script

set -euo pipefail

# =============================================================================
# INITIALIZATION
# =============================================================================

# Get script directory and source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$(dirname "$SCRIPT_DIR")/common"

# Source common utilities and configuration management
if [[ -f "$COMMON_DIR/utils.sh" ]]; then
    source "$COMMON_DIR/utils.sh"
else
    echo "Error: Common utilities not found at $COMMON_DIR/utils.sh"
    exit 1
fi

if [[ -f "$COMMON_DIR/config.sh" ]]; then
    source "$COMMON_DIR/config.sh"
else
    echo "Error: Configuration management not found at $COMMON_DIR/config.sh"
    exit 1
fi

# Script-specific configuration
readonly SCRIPT_NAME="start_qwen3"
readonly SCRIPT_VERSION="2.0.0"
readonly PID_FILE="$PID_DIR/vllm_server.pid"
readonly LOCK_FILE="/tmp/vllm_start.lock"

# =============================================================================
# COMMAND LINE ARGUMENT PARSING
# =============================================================================

show_help() {
    cat << EOF
Production vLLM Server Startup Script for Qwen3-480B v$SCRIPT_VERSION

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --config <file>           Use custom configuration file
    --profile <name>          Use configuration profile:
                              - production: Stable, production-ready settings
                              - dev: Development with lower resource usage
                              - performance: Maximum throughput configuration
                              - memory: Memory-optimized for limited resources
    --api-key <key>           Set API key (overrides config)
    --port <port>             Set server port (overrides config)
    --max-len <tokens>        Set maximum model length (overrides config)
    --gpu-util <ratio>        Set GPU memory utilization 0.0-1.0 (overrides config)
    --tensor-parallel <size>  Set tensor parallel size (overrides config)
    --pipeline-parallel <size> Set pipeline parallel size (overrides config)
    --kv-cache-dtype <type>   Set KV cache data type (fp8|fp16|auto)
    --verbose                 Enable verbose output
    --debug                   Enable debug mode with detailed logging
    --force                   Skip all confirmations
    --dry-run                 Show what would be done without executing
    --validate-only           Only validate configuration, don't start server
    --status                  Check server status
    --stop                    Stop running server
    --restart                 Restart server
    --help                    Show this help message

ENVIRONMENT VARIABLES:
    VLLM_API_KEY             API key for authentication (required)
    CONFIG_PROFILE           Default configuration profile
    LOG_LEVEL                Logging level (DEBUG|INFO|WARNING|ERROR)
    CUDA_VISIBLE_DEVICES     GPU devices to use (default: 0,1,2,3)

EXAMPLES:
    # Start with production configuration
    $0 --profile production --api-key mykey123

    # Start with custom configuration file
    $0 --config /path/to/my-config.sh

    # Start with performance optimizations
    $0 --profile performance --max-len 700000 --gpu-util 0.98

    # Check current server status
    $0 --status

    # Restart server with debug logging
    $0 --restart --debug

CONFIGURATION PROFILES:
    production  - Stable settings for production use (default)
                  200k context, FP8 cache, 95% GPU util
    
    dev         - Development settings with lower resource usage
                  100k context, auto cache, 85% GPU util
    
    performance - Maximum throughput configuration
                  700k context, FP8 cache, 98% GPU util
    
    memory      - Memory-optimized for limited resources
                  50k context, FP8 cache, 90% GPU util

For more information, see the documentation in the configs/ directory.
EOF
}

# Initialize variables with defaults
CONFIG_FILE=""
PROFILE="${CONFIG_PROFILE:-production}"
CUSTOM_API_KEY=""
CUSTOM_PORT=""
CUSTOM_MAX_LEN=""
CUSTOM_GPU_UTIL=""
CUSTOM_TENSOR_PARALLEL=""
CUSTOM_PIPELINE_PARALLEL=""
CUSTOM_KV_CACHE_DTYPE=""
VALIDATE_ONLY=false
CHECK_STATUS=false
STOP_SERVER=false
RESTART_SERVER=false

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --profile)
                PROFILE="$2"
                shift 2
                ;;
            --api-key)
                CUSTOM_API_KEY="$2"
                shift 2
                ;;
            --port)
                CUSTOM_PORT="$2"
                shift 2
                ;;
            --max-len)
                CUSTOM_MAX_LEN="$2"
                shift 2
                ;;
            --gpu-util)
                CUSTOM_GPU_UTIL="$2"
                shift 2
                ;;
            --tensor-parallel)
                CUSTOM_TENSOR_PARALLEL="$2"
                shift 2
                ;;
            --pipeline-parallel)
                CUSTOM_PIPELINE_PARALLEL="$2"
                shift 2
                ;;
            --kv-cache-dtype)
                CUSTOM_KV_CACHE_DTYPE="$2"
                shift 2
                ;;
            --validate-only)
                VALIDATE_ONLY=true
                shift
                ;;
            --status)
                CHECK_STATUS=true
                shift
                ;;
            --stop)
                STOP_SERVER=true
                shift
                ;;
            --restart)
                RESTART_SERVER=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--debug)
                DEBUG=true
                VERBOSE=true
                shift
                ;;
            -f|--force)
                FORCE=true
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
# CONFIGURATION MANAGEMENT
# =============================================================================

# Apply custom overrides to configuration
apply_custom_overrides() {
    [[ -n "$CUSTOM_API_KEY" ]] && export VLLM_API_KEY="$CUSTOM_API_KEY"
    [[ -n "$CUSTOM_PORT" ]] && export API_PORT="$CUSTOM_PORT"
    [[ -n "$CUSTOM_MAX_LEN" ]] && export MAX_MODEL_LEN="$CUSTOM_MAX_LEN"
    [[ -n "$CUSTOM_GPU_UTIL" ]] && export GPU_MEMORY_UTIL="$CUSTOM_GPU_UTIL"
    [[ -n "$CUSTOM_TENSOR_PARALLEL" ]] && export TENSOR_PARALLEL_SIZE="$CUSTOM_TENSOR_PARALLEL"
    [[ -n "$CUSTOM_PIPELINE_PARALLEL" ]] && export PIPELINE_PARALLEL_SIZE="$CUSTOM_PIPELINE_PARALLEL"
    [[ -n "$CUSTOM_KV_CACHE_DTYPE" ]] && export KV_CACHE_DTYPE="$CUSTOM_KV_CACHE_DTYPE"
    
    if [[ -n "$CUSTOM_API_KEY" || -n "$CUSTOM_PORT" || -n "$CUSTOM_MAX_LEN" || -n "$CUSTOM_GPU_UTIL" || 
          -n "$CUSTOM_TENSOR_PARALLEL" || -n "$CUSTOM_PIPELINE_PARALLEL" || -n "$CUSTOM_KV_CACHE_DTYPE" ]]; then
        log_info "Applied custom configuration overrides"
    fi
}

# Load and validate configuration
load_and_validate_config() {
    log_info "Loading configuration..."
    
    # Load configuration from file or profile
    if ! load_config_with_fallback "$CONFIG_FILE" "$PROFILE"; then
        log_error "Failed to load configuration"
        return 1
    fi
    
    # Apply custom overrides
    apply_custom_overrides
    
    # Validate configuration
    if ! validate_config; then
        log_error "Configuration validation failed"
        return 1
    fi
    
    # Validate full system if not just checking status
    if [[ "$CHECK_STATUS" != "true" && "$STOP_SERVER" != "true" ]]; then
        if ! validate_full_config; then
            log_error "System validation failed"
            return 1
        fi
    fi
    
    log_success "Configuration loaded and validated"
    return 0
}

# =============================================================================
# SERVER MANAGEMENT
# =============================================================================

# Check if vLLM server is running
check_server_status() {
    log_info "Checking vLLM server status..."
    
    local status="stopped"
    local pid=""
    local port_status="closed"
    local api_status="unreachable"
    
    # Check by process name
    if is_process_running "vllm serve" "$PID_FILE"; then
        status="running"
        
        # Get PID
        if [[ -f "$PID_FILE" ]]; then
            pid=$(cat "$PID_FILE" 2>/dev/null)
        else
            pid=$(pgrep -f "vllm serve" | head -1)
        fi
        
        # Check port
        if netstat -tuln 2>/dev/null | grep -q ":${API_PORT} "; then
            port_status="open"
            
            # Check API endpoint
            if curl -s --max-time 5 "http://localhost:${API_PORT}/health" >/dev/null 2>&1; then
                api_status="healthy"
            elif curl -s --max-time 5 "http://localhost:${API_PORT}/v1/models" >/dev/null 2>&1; then
                api_status="responding"
            else
                api_status="unhealthy"
            fi
        fi
    fi
    
    # Display status
    echo "=== vLLM Server Status ==="
    echo "Process: $status"
    [[ -n "$pid" ]] && echo "PID: $pid"
    echo "Port $API_PORT: $port_status"
    echo "API: $api_status"
    echo "Configuration: $PROFILE"
    echo "Model: $MODEL_PATH"
    echo "Max Context: $MAX_MODEL_LEN tokens"
    echo "GPU Utilization: $GPU_MEMORY_UTIL"
    echo "=========================="
    
    # Return status code
    [[ "$status" == "running" && "$api_status" == "healthy" ]]
}

# Stop vLLM server
stop_vllm_server() {
    log_info "Stopping vLLM server..."
    
    if ! is_process_running "vllm serve" "$PID_FILE"; then
        log_info "vLLM server is not running"
        return 0
    fi
    
    # Stop the process
    if stop_process "vllm serve" "$PID_FILE" 30; then
        log_success "vLLM server stopped successfully"
        
        # Clean up screen sessions
        screen -ls | grep vllm | cut -d. -f1 | awk '{print $1}' | \
        xargs -I {} screen -S {}.vllm -X quit 2>/dev/null || true
        
        return 0
    else
        log_error "Failed to stop vLLM server"
        return 1
    fi
}

# Activate vLLM environment
activate_vllm_environment() {
    log_info "Activating vLLM environment..."
    
    if [[ ! -f "$VLLM_ENV_PATH/bin/activate" ]]; then
        log_error "vLLM environment not found: $VLLM_ENV_PATH"
        return 1
    fi
    
    # Source the activation script in current shell
    source "$VLLM_ENV_PATH/bin/activate"
    
    # Verify vLLM is available
    if ! python -c "import vllm" 2>/dev/null; then
        log_error "vLLM not available in environment"
        return 1
    fi
    
    # Get version info
    local vllm_version
    vllm_version=$(python -c "import vllm; print(vllm.__version__)" 2>/dev/null)
    log_info "vLLM version: $vllm_version"
    
    log_success "vLLM environment activated"
    return 0
}

# Prepare environment variables for server
prepare_environment() {
    log_info "Preparing environment variables..."
    
    # Core environment variables
    export VLLM_USE_V1=0
    export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
    export VLLM_TORCH_COMPILE_LEVEL=0
    
    # Set CUDA devices
    export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0,1,2,3}"
    
    # Performance optimizations based on profile
    if [[ "$PROFILE" == "performance" ]]; then
        export NCCL_DEBUG=INFO
        export NCCL_P2P_DISABLE=0
        export NCCL_IB_DISABLE=1
        export NCCL_SOCKET_IFNAME=lo
        export NCCL_ALGO=Tree
        export NCCL_PROTO=Simple
        export VLLM_FP8_E4M3_KV_CACHE=0
        export VLLM_FP8_KV_CACHE=0
    fi
    
    log_debug "Environment variables prepared"
    return 0
}

# Build vLLM command
build_vllm_command() {
    log_debug "Building vLLM command..."
    
    local cmd_parts=()
    cmd_parts+=("vllm" "serve")
    
    # Add arguments from configuration
    local args
    mapfile -t args < <(get_vllm_args)
    cmd_parts+=("${args[@]}")
    
    # Add additional arguments based on profile
    if [[ "$PROFILE" == "production" ]]; then
        cmd_parts+=("--served-model-name" "qwen3")
        cmd_parts+=("--enforce-eager")
    fi
    
    echo "${cmd_parts[@]}"
}

# Start vLLM server
start_vllm_server() {
    log_info "Starting vLLM server with profile: $PROFILE"
    
    # Check if already running
    if is_process_running "vllm serve" "$PID_FILE"; then
        log_warning "vLLM server is already running"
        if ! confirm "Stop existing server and start new one?"; then
            return 1
        fi
        stop_vllm_server
    fi
    
    # Activate environment
    if ! activate_vllm_environment; then
        return 1
    fi
    
    # Prepare environment
    if ! prepare_environment; then
        return 1
    fi
    
    # Build command
    local vllm_cmd
    vllm_cmd=$(build_vllm_command)
    
    # Show configuration summary
    echo ""
    echo "=== Starting vLLM Server ==="
    echo "Profile: $PROFILE"
    echo "Model: $MODEL_PATH"
    echo "API Port: $API_PORT"
    echo "Max Context: $MAX_MODEL_LEN tokens"
    echo "GPU Memory: $GPU_MEMORY_UTIL"
    echo "Tensor Parallel: $TENSOR_PARALLEL_SIZE"
    echo "Pipeline Parallel: $PIPELINE_PARALLEL_SIZE"
    echo "KV Cache: $KV_CACHE_DTYPE"
    echo "GPUs: $CUDA_VISIBLE_DEVICES"
    echo "Command: $vllm_cmd"
    echo "============================"
    echo ""
    
    # Confirm start unless forced
    if ! confirm "Start vLLM server with this configuration?" "y"; then
        log_info "Server start cancelled by user"
        return 1
    fi
    
    # Dry run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would execute: $vllm_cmd"
        return 0
    fi
    
    # Create directories
    validate_directory "$PID_DIR" "PID directory" true
    validate_directory "$LOG_DIR" "Log directory" true
    
    # Create log file
    local log_file="$LOG_DIR/vllm_server_${TIMESTAMP}.log"
    
    # Start server in screen session
    log_info "Starting server in screen session..."
    log_info "Log file: $log_file"
    
    screen -dmS vllm_server bash -c "
        source '$VLLM_ENV_PATH/bin/activate'
        $(declare -p | grep '^declare -x')
        echo 'vLLM Server Starting at $(date)' | tee '$log_file'
        echo 'Configuration: $PROFILE' | tee -a '$log_file'
        echo 'Command: $vllm_cmd' | tee -a '$log_file'
        echo '===========================================' | tee -a '$log_file'
        $vllm_cmd 2>&1 | tee -a '$log_file'
    "
    
    # Wait a moment for screen to start
    sleep 2
    
    # Get and save PID
    local server_pid
    server_pid=$(pgrep -f "vllm serve" | head -1)
    if [[ -n "$server_pid" ]]; then
        echo "$server_pid" > "$PID_FILE"
        log_success "vLLM server started with PID: $server_pid"
    else
        log_error "Failed to start vLLM server"
        return 1
    fi
    
    # Show monitoring information
    echo ""
    echo "=== Server Started ==="
    echo "PID: $server_pid"
    echo "Log: $log_file"
    echo "Screen session: vllm_server"
    echo ""
    echo "Monitor progress:"
    echo "  tail -f $log_file"
    echo "  screen -r vllm_server"
    echo ""
    echo "Check status:"
    echo "  $0 --status"
    echo ""
    echo "API will be available at: http://localhost:$API_PORT"
    echo "Model loading typically takes 5-10 minutes..."
    echo "======================"
    
    return 0
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Main function
main() {
    log_info "vLLM Server Startup Script v$SCRIPT_VERSION"
    
    # Initialize utilities
    init_utils
    
    # Parse arguments
    parse_arguments "$@"
    
    # Handle status check first
    if [[ "$CHECK_STATUS" == "true" ]]; then
        if ! load_and_validate_config; then
            exit 1
        fi
        check_server_status
        exit $?
    fi
    
    # Handle stop command
    if [[ "$STOP_SERVER" == "true" ]]; then
        if ! load_and_validate_config; then
            exit 1
        fi
        stop_vllm_server
        exit $?
    fi
    
    # Handle restart command
    if [[ "$RESTART_SERVER" == "true" ]]; then
        if ! load_and_validate_config; then
            exit 1
        fi
        log_info "Restarting vLLM server..."
        stop_vllm_server
        sleep 2
        start_vllm_server
        exit $?
    fi
    
    # Load and validate configuration
    if ! load_and_validate_config; then
        exit 1
    fi
    
    # Handle validate-only mode
    if [[ "$VALIDATE_ONLY" == "true" ]]; then
        log_success "Configuration validation completed successfully"
        show_current_config
        exit 0
    fi
    
    # Show system information if debug mode
    if [[ "$DEBUG" == "true" ]]; then
        get_system_info
    fi
    
    # Start the server
    if ! start_vllm_server; then
        log_error "Failed to start vLLM server"
        exit 1
    fi
    
    log_success "vLLM server startup completed successfully"
}

# Set up signal handlers for cleanup
trap 'cleanup_on_error' EXIT

# Run main function
main "$@"