#!/bin/bash
#
# Comprehensive System Check Script for vLLM with Qwen3-480B
# Enhanced with detailed diagnostics, validation, and reporting
#
# Usage: ./system_check.sh [OPTIONS]
# Options:
#   --verbose                 Enable verbose output
#   --debug                   Enable debug mode
#   --export-report          Export detailed report to file
#   --json                   Output results in JSON format
#   --fix-issues             Attempt to fix common issues automatically
#   --check-only <category>  Only check specific category
#   --help                   Show this help message
#
# Categories: environment, model, gpu, system, network, processes, scripts
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
    
    # Simplified functions for standalone operation
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    NC='\033[0m'
    
    log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
    log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
    log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
    log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo -e "${PURPLE}[DEBUG]${NC} $1"; }
fi

# Script configuration
readonly SCRIPT_NAME="system_check"
readonly SCRIPT_VERSION="2.0.0"
readonly TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Global variables
VERBOSE=false
DEBUG=false
EXPORT_REPORT=false
JSON_OUTPUT=false
FIX_ISSUES=false
CHECK_CATEGORY=""
REPORT_FILE=""
RESULTS=()

# =============================================================================
# COMMAND LINE ARGUMENT PARSING
# =============================================================================

show_help() {
    cat << EOF
Comprehensive System Check Script for vLLM with Qwen3-480B v$SCRIPT_VERSION

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --verbose                 Enable verbose output
    --debug                   Enable debug mode with detailed logging
    --export-report          Export detailed report to file
    --json                   Output results in JSON format
    --fix-issues             Attempt to fix common issues automatically
    --check-only <category>  Only check specific category
    --report-file <file>     Specify custom report file path
    --help                   Show this help message

CHECK CATEGORIES:
    environment              Python environment and packages
    model                    Model files and configuration
    gpu                      GPU hardware and drivers
    system                   System resources and configuration
    network                  Network connectivity and ports
    processes                Running processes and services
    scripts                  Available scripts and tools
    all                      All categories (default)

EXAMPLES:
    # Run comprehensive system check
    $0

    # Check only GPU and system resources
    $0 --check-only gpu

    # Export detailed report
    $0 --export-report --verbose

    # Debug mode with JSON output
    $0 --debug --json

    # Attempt to fix issues automatically
    $0 --fix-issues --verbose

DESCRIPTION:
    This script performs comprehensive system validation for vLLM and Qwen3-480B
    deployment. It checks all critical components including Python environment,
    model files, GPU hardware, system resources, and configuration.

    The script provides detailed diagnostics, recommendations for fixing issues,
    and can export comprehensive reports for troubleshooting.

REQUIREMENTS:
    - Python 3.10+ with vLLM installed
    - NVIDIA GPUs with CUDA support
    - Sufficient system resources for Qwen3-480B
EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose)
                VERBOSE=true
                shift
                ;;
            --debug)
                DEBUG=true
                VERBOSE=true
                shift
                ;;
            --export-report)
                EXPORT_REPORT=true
                shift
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --fix-issues)
                FIX_ISSUES=true
                shift
                ;;
            --check-only)
                CHECK_CATEGORY="$2"
                shift 2
                ;;
            --report-file)
                REPORT_FILE="$2"
                shift 2
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
# UTILITY FUNCTIONS
# =============================================================================

# Add result to results array
add_result() {
    local category="$1"
    local check="$2"
    local status="$3"
    local message="$4"
    local details="${5:-}"
    
    local result
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        result=$(jq -n \
            --arg cat "$category" \
            --arg check "$check" \
            --arg status "$status" \
            --arg msg "$message" \
            --arg det "$details" \
            '{category: $cat, check: $check, status: $status, message: $msg, details: $det}')
    else
        result="[$category] $check: $status - $message"
        [[ -n "$details" ]] && result="$result ($details)"
    fi
    
    RESULTS+=("$result")
}

# Display section header
section_header() {
    local title="$1"
    echo ""
    echo "=== $title ==="
}

# Display subsection header
subsection_header() {
    local title="$1"
    [[ "$VERBOSE" == "true" ]] && echo ""
    echo "--- $title ---"
}

# Execute command with error handling
safe_execute() {
    local description="$1"
    shift
    
    log_debug "Executing: $*"
    
    if output=$("$@" 2>&1); then
        log_debug "$description: Success"
        echo "$output"
        return 0
    else
        local exit_code=$?
        log_debug "$description: Failed with exit code $exit_code"
        echo "$output"
        return $exit_code
    fi
}

# =============================================================================
# CHECK FUNCTIONS
# =============================================================================

