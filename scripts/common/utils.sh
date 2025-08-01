#!/bin/bash
#
# Common Utilities for vLLM Scripts
# Production-ready helper functions for logging, validation, and configuration
#
# Usage: source /path/to/scripts/common/utils.sh
#
# Version: 1.0.0
# Author: Production Enhancement Script
# Created: $(date +"%Y-%m-%d")

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Configuration paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BASE_DIR="$(dirname "$SCRIPT_DIR")"
readonly CONFIG_DIR="$BASE_DIR/../configs"
readonly LOG_DIR="${LOG_DIR:-/var/log/vllm}"
readonly PID_DIR="${PID_DIR:-/var/run/vllm}"

# Default configuration values
readonly DEFAULT_VLLM_ENV_PATH="/opt/vllm"
readonly DEFAULT_MODEL_PATH="/models/qwen3"
readonly DEFAULT_API_PORT=8000
readonly DEFAULT_GPU_MEMORY_UTIL=0.95
readonly DEFAULT_MAX_MODEL_LEN=200000

# Global variables for script configuration
VERBOSE=false
DEBUG=false
FORCE=false
DRY_RUN=false
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

# Initialize logging
init_logging() {
    local log_file="${1:-vllm_${TIMESTAMP}.log}"
    local log_level="${2:-INFO}"
    
    # Create log directory if it doesn't exist
    mkdir -p "$LOG_DIR"
    
    # Set global log file
    LOG_FILE="$LOG_DIR/$log_file"
    
    # Initialize log file
    cat > "$LOG_FILE" << EOF
=== vLLM Script Log ===
Timestamp: $(date -Iseconds)
Script: ${0##*/}
PID: $$
Log Level: $log_level
Host: $(hostname)
User: $(whoami)
Working Directory: $(pwd)
========================

EOF
    
    echo "Logging initialized: $LOG_FILE"
}

# Generic log function
_log() {
    local level="$1"
    local color="$2"
    local message="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Format message
    local formatted_message="[$timestamp] [$level] $message"
    
    # Write to log file if available
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "$formatted_message" >> "$LOG_FILE"
    fi
    
    # Write to console with color
    echo -e "${color}$formatted_message${NC}"
}

# Specific logging functions
log_info() {
    _log "INFO" "$BLUE" "$1"
}

log_success() {
    _log "SUCCESS" "$GREEN" "$1"
}

log_warning() {
    _log "WARNING" "$YELLOW" "$1"
}

log_error() {
    _log "ERROR" "$RED" "$1"
}

log_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        _log "DEBUG" "$PURPLE" "$1"
    fi
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        _log "VERBOSE" "$CYAN" "$1"
    fi
}

# =============================================================================
# ERROR HANDLING
# =============================================================================

# Error handler function
error_handler() {
    local line_no=$1
    local error_code=$2
    local command="$3"
    
    log_error "Script failed at line $line_no with exit code $error_code"
    log_error "Failed command: $command"
    
    # Show stack trace if debug is enabled
    if [[ "$DEBUG" == "true" ]]; then
        log_debug "=== Stack Trace ==="
        local frame=0
        while caller $frame; do
            ((frame++))
        done | while read line func file; do
            log_debug "  at $func ($file:$line)"
        done
    fi
    
    # Cleanup on error
    cleanup_on_error
    
    exit $error_code
}

# Cleanup function called on error
cleanup_on_error() {
    log_info "Performing cleanup on error..."
    
    # Kill any processes we started
    if [[ -n "${CHILD_PIDS:-}" ]]; then
        for pid in $CHILD_PIDS; do
            if kill -0 "$pid" 2>/dev/null; then
                log_info "Killing child process: $pid"
                kill -TERM "$pid" 2>/dev/null || true
            fi
        done
    fi
    
    # Remove temporary files
    if [[ -n "${TEMP_FILES:-}" ]]; then
        for temp_file in $TEMP_FILES; do
            if [[ -f "$temp_file" ]]; then
                log_info "Removing temporary file: $temp_file"
                rm -f "$temp_file"
            fi
        done
    fi
}

