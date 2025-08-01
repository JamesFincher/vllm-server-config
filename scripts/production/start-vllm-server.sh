#!/bin/bash
#
# Production vLLM Server Startup Script for Qwen3-480B
# Enhanced with comprehensive error handling, logging, and configuration management
# Optimized configuration based on extensive testing
#
# Usage: ./start-vllm-server.sh [OPTIONS]
# Options:
#   --config <file>           Use custom configuration file
#   --profile <name>          Use configuration profile (production|dev|performance|memory)
#   --context-length <length> Set max context length (overrides config)
#   --port <port>             Set server port (overrides config)
#   --api-key <key>           Set API key (overrides config)
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
readonly SCRIPT_NAME="start-vllm-server"
readonly SCRIPT_VERSION="2.0.0"
readonly PID_FILE="$PID_DIR/vllm_server.pid"

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
                              - performance: High-throughput configuration (700k context)
                              - production: Stable production settings (200k context)
                              - dev: Development with lower resource usage
                              - memory: Memory-optimized for limited resources
    --context-length <length> Set max context length (overrides config)
    --port <port>             Set server port (overrides config)
    --api-key <key>           Set API key (overrides config)
    --gpu-util <ratio>        Set GPU memory utilization 0.0-1.0 (overrides config)
    --tensor-parallel <size>  Set tensor parallel size (overrides config)
    --pipeline-parallel <size> Set pipeline parallel size (overrides config)
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
    CUDA_VISIBLE_DEVICES     GPU devices to use (default: 0,1,2,3)

EXAMPLES:
    # Start with high-performance configuration
    $0 --profile performance --api-key mykey123

    # Start with custom context length
    $0 --profile production --context-length 500000

    # Check server status
    $0 --status

    # Restart with debug logging
    $0 --restart --debug

HARDWARE REQUIREMENTS:
    - 4x NVIDIA H200 GPUs (or equivalent with 140GB+ VRAM each)
    - 700GB+ system RAM
    - 1TB+ storage for model files

CONFIGURATION PROFILES:
    performance - Maximum throughput (700k context, FP8 cache, 98% GPU util)
    production  - Stable production (200k context, FP8 cache, 95% GPU util)
    dev         - Development (100k context, auto cache, 85% GPU util)
    memory      - Memory-optimized (50k context, FP8 cache, 90% GPU util)

For more information, see the documentation in the configs/ directory.
EOF
}

# Initialize variables with defaults
CONFIG_FILE=""
PROFILE="${CONFIG_PROFILE:-performance}"  # Default to performance for this script
CUSTOM_CONTEXT_LENGTH=""
CUSTOM_PORT=""
CUSTOM_API_KEY=""
CUSTOM_GPU_UTIL=""
CUSTOM_TENSOR_PARALLEL=""
CUSTOM_PIPELINE_PARALLEL=""
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
            --context-length)
                CUSTOM_CONTEXT_LENGTH="$2"
                shift 2
                ;;
            --port)
                CUSTOM_PORT="$2"
                shift 2
                ;;
            --api-key)
                CUSTOM_API_KEY="$2"
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
    [[ -n "$CUSTOM_CONTEXT_LENGTH" ]] && export MAX_MODEL_LEN="$CUSTOM_CONTEXT_LENGTH"
    [[ -n "$CUSTOM_GPU_UTIL" ]] && export GPU_MEMORY_UTIL="$CUSTOM_GPU_UTIL"
    [[ -n "$CUSTOM_TENSOR_PARALLEL" ]] && export TENSOR_PARALLEL_SIZE="$CUSTOM_TENSOR_PARALLEL"
    [[ -n "$CUSTOM_PIPELINE_PARALLEL" ]] && export PIPELINE_PARALLEL_SIZE="$CUSTOM_PIPELINE_PARALLEL"
    
    if [[ -n "$CUSTOM_API_KEY" || -n "$CUSTOM_PORT" || -n "$CUSTOM_CONTEXT_LENGTH" || 
          -n "$CUSTOM_GPU_UTIL" || -n "$CUSTOM_TENSOR_PARALLEL" || -n "$CUSTOM_PIPELINE_PARALLEL" ]]; then
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