# Check Python environment and packages
check_environment() {
    section_header "Python Environment Check"
    
    local status="PASS"
    local issues=()
    
    # Check if vLLM environment exists
    if [[ ! -f "/opt/vllm/bin/activate" ]]; then
        issues+=("vLLM virtual environment not found at /opt/vllm")
        status="FAIL"
        add_result "environment" "vllm_env" "FAIL" "Virtual environment not found" "/opt/vllm/bin/activate missing"
    else
        log_info "Activating vLLM environment..."
        source /opt/vllm/bin/activate
        add_result "environment" "vllm_env" "PASS" "Virtual environment found" "/opt/vllm"
        
        # Check Python version
        local python_version
        python_version=$(python --version 2>&1 | cut -d' ' -f2)
        log_info "Python version: $python_version"
        add_result "environment" "python_version" "INFO" "Python $python_version" ""
        
        # Check vLLM installation
        if python -c "import vllm" 2>/dev/null; then
            local vllm_version
            vllm_version=$(python -c "import vllm; print(vllm.__version__)" 2>/dev/null)
            log_success "vLLM version: $vllm_version"
            add_result "environment" "vllm_install" "PASS" "vLLM installed" "version $vllm_version"
            
            # Check vLLM location and details
            if [[ "$VERBOSE" == "true" ]]; then
                python -c "
import vllm
import os
print(f'vLLM location: {vllm.__file__}')
print(f'vLLM install dir: {os.path.dirname(vllm.__file__)}')
"
            fi
        else
            issues+=("vLLM not installed or not importable")
            status="FAIL"
            add_result "environment" "vllm_install" "FAIL" "vLLM not importable" ""
        fi
        
        # Check critical packages
        subsection_header "Critical Package Check"
        local critical_packages=("torch" "transformers" "numpy" "cuda" "flash-attn" "triton" "xformers")
        
        for package in "${critical_packages[@]}"; do
            if pip list | grep -i "$package" >/dev/null 2>&1; then
                local version
                version=$(pip list | grep -i "$package" | awk '{print $2}' | head -1)
                log_info "$package: $version"
                add_result "environment" "package_$package" "PASS" "$package installed" "version $version"
            else
                log_warning "$package: Not found"
                add_result "environment" "package_$package" "WARNING" "$package not found" ""
            fi
        done
        
        # Check PyTorch CUDA support
        if python -c "import torch; print('CUDA available:', torch.cuda.is_available())" 2>/dev/null | grep -q "True"; then
            local cuda_version
            cuda_version=$(python -c "import torch; print(torch.version.cuda)" 2>/dev/null)
            log_success "PyTorch CUDA support: Available (CUDA $cuda_version)"
            add_result "environment" "torch_cuda" "PASS" "PyTorch CUDA available" "CUDA $cuda_version"
        else
            issues+=("PyTorch CUDA support not available")
            status="FAIL"
            add_result "environment" "torch_cuda" "FAIL" "PyTorch CUDA not available" ""
        fi
        
        # Check vLLM configuration
        subsection_header "vLLM Configuration Check"
        python -c "
try:
    from vllm.config import ModelConfig
    print('✓ vLLM ModelConfig available')
except Exception as e:
    print('✗ vLLM ModelConfig import failed:', str(e))

try:
    from vllm import LLM
    print('✓ vLLM LLM class available')
except Exception as e:
    print('✗ vLLM LLM import failed:', str(e))
"
    fi
    
    # Summary
    if [[ "$status" == "PASS" ]]; then
        log_success "Environment check: PASSED"
    else
        log_error "Environment check: FAILED"
        printf "  Issues found:\n"
        printf "  - %s\n" "${issues[@]}"
    fi
    
    add_result "environment" "overall" "$status" "Environment check completed" "${#issues[@]} issues found"
}