# Set up error handling
setup_error_handling() {
    set -eE  # Exit on error, inherit error handling in functions
    trap 'error_handler ${LINENO} $? "$BASH_COMMAND"' ERR
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Check if script is running as expected user
check_user() {
    local expected_user="${1:-root}"
    local current_user=$(whoami)
    
    if [[ "$current_user" != "$expected_user" ]]; then
        log_error "This script must be run as user '$expected_user' (currently: $current_user)"
        if [[ "$expected_user" == "root" ]]; then
            log_error "Please run with sudo or as root"
        fi
        exit 1
    fi
    
    log_debug "User check passed: $current_user"
}

# Check if required commands are available
check_commands() {
    local commands=("$@")
    local missing_commands=()
    
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -ne 0 ]]; then
        log_error "Missing required commands:"
        printf "  - %s\n" "${missing_commands[@]}"
        return 1
    fi
    
    log_debug "Command check passed: ${commands[*]}"
    return 0
}

# Validate directory exists and is writable
validate_directory() {
    local dir="$1"
    local description="${2:-Directory}"
    local create_if_missing="${3:-false}"
    
    if [[ ! -d "$dir" ]]; then
        if [[ "$create_if_missing" == "true" ]]; then
            log_info "Creating $description: $dir"
            mkdir -p "$dir" || {
                log_error "Failed to create $description: $dir"
                return 1
            }
        else
            log_error "$description does not exist: $dir"
            return 1
        fi
    fi
    
    if [[ ! -w "$dir" ]]; then
        log_error "$description is not writable: $dir"
        return 1
    fi
    
    log_debug "$description validation passed: $dir"
    return 0
}

# Validate file exists and is readable
validate_file() {
    local file="$1"
    local description="${2:-File}"
    
    if [[ ! -f "$file" ]]; then
        log_error "$description does not exist: $file"
        return 1
    fi
    
    if [[ ! -r "$file" ]]; then
        log_error "$description is not readable: $file"
        return 1
    fi
    
    log_debug "$description validation passed: $file"
    return 0
}

# Validate port is available
validate_port() {
    local port="$1"
    local description="${2:-Port}"
    
    if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        log_error "Invalid $description: $port (must be 1-65535)"
        return 1
    fi
    
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        log_warning "$description $port is already in use"
        return 1
    fi
    
    log_debug "$description validation passed: $port"
    return 0
}

# Validate GPU availability
validate_gpus() {
    local required_gpus="${1:-1}"
    
    if ! command -v nvidia-smi &> /dev/null; then
        log_error "nvidia-smi not found - NVIDIA drivers may not be installed"
        return 1
    fi
    
    local available_gpus
    available_gpus=$(nvidia-smi --list-gpus 2>/dev/null | wc -l)
    
    if (( available_gpus < required_gpus )); then
        log_error "Insufficient GPUs: need $required_gpus, found $available_gpus"
        return 1
    fi
    
    log_debug "GPU validation passed: $available_gpus available (need $required_gpus)"
    return 0
}

# =============================================================================
# CONFIGURATION FUNCTIONS
# =============================================================================

# Load configuration from file
load_config() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        log_warning "Configuration file not found: $config_file"
        return 1
    fi
    
    log_info "Loading configuration from: $config_file"
    
    # Source the configuration file in a subshell to validate it first
    if ! (source "$config_file") &>/dev/null; then
        log_error "Invalid configuration file: $config_file"
        return 1
    fi
    
    # Source the configuration file
    source "$config_file"
    log_debug "Configuration loaded successfully"
    return 0
}