# Enhanced server status check
check_server_status() {
    log_info "Checking vLLM server status..."
    
    local status="stopped"
    local pid=""
    local port_status="closed"
    local api_status="unreachable"
    local memory_usage=""
    local uptime=""
    
    # Check by process name
    if is_process_running "vllm serve" "$PID_FILE"; then
        status="running"
        
        # Get PID
        if [[ -f "$PID_FILE" ]]; then
            pid=$(cat "$PID_FILE" 2>/dev/null)
        else
            pid=$(pgrep -f "vllm serve" | head -1)
        fi
        
        # Get process uptime
        if [[ -n "$pid" ]]; then
            uptime=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ' || echo "unknown")
        fi
        
        # Check port
        if netstat -tuln 2>/dev/null | grep -q ":${API_PORT} "; then
            port_status="open"
            
            # Check API endpoints
            if curl -s --max-time 5 "http://localhost:${API_PORT}/health" >/dev/null 2>&1; then
                api_status="healthy"
            elif curl -s --max-time 5 "http://localhost:${API_PORT}/v1/models" >/dev/null 2>&1; then
                api_status="responding"
            else
                api_status="unhealthy"
            fi
        fi
        
        # Get memory usage if nvidia-smi is available
        if command -v nvidia-smi &> /dev/null; then
            memory_usage=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits | \
                          awk -F', ' 'NR==1{used+=$1; total+=$2} END{printf "%.1f%%", (used/total)*100}' 2>/dev/null || echo "N/A")
        fi
    fi
    
    # Display comprehensive status
    echo "=== vLLM Server Status ==="
    echo "Process: $status"
    [[ -n "$pid" ]] && echo "PID: $pid"
    [[ -n "$uptime" ]] && echo "Uptime: $uptime"
    echo "Port $API_PORT: $port_status"
    echo "API: $api_status"
    [[ -n "$memory_usage" ]] && echo "GPU Memory: $memory_usage"
    echo "Configuration: $PROFILE"
    echo "Model: $MODEL_PATH"
    echo "Max Context: $MAX_MODEL_LEN tokens"
    echo "GPU Utilization: $GPU_MEMORY_UTIL"
    echo "Tensor Parallel: $TENSOR_PARALLEL_SIZE"
    echo "Pipeline Parallel: $PIPELINE_PARALLEL_SIZE"
    echo "=========================="
    
    # Additional diagnostics if debug mode
    if [[ "$DEBUG" == "true" && "$status" == "running" ]]; then
        echo ""
        echo "=== Debug Information ==="
        if [[ -n "$pid" ]]; then
            echo "Process details:"
            ps -fp "$pid" 2>/dev/null || echo "  Unable to get process details"
            
            echo "Open files:"
            lsof -p "$pid" 2>/dev/null | wc -l | awk '{print "  " $1 " files open"}'
            
            echo "Network connections:"
            netstat -tulpn 2>/dev/null | grep "$pid" | wc -l | awk '{print "  " $1 " connections"}'
        fi
        
        if command -v nvidia-smi &> /dev/null; then
            echo "GPU processes:"
            nvidia-smi pmon -c 1 -s um 2>/dev/null | grep -E "(python|vllm)" || echo "  No GPU processes found"
        fi
        echo "=========================="
    fi
    
    # Return status code
    [[ "$status" == "running" && "$api_status" =~ ^(healthy|responding)$ ]]
}

# Enhanced server stop with cleanup
stop_vllm_server() {
    log_info "Stopping vLLM server..."
    
    if ! is_process_running "vllm serve" "$PID_FILE"; then
        log_info "vLLM server is not running"
        return 0
    fi
    
    # Show confirmation unless forced
    if ! confirm "Stop vLLM server?" "y"; then
        log_info "Server stop cancelled by user"
        return 1
    fi
    
    # Stop the process with enhanced cleanup
    log_info "Stopping vLLM process..."
    if stop_process "vllm serve" "$PID_FILE" 60; then  # Longer timeout for large models
        log_success "vLLM server stopped successfully"
        
        # Clean up screen sessions
        log_info "Cleaning up screen sessions..."
        screen -ls 2>/dev/null | grep vllm | cut -d. -f1 | awk '{print $1}' | \
        xargs -I {} screen -S {}.vllm -X quit 2>/dev/null || true
        
        # Wait for GPU memory to be released
        if command -v nvidia-smi &> /dev/null; then
            log_info "Waiting for GPU memory to be released..."
            local count=0
            while (( count < 30 )); do
                if ! nvidia-smi pmon -c 1 -s um 2>/dev/null | grep -E "(python|vllm)" >/dev/null; then
                    break
                fi
                sleep 1
                ((count++))
            done
            
            if (( count < 30 )); then
                log_success "GPU memory released"
            else
                log_warning "GPU memory may still be in use"
            fi
        fi
        
        return 0
    else
        log_error "Failed to stop vLLM server gracefully"
        return 1
    fi
}