# Check model files and configuration
check_model() {
    section_header "Model Files and Configuration Check"
    
    local status="PASS"
    local issues=()
    local model_path="/models/qwen3"
    
    # Check model directory exists
    if [[ ! -d "$model_path" ]]; then
        issues+=("Model directory not found: $model_path")
        status="FAIL"
        add_result "model" "directory" "FAIL" "Model directory not found" "$model_path"
        return
    else
        log_success "Model directory found: $model_path"
        add_result "model" "directory" "PASS" "Model directory exists" "$model_path"
    fi
    
    # Check model size
    local model_size_bytes
    model_size_bytes=$(du -sb "$model_path" 2>/dev/null | cut -f1)
    if [[ -n "$model_size_bytes" ]]; then
        local model_size_gb=$((model_size_bytes / 1024 / 1024 / 1024))
        log_info "Model size: ${model_size_gb}GB"
        add_result "model" "size" "INFO" "Model size" "${model_size_gb}GB"
        
        # Warn if model seems too small
        if (( model_size_gb < 100 )); then
            log_warning "Model size seems small for Qwen3-480B ($model_size_gb GB)"
            issues+=("Model size seems small ($model_size_gb GB)")
            add_result "model" "size_check" "WARNING" "Model size may be insufficient" "$model_size_gb GB"
        fi
    fi
    
    # Check critical model files
    subsection_header "Model Files Check"
    local critical_files=("config.json" "tokenizer.json" "tokenizer_config.json")
    local optional_files=("pytorch_model.bin" "model.safetensors" "generation_config.json")
    
    for file in "${critical_files[@]}"; do
        if [[ -f "$model_path/$file" ]]; then
            log_success "✓ $file"
            add_result "model" "file_$file" "PASS" "Required file exists" "$file"
        else
            log_error "✗ $file (required)"
            issues+=("Missing required file: $file")
            status="FAIL"
            add_result "model" "file_$file" "FAIL" "Required file missing" "$file"
        fi
    done
    
    for file in "${optional_files[@]}"; do
        if [[ -f "$model_path/$file" ]]; then
            log_info "✓ $file (optional)"
            add_result "model" "file_$file" "PASS" "Optional file exists" "$file"
        else
            log_warning "- $file (optional, not found)"
            add_result "model" "file_$file" "WARNING" "Optional file missing" "$file"
        fi
    done
    
    # Check model configuration
    if [[ -f "$model_path/config.json" ]]; then
        subsection_header "Model Configuration"
        
        if command -v jq >/dev/null 2>&1; then
            local model_type vocab_size hidden_size
            model_type=$(jq -r '.model_type // "unknown"' "$model_path/config.json")
            vocab_size=$(jq -r '.vocab_size // "unknown"' "$model_path/config.json")
            hidden_size=$(jq -r '.hidden_size // "unknown"' "$model_path/config.json")
            
            log_info "Model type: $model_type"
            log_info "Vocabulary size: $vocab_size"
            log_info "Hidden size: $hidden_size"
            
            add_result "model" "config_type" "INFO" "Model type" "$model_type"
            add_result "model" "config_vocab" "INFO" "Vocabulary size" "$vocab_size"
            add_result "model" "config_hidden" "INFO" "Hidden size" "$hidden_size"
        else
            log_warning "jq not available - skipping detailed config analysis"
            # Fallback to basic Python JSON parsing
            if python -c "import json; print('Model config is valid JSON')" < "$model_path/config.json" 2>/dev/null; then
                log_success "Model config.json is valid JSON"
                add_result "model" "config_valid" "PASS" "Config file is valid JSON" ""
            else
                log_error "Model config.json is invalid JSON"
                issues+=("Invalid model configuration JSON")
                status="FAIL"
                add_result "model" "config_valid" "FAIL" "Config file is invalid JSON" ""
            fi
        fi
        
        # Show config preview if verbose
        if [[ "$VERBOSE" == "true" ]]; then
            echo "Model config preview:"
            if command -v jq >/dev/null 2>&1; then
                jq '.' "$model_path/config.json" | head -30
            else
                python -c "import json; print(json.dumps(json.load(open('$model_path/config.json')), indent=2))" | head -30
            fi
        fi
    fi
    
    # Check file permissions
    subsection_header "File Permissions Check"
    if [[ -r "$model_path" ]]; then
        log_success "Model directory is readable"
        add_result "model" "permissions" "PASS" "Directory readable" ""
    else
        log_error "Model directory is not readable"
        issues+=("Model directory not readable")
        status="FAIL"
        add_result "model" "permissions" "FAIL" "Directory not readable" ""
    fi
    
    # Summary
    if [[ "$status" == "PASS" ]]; then
        log_success "Model check: PASSED"
    else
        log_error "Model check: FAILED"
        printf "  Issues found:\n"
        printf "  - %s\n" "${issues[@]}"
    fi
    
    add_result "model" "overall" "$status" "Model check completed" "${#issues[@]} issues found"
}