# Set default configuration values
set_defaults() {
    # Set defaults if not already set
    VLLM_ENV_PATH="${VLLM_ENV_PATH:-$DEFAULT_VLLM_ENV_PATH}"
    MODEL_PATH="${MODEL_PATH:-$DEFAULT_MODEL_PATH}"
    API_PORT="${API_PORT:-$DEFAULT_API_PORT}"
    GPU_MEMORY_UTIL="${GPU_MEMORY_UTIL:-$DEFAULT_GPU_MEMORY_UTIL}"
    MAX_MODEL_LEN="${MAX_MODEL_LEN:-$DEFAULT_MAX_MODEL_LEN}"
    
    # Set CUDA devices if not set
    CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0,1,2,3}"
    
    log_debug "Default configuration set"
}

# Validate configuration
validate_config() {
    local errors=()
    
    # Check required variables
    [[ -z "${VLLM_API_KEY:-}" ]] && errors+=("VLLM_API_KEY not set")
    [[ -z "${VLLM_ENV_PATH:-}" ]] && errors+=("VLLM_ENV_PATH not set")
    [[ -z "${MODEL_PATH:-}" ]] && errors+=("MODEL_PATH not set")
    
    # Check numeric values
    if [[ -n "${API_PORT:-}" ]] && ! [[ "$API_PORT" =~ ^[0-9]+$ ]]; then
        errors+=("API_PORT must be numeric")
    fi
    
    if [[ -n "${GPU_MEMORY_UTIL:-}" ]] && ! [[ "$GPU_MEMORY_UTIL" =~ ^0\.[0-9]+$ ]]; then
        errors+=("GPU_MEMORY_UTIL must be decimal between 0 and 1")
    fi
    
    if [[ ${#errors[@]} -ne 0 ]]; then
        log_error "Configuration validation failed:"
        printf "  - %s\n" "${errors[@]}"
        return 1
    fi
    
    log_debug "Configuration validation passed"
    return 0
}

# =============================================================================
# PROCESS MANAGEMENT
# =============================================================================

# Check if a process is running
is_process_running() {
    local process_name="$1"
    local pid_file="${2:-}"
    
    # Check by PID file if provided
    if [[ -n "$pid_file" && -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            # Remove stale PID file
            rm -f "$pid_file"
        fi
    fi
    
    # Check by process name
    if pgrep -f "$process_name" >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Stop a process gracefully
stop_process() {
    local process_name="$1"
    local pid_file="${2:-}"
    local timeout="${3:-30}"
    
    log_info "Stopping process: $process_name"
    
    local pids=()
    
    # Get PID from file if provided
    if [[ -n "$pid_file" && -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            pids+=("$pid")
        fi
    fi
    
    # Get PIDs by process name
    while IFS= read -r pid; do
        pids+=("$pid")
    done < <(pgrep -f "$process_name" 2>/dev/null || true)
    
    if [[ ${#pids[@]} -eq 0 ]]; then
        log_info "No processes found matching: $process_name"
        return 0
    fi
    
    # Send TERM signal
    for pid in "${pids[@]}"; do
        log_info "Sending TERM signal to PID: $pid"
        kill -TERM "$pid" 2>/dev/null || true
    done
    
    # Wait for processes to exit
    local count=0
    while (( count < timeout )); do
        local running=false
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                running=true
                break
            fi
        done
        
        if [[ "$running" == "false" ]]; then
            log_success "Process stopped gracefully: $process_name"
            [[ -n "$pid_file" ]] && rm -f "$pid_file"
            return 0
        fi
        
        sleep 1
        ((count++))
    done
    
    # Force kill if still running
    log_warning "Process did not stop gracefully, force killing: $process_name"
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            log_warning "Force killing PID: $pid"
            kill -KILL "$pid" 2>/dev/null || true
        fi
    done
    
    [[ -n "$pid_file" ]] && rm -f "$pid_file"
    return 0
}

# =============================================================================
# PROGRESS INDICATORS
# =============================================================================

# Show a spinner while running a command
show_spinner() {
    local pid=$1
    local message="${2:-Processing}"
    local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local delay=0.1
    
    echo -n "$message "
    
    while kill -0 "$pid" 2>/dev/null; do
        for (( i=0; i<${#spinner_chars}; i++ )); do
            echo -ne "\b${spinner_chars:$i:1}"
            sleep $delay
            if ! kill -0 "$pid" 2>/dev/null; then
                break 2
            fi
        done
    done
    
    echo -e "\b✓"
}

# Show progress bar
show_progress() {
    local current=$1
    local total=$2
    local width=${3:-50}
    local message="${4:-Progress}"
    
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r%s: [" "$message"
    printf "%*s" $filled | tr ' ' '='
    printf "%*s" $empty | tr ' ' '-'
    printf "] %d%%" $percent
    
    if [[ $current -eq $total ]]; then
        echo ""
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Confirm action with user
confirm() {
    local message="${1:-Are you sure?}"
    local default="${2:-n}"
    
    if [[ "$FORCE" == "true" ]]; then
        log_debug "Force mode enabled, skipping confirmation"
        return 0
    fi
    
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

# Create temporary file
create_temp_file() {
    local prefix="${1:-vllm_temp}"
    local suffix="${2:-}"
    
    local temp_file
    temp_file=$(mktemp "/tmp/${prefix}_XXXXXX${suffix}")
    
    # Add to cleanup list
    TEMP_FILES="${TEMP_FILES:-} $temp_file"
    
    echo "$temp_file"
}

# Human readable file size
human_readable_size() {
    local size=$1
    local units=("B" "KB" "MB" "GB" "TB")
    local unit=0
    
    while (( size > 1024 && unit < ${#units[@]}-1 )); do
        size=$((size / 1024))
        ((unit++))
    done
    
    echo "${size}${units[$unit]}"
}

# Get system information
get_system_info() {
    echo "=== System Information ==="
    echo "Hostname: $(hostname)"
    echo "OS: $(uname -s) $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "CPU Cores: $(nproc)"
    echo "Total Memory: $(free -h | awk '/^Mem:/ {print $2}')"
    echo "Available Memory: $(free -h | awk '/^Mem:/ {print $7}')"
    
    if command -v nvidia-smi &> /dev/null; then
        echo "GPUs: $(nvidia-smi --list-gpus | wc -l)"
        echo "GPU Driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -1)"
    else
        echo "GPUs: No NVIDIA GPUs detected"
    fi
    
    echo "Disk Space (/):"
    df -h / | tail -1 | awk '{print "  Used: " $3 " / " $2 " (" $5 ")"}'
    echo "========================="
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

# Parse common arguments
parse_common_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
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
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --log-file)
                LOG_FILE="$2"
                shift 2
                ;;
            -h|--help)
                if declare -f show_help > /dev/null; then
                    show_help
                else
                    echo "Help function not implemented"
                fi
                exit 0
                ;;
            *)
                # Return remaining arguments
                break
                ;;
        esac
    done
    
    # Return remaining arguments
    echo "$@"
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize common utilities
init_utils() {
    # Set up error handling
    setup_error_handling
    
    # Set defaults
    set_defaults
    
    # Load configuration if specified
    if [[ -n "${CONFIG_FILE:-}" ]]; then
        load_config "$CONFIG_FILE"
    fi
    
    # Initialize logging
    init_logging "${LOG_FILE##*/}"
    
    log_debug "Common utilities initialized"
}

# =============================================================================
# EXPORTS
# =============================================================================

# Export functions that should be available to scripts
export -f log_info log_success log_warning log_error log_debug log_verbose
export -f check_user check_commands validate_directory validate_file validate_port validate_gpus
export -f load_config set_defaults validate_config
export -f is_process_running stop_process
export -f show_spinner show_progress
export -f confirm create_temp_file human_readable_size get_system_info
export -f parse_common_args init_utils

# Export variables
export RED GREEN YELLOW BLUE PURPLE CYAN WHITE NC
export SCRIPT_DIR BASE_DIR CONFIG_DIR LOG_DIR PID_DIR
export VERBOSE DEBUG FORCE DRY_RUN TIMESTAMP

log_debug "Common utilities library loaded"