# Enhanced server startup with better monitoring
start_vllm_server() {
    log_info "Starting vLLM server with profile: $PROFILE"
    
    # Check if already running
    if is_process_running "vllm serve" "$PID_FILE"; then
        log_warning "vLLM server is already running"
        if ! confirm "Stop existing server and start new one?"; then
            return 1
        fi
        stop_vllm_server
        sleep 3  # Give extra time after stopping
    fi
    
    # Pre-flight checks
    log_info "Running pre-flight checks..."
    
    # Check virtual environment
    if [[ ! -f "$VLLM_ENV_PATH/bin/activate" ]]; then
        log_error "vLLM virtual environment not found at $VLLM_ENV_PATH"
        log_error "Please run the setup script first"
        return 1
    fi
    
    # Check model directory
    if [[ ! -d "$MODEL_PATH" ]]; then
        log_error "Model directory not found: $MODEL_PATH"
        log_error "Please download the model first"
        return 1
    fi
    
    # Check GPU availability
    if command -v nvidia-smi &> /dev/null; then
        local gpu_count
        gpu_count=$(nvidia-smi --list-gpus | wc -l)
        if (( gpu_count < 2 )); then
            log_warning "Only $gpu_count GPU(s) detected. Qwen3-480B requires at least 4 GPUs for optimal performance."
        fi
    fi
    
    # Activate environment and verify
    log_info "Activating vLLM environment..."
    source "$VLLM_ENV_PATH/bin/activate"
    
    # Verify vLLM installation
    if ! python -c "import vllm" 2>/dev/null; then
        log_error "vLLM not available in environment"
        return 1
    fi
    
    local vllm_version
    vllm_version=$(python -c "import vllm; print(vllm.__version__)" 2>/dev/null)
    log_info "vLLM version: $vllm_version"
    
    # Set environment variables
    export VLLM_API_KEY="$VLLM_API_KEY"
    export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
    export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0,1,2,3}"
    
    # Performance optimizations based on profile
    if [[ "$PROFILE" == "performance" ]]; then
        log_info "Applying performance optimizations..."
        export NCCL_DEBUG=INFO
        export NCCL_P2P_DISABLE=0
        export NCCL_IB_DISABLE=1
        export NCCL_SOCKET_IFNAME=lo
        export NCCL_ALGO=Tree
        export NCCL_PROTO=Simple
        export VLLM_FP8_E4M3_KV_CACHE=0
        export VLLM_FP8_KV_CACHE=0
    fi
    
    # Build vLLM command
    local vllm_cmd
    vllm_cmd=$(get_vllm_args | tr '\n' ' ')
    vllm_cmd="vllm serve $vllm_cmd"
    
    # Show configuration summary
    echo ""
    echo "=== vLLM Server Configuration ==="
    echo "Model: Qwen3-Coder-480B-A35B-Instruct-FP8"
    echo "Profile: $PROFILE"
    echo "Context Length: $MAX_MODEL_LEN tokens"
    echo "Port: $API_PORT"
    echo "GPU Memory Utilization: $GPU_MEMORY_UTIL"
    echo "Tensor Parallel: $TENSOR_PARALLEL_SIZE"
    echo "Pipeline Parallel: $PIPELINE_PARALLEL_SIZE"
    echo "KV Cache: $KV_CACHE_DTYPE"
    echo "GPUs: $CUDA_VISIBLE_DEVICES"
    echo "================================="
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
    
    # Create necessary directories
    validate_directory "$PID_DIR" "PID directory" true
    validate_directory "$LOG_DIR" "Log directory" true
    
    # Create log file
    local log_file="$LOG_DIR/vllm-server-${TIMESTAMP}.log"
    
    log_info "Starting vLLM server..."
    log_info "Log file: $log_file"
    log_info "This may take 5-10 minutes for model loading..."
    
    # Start server in screen session with enhanced logging
    screen -dmS vllm_server bash -c "
        set -e
        source '$VLLM_ENV_PATH/bin/activate'
        
        # Re-export all environment variables
        $(declare -p | grep '^declare -x')
        
        echo '=====================================' | tee '$log_file'
        echo 'vLLM Server Starting' | tee -a '$log_file'
        echo 'Timestamp: $(date -Iseconds)' | tee -a '$log_file'
        echo 'Profile: $PROFILE' | tee -a '$log_file'
        echo 'Model: $MODEL_PATH' | tee -a '$log_file'
        echo 'Context: $MAX_MODEL_LEN tokens' | tee -a '$log_file'
        echo 'Command: $vllm_cmd' | tee -a '$log_file'
        echo '=====================================' | tee -a '$log_file'
        echo '' | tee -a '$log_file'
        
        # Execute vLLM command
        $vllm_cmd 2>&1 | tee -a '$log_file'
    "
    
    # Wait for screen session to start
    sleep 3
    
    # Get and save PID
    local server_pid
    server_pid=$(pgrep -f "vllm serve" | head -1)
    if [[ -n "$server_pid" ]]; then
        echo "$server_pid" > "$PID_FILE"
        log_success "vLLM server started with PID: $server_pid"
        
        # Show monitoring information
        echo ""
        echo "=== Server Started Successfully ==="
        echo "PID: $server_pid"
        echo "Profile: $PROFILE"
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
        echo "===================================="
        
        return 0
    else
        log_error "Failed to start vLLM server"
        log_error "Check the log file for details: $log_file"
        return 1
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Main function
main() {
    log_info "Production vLLM Server Script v$SCRIPT_VERSION"
    
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
        sleep 5  # Give more time for cleanup
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