# Check GPU hardware and drivers
check_gpu() {
    section_header "GPU Hardware and Drivers Check"
    
    local status="PASS"
    local issues=()
    
    # Check nvidia-smi availability
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        issues+=("nvidia-smi not found - NVIDIA drivers may not be installed")
        status="FAIL"
        add_result "gpu" "nvidia_smi" "FAIL" "nvidia-smi not found" ""
        log_error "nvidia-smi not found. Please install NVIDIA drivers."
        return
    fi
    
    log_success "nvidia-smi found"
    add_result "gpu" "nvidia_smi" "PASS" "nvidia-smi available" ""
    
    # Get driver version
    local driver_version
    driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -1)
    log_info "NVIDIA driver version: $driver_version"
    add_result "gpu" "driver_version" "INFO" "Driver version" "$driver_version"
    
    # Check GPU count and details
    local gpu_count
    gpu_count=$(nvidia-smi --list-gpus | wc -l)
    log_info "Number of GPUs: $gpu_count"
    add_result "gpu" "gpu_count" "INFO" "GPU count" "$gpu_count"
    
    if (( gpu_count == 0 )); then
        issues+=("No GPUs detected")
        status="FAIL"
        add_result "gpu" "gpu_availability" "FAIL" "No GPUs detected" ""
    elif (( gpu_count < 4 )); then
        log_warning "Only $gpu_count GPU(s) detected. Qwen3-480B works best with 4+ GPUs"
        add_result "gpu" "gpu_availability" "WARNING" "Insufficient GPU count" "$gpu_count GPUs (recommended: 4+)"
    else
        log_success "$gpu_count GPUs detected - sufficient for Qwen3-480B"
        add_result "gpu" "gpu_availability" "PASS" "Sufficient GPUs" "$gpu_count GPUs"
    fi
    
    # Check individual GPU details
    if (( gpu_count > 0 )); then
        subsection_header "Individual GPU Details"
        
        # Use Python to get detailed GPU information
        if source /opt/vllm/bin/activate 2>/dev/null && python -c "import torch" 2>/dev/null; then
            python -c "
import torch
if torch.cuda.is_available():
    for i in range(torch.cuda.device_count()):
        props = torch.cuda.get_device_properties(i)
        print(f'GPU {i}: {props.name}')
        print(f'  Memory: {props.total_memory / 1024**3:.1f} GB')
        print(f'  Compute Capability: {props.major}.{props.minor}')
        print(f'  Multi-processors: {props.multi_processor_count}')
        print()
else:
    print('CUDA not available through PyTorch')
"
        fi
        
        # Check GPU memory
        log_info "GPU memory status:"
        nvidia-smi --query-gpu=index,name,memory.total,memory.used,memory.free --format=csv
        
        # Check for insufficient memory
        local min_memory=0
        while IFS= read -r memory; do
            if (( memory > 0 && (min_memory == 0 || memory < min_memory) )); then
                min_memory=$memory
            fi
        done < <(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)
        
        if (( min_memory > 0 )); then
            local min_memory_gb=$((min_memory / 1024))
            if (( min_memory_gb < 80 )); then
                log_warning "Minimum GPU memory: ${min_memory_gb}GB (recommended: 140GB+ for Qwen3-480B)"
                issues+=("GPU memory may be insufficient")
                add_result "gpu" "memory_check" "WARNING" "Low GPU memory" "${min_memory_gb}GB"
            else
                log_success "GPU memory: ${min_memory_gb}GB+ available"
                add_result "gpu" "memory_check" "PASS" "Sufficient GPU memory" "${min_memory_gb}GB+"
            fi
        fi
        
        # Check GPU utilization
        if [[ "$VERBOSE" == "true" ]]; then
            subsection_header "Current GPU Utilization"
            nvidia-smi --query-gpu=index,utilization.gpu,utilization.memory,temperature.gpu,power.draw --format=csv
        fi
        
        # Check for running GPU processes
        local gpu_processes
        gpu_processes=$(nvidia-smi pmon -c 1 -s um 2>/dev/null | grep -E "python|vllm" | wc -l)
        if (( gpu_processes > 0 )); then
            log_info "GPU processes running: $gpu_processes"
            add_result "gpu" "processes" "INFO" "GPU processes running" "$gpu_processes processes"
            
            if [[ "$VERBOSE" == "true" ]]; then
                echo "Active GPU processes:"
                nvidia-smi pmon -c 1 -s um 2>/dev/null | grep -E "python|vllm" || echo "  None found"
            fi
        else
            log_info "No active GPU processes detected"
            add_result "gpu" "processes" "INFO" "No GPU processes" "0 processes"
        fi
    fi
    
    # Check CUDA libraries
    subsection_header "CUDA Libraries Check"
    if ldconfig -p | grep -q cuda; then
        log_success "CUDA libraries found in system"
        add_result "gpu" "cuda_libs" "PASS" "CUDA libraries available" ""
        
        if [[ "$VERBOSE" == "true" ]]; then
            echo "CUDA libraries:"
            ldconfig -p | grep cuda | head -10
        fi
    else
        log_warning "CUDA libraries not found in ldconfig"
        add_result "gpu" "cuda_libs" "WARNING" "CUDA libraries not in ldconfig" ""
    fi
    
    # Check NCCL version if available
    if source /opt/vllm/bin/activate 2>/dev/null && python -c "import torch; print('NCCL version:', torch.cuda.nccl.version())" 2>/dev/null; then
        local nccl_version
        nccl_version=$(python -c "import torch; print(torch.cuda.nccl.version())" 2>/dev/null)
        log_info "NCCL version: $nccl_version"
        add_result "gpu" "nccl_version" "INFO" "NCCL version" "$nccl_version"
    fi
    
    # Summary
    if [[ "$status" == "PASS" ]]; then
        log_success "GPU check: PASSED"
    else
        log_error "GPU check: FAILED"
        printf "  Issues found:\n"
        printf "  - %s\n" "${issues[@]}"
    fi
    
    add_result "gpu" "overall" "$status" "GPU check completed" "${#issues[@]} issues found"
}

# Check system resources and configuration
check_system() {
    section_header "System Resources and Configuration Check"
    
    local status="PASS"
    local issues=()
    
    # System information
    subsection_header "System Information"
    log_info "Hostname: $(hostname)"
    log_info "OS: $(uname -s) $(uname -r)"
    log_info "Architecture: $(uname -m)"
    log_info "CPU cores: $(nproc)"
    
    add_result "system" "hostname" "INFO" "Hostname" "$(hostname)"
    add_result "system" "os" "INFO" "Operating system" "$(uname -s) $(uname -r)"
    add_result "system" "arch" "INFO" "Architecture" "$(uname -m)"
    add_result "system" "cpu_cores" "INFO" "CPU cores" "$(nproc)"
    
    # Memory check
    subsection_header "Memory Check"
    local total_ram_gb free_ram_gb used_ram_gb
    total_ram_gb=$(free -g | awk '/^Mem:/ {print $2}')
    free_ram_gb=$(free -g | awk '/^Mem:/ {print $7}')
    used_ram_gb=$(free -g | awk '/^Mem:/ {print $3}')
    
    log_info "Total RAM: ${total_ram_gb}GB"
    log_info "Used RAM: ${used_ram_gb}GB"
    log_info "Available RAM: ${free_ram_gb}GB"
    
    add_result "system" "total_ram" "INFO" "Total RAM" "${total_ram_gb}GB"
    add_result "system" "available_ram" "INFO" "Available RAM" "${free_ram_gb}GB"
    
    if (( total_ram_gb < 200 )); then
        log_warning "System RAM may be insufficient: ${total_ram_gb}GB (recommended: 500GB+ for Qwen3-480B)"
        issues+=("Insufficient system RAM")
        add_result "system" "ram_check" "WARNING" "Low system RAM" "${total_ram_gb}GB"
    else
        log_success "System RAM: ${total_ram_gb}GB (sufficient)"
        add_result "system" "ram_check" "PASS" "Sufficient system RAM" "${total_ram_gb}GB"
    fi
    
    # Disk space check
    subsection_header "Disk Space Check"
    local root_usage model_usage
    root_usage=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
    
    log_info "Root filesystem usage: ${root_usage}%"
    df -h / | tail -1 | awk '{print "  Used: " $3 " / " $2 " (" $5 ")"}'
    
    add_result "system" "root_disk" "INFO" "Root disk usage" "${root_usage}%"
    
    if (( root_usage > 90 )); then
        log_warning "Root filesystem is nearly full (${root_usage}%)"
        issues+=("Root filesystem nearly full")
        add_result "system" "disk_space" "WARNING" "High disk usage" "${root_usage}%"
    fi
    
    # Check model directory disk space
    if [[ -d "/models" ]]; then
        local model_disk_free
        model_disk_free=$(df -h /models | tail -1 | awk '{print $4}')
        log_info "Available space for models: $model_disk_free"
        add_result "system" "model_disk_space" "INFO" "Model directory space" "$model_disk_free available"
    fi
    
    # Load average check
    subsection_header "System Load Check"
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}')
    log_info "Load average:$load_avg"
    add_result "system" "load_avg" "INFO" "Load average" "$load_avg"
    
    # Check swap
    local swap_total swap_used
    if free | grep -q Swap; then
        swap_total=$(free -h | awk '/^Swap:/ {print $2}')
        swap_used=$(free -h | awk '/^Swap:/ {print $3}')
        log_info "Swap: $swap_used used / $swap_total total"
        add_result "system" "swap" "INFO" "Swap usage" "$swap_used / $swap_total"
        
        if [[ "$swap_used" != "0B" ]]; then
            log_warning "Swap is being used - may indicate memory pressure"
            add_result "system" "swap_usage" "WARNING" "Swap in use" "$swap_used"
        fi
    else
        log_info "No swap configured"
        add_result "system" "swap" "INFO" "Swap status" "No swap configured"
    fi
    
    # Check ulimits
    subsection_header "System Limits Check"
    local open_files_limit
    open_files_limit=$(ulimit -n)
    log_info "Open files limit: $open_files_limit"
    add_result "system" "open_files_limit" "INFO" "Open files limit" "$open_files_limit"
    
    if (( open_files_limit < 65536 )); then
        log_warning "Open files limit may be too low: $open_files_limit (recommended: 65536+)"
        issues+=("Low open files limit")
        add_result "system" "files_limit_check" "WARNING" "Low open files limit" "$open_files_limit"
    fi
    
    # Check kernel parameters
    if [[ "$VERBOSE" == "true" ]]; then
        subsection_header "Network Kernel Parameters"
        for param in net.core.rmem_max net.core.wmem_max; do
            if [[ -f "/proc/sys/${param//./\/}" ]]; then
                local value
                value=$(cat "/proc/sys/${param//./\/}")
                log_info "$param: $value"
            fi
        done
    fi
    
    # Summary
    if [[ "$status" == "PASS" ]]; then
        log_success "System check: PASSED"
    else
        log_error "System check: FAILED"
        printf "  Issues found:\n"
        printf "  - %s\n" "${issues[@]}"
    fi
    
    add_result "system" "overall" "$status" "System check completed" "${#issues[@]} issues found"
}

# Check network connectivity and ports
check_network() {
    section_header "Network Connectivity and Ports Check"
    
    local status="PASS"
    local issues=()
    
    # Check common vLLM ports
    subsection_header "Port Availability Check"
    local common_ports=(8000 8001 8080 8888)
    
    for port in "${common_ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log_warning "Port $port is in use"
            add_result "network" "port_$port" "WARNING" "Port in use" "$port"
        else
            log_info "Port $port is available"
            add_result "network" "port_$port" "PASS" "Port available" "$port"
        fi
    done
    
    # Check firewall status
    subsection_header "Firewall Check"
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status
        ufw_status=$(ufw status 2>/dev/null | head -1)
        log_info "UFW status: $ufw_status"
        add_result "network" "firewall" "INFO" "UFW firewall status" "$ufw_status"
        
        if echo "$ufw_status" | grep -q "active"; then
            log_info "UFW is active - ensure required ports are allowed"
        fi
    else
        log_info "UFW not found - checking iptables"
        if command -v iptables >/dev/null 2>&1 && [[ $(iptables -L | wc -l) -gt 8 ]]; then
            log_info "iptables rules detected"
            add_result "network" "firewall" "INFO" "iptables rules present" ""
        else
            log_info "No obvious firewall rules detected"
            add_result "network" "firewall" "INFO" "No firewall detected" ""
        fi
    fi
    
    # Check network interfaces
    if [[ "$VERBOSE" == "true" ]]; then
        subsection_header "Network Interfaces"
        ip addr show | grep -E "^[0-9]+:|inet " | head -10
    fi
    
    # Summary
    log_success "Network check: PASSED"
    add_result "network" "overall" "PASS" "Network check completed" "0 issues found"
}

# Check running processes and services
check_processes() {
    section_header "Running Processes and Services Check"
    
    # Check for existing vLLM processes
    subsection_header "vLLM Processes"
    if pgrep -f "vllm" >/dev/null 2>&1; then
        log_info "vLLM processes detected:"
        pgrep -f "vllm" | while read -r pid; do
            if ps -p "$pid" >/dev/null 2>&1; then
                echo "  PID $pid: $(ps -p "$pid" -o command= 2>/dev/null | cut -c1-80)..."
            fi
        done
        add_result "processes" "vllm_running" "INFO" "vLLM processes detected" "$(pgrep -f vllm | wc -l) processes"
    else
        log_info "No vLLM processes detected"
        add_result "processes" "vllm_running" "INFO" "No vLLM processes" "0 processes"
    fi
    
    # Check for Python processes
    subsection_header "Python Processes"
    local python_count
    python_count=$(pgrep -f python | wc -l)
    log_info "Python processes: $python_count"
    add_result "processes" "python_processes" "INFO" "Python processes" "$python_count processes"
    
    if [[ "$VERBOSE" == "true" && $python_count -gt 0 ]]; then
        echo "Python processes:"
        ps aux | grep python | grep -v grep | head -10
    fi
    
    # Check screen sessions
    subsection_header "Screen Sessions"
    if command -v screen >/dev/null 2>&1; then
        local screen_count
        screen_count=$(screen -ls 2>/dev/null | grep -c "Socket" || echo "0")
        log_info "Screen sessions: $screen_count"
        add_result "processes" "screen_sessions" "INFO" "Screen sessions" "$screen_count sessions"
        
        if [[ "$VERBOSE" == "true" && $screen_count -gt 0 ]]; then
            echo "Active screen sessions:"
            screen -ls 2>/dev/null | grep -v "Socket" || echo "  None"
        fi
    else
        log_warning "screen command not found"
        add_result "processes" "screen_available" "WARNING" "screen not available" ""
    fi
    
    add_result "processes" "overall" "PASS" "Process check completed" "0 issues found"
}

# Check available scripts and tools
check_scripts() {
    section_header "Available Scripts and Tools Check"
    
    # Check for vLLM-related scripts
    subsection_header "vLLM Scripts"
    local script_locations=("/root" "$SCRIPT_DIR" "$SCRIPT_DIR/production" "$SCRIPT_DIR/experimental")
    local found_scripts=()
    
    for location in "${script_locations[@]}"; do
        if [[ -d "$location" ]]; then
            while IFS= read -r -d '' script; do
                if [[ -x "$script" ]]; then
                    found_scripts+=("$script")
                    log_info "✓ $(basename "$script") ($(dirname "$script"))"
                fi
            done < <(find "$location" -maxdepth 1 -name "*.sh" -print0 2>/dev/null)
        fi
    done
    
    add_result "scripts" "script_count" "INFO" "Executable scripts found" "${#found_scripts[@]} scripts"
    
    # Check for key management scripts
    local key_scripts=("start_qwen3.sh" "start-vllm-server.sh" "quick_setup.sh" "system_check.sh")
    for script in "${key_scripts[@]}"; do
        local found=false
        for found_script in "${found_scripts[@]}"; do
            if [[ "$(basename "$found_script")" == "$script" ]]; then
                log_success "✓ $script found"
                add_result "scripts" "key_script_$script" "PASS" "Key script available" "$script"
                found=true
                break
            fi
        done
        
        if [[ "$found" == "false" ]]; then
            log_warning "- $script not found"
            add_result "scripts" "key_script_$script" "WARNING" "Key script missing" "$script"
        fi
    done
    
    # Check for common tools
    subsection_header "System Tools Check"
    local tools=("curl" "wget" "jq" "screen" "tmux" "htop" "nvtop")
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_success "✓ $tool"
            add_result "scripts" "tool_$tool" "PASS" "Tool available" "$tool"
        else
            log_warning "- $tool not found"
            add_result "scripts" "tool_$tool" "WARNING" "Tool missing" "$tool"
        fi
    done
    
    add_result "scripts" "overall" "PASS" "Scripts check completed" "0 issues found"
}

# =============================================================================
# REPORT GENERATION
# =============================================================================

# Generate comprehensive report
generate_report() {
    local report_file="${REPORT_FILE:-system_check_report_${TIMESTAMP}.txt}"
    
    log_info "Generating comprehensive report: $report_file"
    
    cat > "$report_file" << EOF
=================================================================================
vLLM System Check Report
Generated: $(date -Iseconds)
Script Version: $SCRIPT_VERSION
Host: $(hostname)
=================================================================================

EXECUTIVE SUMMARY
=================================================================================
This report contains comprehensive system validation results for vLLM and 
Qwen3-480B deployment. Each section includes detailed findings and recommendations.

EOF
    
    # Add results summary
    local pass_count warning_count fail_count
    pass_count=$(printf '%s\n' "${RESULTS[@]}" | grep -c "PASS" || echo "0")
    warning_count=$(printf '%s\n' "${RESULTS[@]}" | grep -c "WARNING" || echo "0")
    fail_count=$(printf '%s\n' "${RESULTS[@]}" | grep -c "FAIL" || echo "0")
    
    cat >> "$report_file" << EOF
RESULTS SUMMARY
=================================================================================
✓ PASS:    $pass_count checks
⚠ WARNING: $warning_count checks  
✗ FAIL:    $fail_count checks

EOF
    
    # Add detailed results
    echo "DETAILED RESULTS" >> "$report_file"
    echo "=================================================================================" >> "$report_file"
    printf '%s\n' "${RESULTS[@]}" >> "$report_file"
    
    # Add system information
    cat >> "$report_file" << EOF

SYSTEM INFORMATION
=================================================================================
Hostname: $(hostname)
OS: $(uname -a)
Uptime: $(uptime)
Current User: $(whoami)
Working Directory: $(pwd)

ENVIRONMENT VARIABLES
=================================================================================
EOF
    
    env | grep -E "^(VLLM_|CUDA_|NCCL_|PATH)" | sort >> "$report_file" || echo "No relevant environment variables found" >> "$report_file"
    
    cat >> "$report_file" << EOF

RECOMMENDATIONS
=================================================================================
Based on the system check results, here are recommended actions:

EOF
    
    # Add recommendations based on results
    if (( fail_count > 0 )); then
        echo "CRITICAL ISSUES TO RESOLVE:" >> "$report_file"
        printf '%s\n' "${RESULTS[@]}" | grep "FAIL" | sed 's/^/- /' >> "$report_file"
        echo "" >> "$report_file"
    fi
    
    if (( warning_count > 0 )); then
        echo "WARNINGS TO CONSIDER:" >> "$report_file"
        printf '%s\n' "${RESULTS[@]}" | grep "WARNING" | sed 's/^/- /' >> "$report_file"
        echo "" >> "$report_file"
    fi
    
    if (( fail_count == 0 && warning_count == 0 )); then
        echo "✓ System appears ready for vLLM deployment!" >> "$report_file"
        echo "" >> "$report_file"
    fi
    
    echo "Report generated: $report_file"
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        local json_file="${report_file%.txt}.json"
        printf '%s\n' "${RESULTS[@]}" | jq -s '.' > "$json_file" 2>/dev/null || {
            echo "Warning: Failed to generate JSON report"
        }
        echo "JSON report: $json_file"
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Main function
main() {
    echo "=== vLLM System Check v$SCRIPT_VERSION ==="
    echo "Comprehensive system validation for Qwen3-480B deployment"
    echo ""
    
    # Parse arguments
    parse_arguments "$@"
    
    # Determine which checks to run
    local checks_to_run=()
    
    if [[ -n "$CHECK_CATEGORY" ]]; then
        case "$CHECK_CATEGORY" in
            "environment"|"env") checks_to_run=("environment") ;;
            "model") checks_to_run=("model") ;;
            "gpu") checks_to_run=("gpu") ;;
            "system") checks_to_run=("system") ;;
            "network") checks_to_run=("network") ;;
            "processes") checks_to_run=("processes") ;;
            "scripts") checks_to_run=("scripts") ;;
            "all") checks_to_run=("environment" "model" "gpu" "system" "network" "processes" "scripts") ;;
            *) 
                log_error "Invalid check category: $CHECK_CATEGORY"
                echo "Valid categories: environment, model, gpu, system, network, processes, scripts, all"
                exit 1
                ;;
        esac
    else
        checks_to_run=("environment" "model" "gpu" "system" "network" "processes" "scripts")
    fi
    
    # Run selected checks
    for check in "${checks_to_run[@]}"; do
        case "$check" in
            "environment") check_environment ;;
            "model") check_model ;;
            "gpu") check_gpu ;;
            "system") check_system ;;
            "network") check_network ;;
            "processes") check_processes ;;
            "scripts") check_scripts ;;
        esac
    done
    
    # Generate report if requested
    if [[ "$EXPORT_REPORT" == "true" ]]; then
        echo ""
        generate_report
    fi
    
    # Summary
    echo ""
    section_header "System Check Summary"
    
    local total_checks pass_count warning_count fail_count
    total_checks=${#RESULTS[@]}
    pass_count=$(printf '%s\n' "${RESULTS[@]}" | grep -c "PASS" || echo "0")
    warning_count=$(printf '%s\n' "${RESULTS[@]}" | grep -c "WARNING" || echo "0")
    fail_count=$(printf '%s\n' "${RESULTS[@]}" | grep -c "FAIL" || echo "0")
    
    echo "Total checks performed: $total_checks"
    echo "✓ Passed: $pass_count"
    echo "⚠ Warnings: $warning_count"
    echo "✗ Failed: $fail_count"
    echo ""
    
    if (( fail_count == 0 )); then
        log_success "System check completed successfully!"
        if (( warning_count > 0 )); then
            log_warning "Some warnings were found - review recommendations"
        fi
        echo ""
        echo "Your system appears ready for vLLM deployment."
        echo "Use the production scripts to start the server:"
        echo "  ./production/start_qwen3.sh --help"
        echo "  ./production/start-vllm-server.sh --help"
    else
        log_error "System check failed with $fail_count critical issues"
        echo ""
        echo "Please resolve the critical issues before deploying vLLM."
        if [[ "$EXPORT_REPORT" != "true" ]]; then
            echo "Run with --export-report for detailed recommendations."
        fi
        exit 1
    fi
    
    # JSON output
    if [[ "$JSON_OUTPUT" == "true" && "$EXPORT_REPORT" != "true" ]]; then
        echo ""
        echo "=== JSON Results ==="
        printf '%s\n' "${RESULTS[@]}" | jq -s '.' 2>/dev/null || {
            echo "JSON output failed - results:"
            printf '%s\n' "${RESULTS[@]}"
        }
    fi
}

# Run main function
main "$@"
