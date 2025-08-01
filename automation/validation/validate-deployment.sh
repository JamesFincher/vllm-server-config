#!/bin/bash
# Comprehensive Deployment Validation Script
# Validates vLLM server deployment, configuration, and performance

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE=""
LOG_FILE="/var/log/vllm-deployment/validation.log"

# Default configuration
API_ENDPOINT="http://localhost:8000"
API_KEY=""
TIMEOUT=30
PERFORMANCE_THRESHOLD=10.0
GPU_MEMORY_THRESHOLD=95
CPU_THRESHOLD=90
MEMORY_THRESHOLD=90

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Validation state
total_checks=0
passed_checks=0
warnings=0
errors=0

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] [VALIDATION]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    ((errors++))
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
    ((warnings++))
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

run_check() {
    local check_name="$1"
    local check_function="$2"
    local severity="${3:-error}"  # error, warning, info
    
    ((total_checks++))
    log "Running check: $check_name"
    
    if $check_function; then
        success "✅ $check_name: PASSED"
        ((passed_checks++))
        return 0
    else
        case "$severity" in
            "error")
                error "❌ $check_name: FAILED"
                ;;
            "warning")
                warning "⚠️  $check_name: WARNING"
                ((passed_checks++))  # Count warnings as passed for overall scoring
                ;;
            "info")
                info "ℹ️  $check_name: INFO"
                ((passed_checks++))
                ;;
        esac
        return 1
    fi
}

show_help() {
    cat << EOF
Deployment Validation Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --config FILE       Use alternative config file
    --api-key KEY       API key for testing
    --endpoint URL      API endpoint to test (default: http://localhost:8000)
    --timeout SECONDS   Request timeout (default: 30)
    --quick             Run only essential checks
    --detailed          Run comprehensive validation including performance tests
    --report FILE       Generate detailed report to file
    --dry-run           Show what checks would be run without executing
    --help              Show this help message

EXAMPLES:
    $0                                    # Basic validation
    $0 --detailed                         # Comprehensive validation
    $0 --quick --api-key mykey           # Quick validation with custom API key
    $0 --report /tmp/validation.json     # Generate detailed report

EOF
}

# Parse arguments
QUICK_MODE=false
DETAILED_MODE=false
REPORT_FILE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --api-key)
            API_KEY="$2"
            shift 2
            ;;
        --endpoint)
            API_ENDPOINT="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --quick)
            QUICK_MODE=true
            shift
            ;;
        --detailed)
            DETAILED_MODE=true
            shift
            ;;
        --report)
            REPORT_FILE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Load configuration if provided
if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

# Validation functions
check_system_requirements() {
    log "Checking system requirements..."
    
    # Check OS
    if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
        warning "Not running on Ubuntu (supported but not tested)"
    fi
    
    # Check available memory
    local total_ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $total_ram_gb -lt 400 ]]; then
        error "Insufficient RAM: ${total_ram_gb}GB (minimum 400GB recommended)"
        return 1
    fi
    
    # Check disk space
    local available_disk=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    if [[ $available_disk -lt 100 ]]; then
        error "Insufficient disk space: ${available_disk}GB (minimum 100GB free required)"
        return 1
    fi
    
    return 0
}

check_gpu_availability() {
    log "Checking GPU availability..."
    
    if ! command -v nvidia-smi &> /dev/null; then
        error "nvidia-smi not found"
        return 1
    fi
    
    local gpu_count=$(nvidia-smi -L 2>/dev/null | wc -l)
    if [[ $gpu_count -lt 4 ]]; then
        error "Insufficient GPUs: found $gpu_count, minimum 4 required"
        return 1
    fi
    
    # Check GPU memory
    local insufficient_gpus=0
    while IFS= read -r memory; do
        if [[ $memory -lt 140000 ]]; then
            ((insufficient_gpus++))
        fi
    done < <(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)
    
    if [[ $insufficient_gpus -gt 0 ]]; then
        error "$insufficient_gpus GPUs have insufficient memory (need 140GB+)"
        return 1
    fi
    
    return 0
}

check_service_status() {
    log "Checking vLLM service status..."
    
    if ! systemctl is-active --quiet vllm-server; then
        error "vLLM service is not running"
        return 1
    fi
    
    if ! systemctl is-enabled --quiet vllm-server; then
        warning "vLLM service is not enabled for auto-start"
    fi
    
    return 0
}

check_api_health() {
    log "Checking API health..."
    
    # Health endpoint
    if ! curl -f -s --max-time "$TIMEOUT" "$API_ENDPOINT/health" > /dev/null; then
        error "Health endpoint not responding"
        return 1
    fi
    
    # Models endpoint
    if [[ -n "$API_KEY" ]]; then
        if ! curl -f -s --max-time "$TIMEOUT" \
            -H "Authorization: Bearer $API_KEY" \
            "$API_ENDPOINT/v1/models" > /dev/null; then
            error "Models endpoint not responding or authentication failed"
            return 1
        fi
    else
        warning "No API key provided, skipping authenticated endpoint tests"
    fi
    
    return 0
}

check_api_functionality() {
    log "Checking API functionality..."
    
    if [[ -z "$API_KEY" ]]; then
        warning "No API key provided, skipping functionality tests"
        return 0
    fi
    
    # Test completion endpoint
    local response=$(curl -s --max-time "$TIMEOUT" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d '{"model":"qwen3","messages":[{"role":"user","content":"Say OK if you are working"}],"max_tokens":10,"temperature":0.1}' \
        "$API_ENDPOINT/v1/chat/completions")
    
    if ! echo "$response" | jq -e '.choices[0].message.content' > /dev/null 2>&1; then
        error "API completion test failed"
        return 1
    fi
    
    return 0
}

check_performance() {
    log "Checking API performance..."
    
    if [[ -z "$API_KEY" ]]; then
        warning "No API key provided, skipping performance tests"
        return 0
    fi
    
    local start_time=$(date +%s.%3N)
    
    curl -s --max-time "$TIMEOUT" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d '{"model":"qwen3","messages":[{"role":"user","content":"Write a short paragraph about AI."}],"max_tokens":50,"temperature":0.3}' \
        "$API_ENDPOINT/v1/chat/completions" > /dev/null
    
    local end_time=$(date +%s.%3N)
    local response_time=$(echo "$end_time - $start_time" | bc -l)
    
    if (( $(echo "$response_time > $PERFORMANCE_THRESHOLD" | bc -l) )); then
        warning "API response time is high: ${response_time}s (threshold: ${PERFORMANCE_THRESHOLD}s)"
        return 1
    fi
    
    info "API response time: ${response_time}s"
    return 0
}

check_gpu_utilization() {
    log "Checking GPU utilization..."
    
    if ! command -v nvidia-smi &> /dev/null; then
        warning "nvidia-smi not available, skipping GPU checks"
        return 0
    fi
    
    # Check GPU memory usage
    local high_usage_gpus=0
    while IFS= read -r usage; do
        if [[ $usage -gt $GPU_MEMORY_THRESHOLD ]]; then
            ((high_usage_gpus++))
        fi
    done < <(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | awk '{print int($1/1024)}')
    
    if [[ $high_usage_gpus -gt 0 ]]; then
        warning "$high_usage_gpus GPUs have high memory usage (>${GPU_MEMORY_THRESHOLD}%)"
    fi
    
    # Check if any GPUs are being used
    local gpus_in_use=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | awk '$1 > 1000 {count++} END {print count+0}')
    
    if [[ $gpus_in_use -lt 2 ]]; then
        error "Insufficient GPUs in use: $gpus_in_use (expected at least 2)"
        return 1
    fi
    
    info "$gpus_in_use GPUs are actively in use"
    return 0
}

check_system_resources() {
    log "Checking system resource usage..."
    
    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    if (( $(echo "$cpu_usage > $CPU_THRESHOLD" | bc -l) )); then
        warning "High CPU usage: ${cpu_usage}%"
    fi
    
    # Memory usage
    local memory_usage=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
    if (( $(echo "$memory_usage > $MEMORY_THRESHOLD" | bc -l) )); then
        warning "High memory usage: ${memory_usage}%"
    fi
    
    return 0
}

check_log_files() {
    log "Checking log files..."
    
    local log_dir="/var/log/vllm"
    if [[ ! -d "$log_dir" ]]; then
        error "Log directory not found: $log_dir"
        return 1
    fi
    
    # Check for recent log files
    local recent_logs=$(find "$log_dir" -name "*.log" -mtime -1 | wc -l)
    if [[ $recent_logs -eq 0 ]]; then
        warning "No recent log files found in $log_dir"
    fi
    
    # Check for error patterns in logs
    local error_count=$(find "$log_dir" -name "*.log" -mtime -1 -exec grep -i "error\|exception\|failed" {} \; 2>/dev/null | wc -l)
    if [[ $error_count -gt 10 ]]; then
        warning "High number of errors in recent logs: $error_count"
    fi
    
    return 0
}

check_configuration_files() {
    log "Checking configuration files..."
    
    local config_dir="/etc/vllm"
    if [[ ! -d "$config_dir" ]]; then
        error "Configuration directory not found: $config_dir"
        return 1
    fi
    
    # Check for essential configuration files
    local essential_configs=("deployment.conf")
    for config in "${essential_configs[@]}"; do
        if [[ ! -f "$config_dir/$config" ]]; then
            warning "Configuration file not found: $config_dir/$config"
        fi
    done
    
    return 0
}

check_model_files() {
    log "Checking model files..."
    
    local model_path="/models/qwen3"
    if [[ ! -d "$model_path" ]]; then
        error "Model directory not found: $model_path"
        return 1
    fi
    
    # Check for essential model files
    local essential_files=("config.json")
    for file in "${essential_files[@]}"; do
        if [[ ! -f "$model_path/$file" ]]; then
            error "Essential model file not found: $model_path/$file"
            return 1
        fi
    done
    
    # Check model directory size
    local model_size_gb=$(du -sh "$model_path" | cut -f1 | sed 's/G//')
    if [[ $model_size_gb -lt 400 ]]; then
        warning "Model directory seems small: ${model_size_gb}GB (expected ~450GB)"
    fi
    
    return 0
}

check_security() {
    log "Checking security configuration..."
    
    # Check for default/weak API keys
    if [[ "$API_KEY" == "YOUR_API_KEY_HERE" ]] || [[ "$API_KEY" == "your-secret-key" ]]; then
        error "Default/weak API key detected"
        return 1
    fi
    
    # Check file permissions
    local sensitive_files=("/etc/vllm/deployment.conf")
    for file in "${sensitive_files[@]}"; do
        if [[ -f "$file" ]]; then
            local perms=$(stat -c "%a" "$file")
            if [[ "$perms" != "600" ]] && [[ "$perms" != "640" ]]; then
                warning "Insecure permissions on $file: $perms"
            fi
        fi
    done
    
    return 0
}

generate_report() {
    local report_data=$(cat << EOF
{
    "timestamp": "$(date -Iseconds)",
    "validation_summary": {
        "total_checks": $total_checks,
        "passed_checks": $passed_checks,
        "warnings": $warnings,
        "errors": $errors,
        "success_rate": $(echo "scale=2; $passed_checks * 100 / $total_checks" | bc -l)
    },
    "system_info": {
        "hostname": "$(hostname)",
        "os": "$(lsb_release -d 2>/dev/null | cut -f2 || echo 'Unknown')",
        "kernel": "$(uname -r)",
        "uptime": "$(uptime -p)",
        "load_average": "$(uptime | awk -F'load average:' '{print $2}')"
    },
    "api_status": {
        "endpoint": "$API_ENDPOINT",
        "health_check": $(curl -f -s --max-time 5 "$API_ENDPOINT/health" > /dev/null && echo "true" || echo "false")
    }
}
EOF
    )
    
    if [[ -n "$REPORT_FILE" ]]; then
        echo "$report_data" > "$REPORT_FILE"
        log "Detailed report saved to: $REPORT_FILE"
    fi
    
    return 0
}

main() {
    log "Starting vLLM deployment validation..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN MODE - Showing what checks would be performed:"
        echo "- System requirements check"
        echo "- GPU availability check"
        echo "- Service status check"
        echo "- API health check"
        if [[ "$QUICK_MODE" != "true" ]]; then
            echo "- API functionality check"
            echo "- Performance check"
            echo "- GPU utilization check"
            echo "- System resources check"
            echo "- Log files check"
            echo "- Configuration files check"
            echo "- Model files check"
            echo "- Security check"
        fi
        return 0
    fi
    
    # Essential checks (always run)
    run_check "System Requirements" check_system_requirements
    run_check "GPU Availability" check_gpu_availability
    run_check "Service Status" check_service_status
    run_check "API Health" check_api_health
    
    if [[ "$QUICK_MODE" == "true" ]]; then
        log "Quick mode enabled, skipping detailed checks"
    else
        # Standard checks
        run_check "API Functionality" check_api_functionality
        run_check "Performance" check_performance warning
        run_check "GPU Utilization" check_gpu_utilization
        run_check "System Resources" check_system_resources warning
        run_check "Log Files" check_log_files warning
        run_check "Configuration Files" check_configuration_files
        run_check "Model Files" check_model_files
        run_check "Security" check_security warning
    fi
    
    # Generate report
    generate_report
    
    # Summary
    log "Validation completed"
    echo
    echo "=============================================="
    echo "           VALIDATION SUMMARY"
    echo "=============================================="
    echo "Total Checks: $total_checks"
    echo "Passed: $passed_checks"
    echo "Warnings: $warnings"
    echo "Errors: $errors"
    
    local success_rate=$(echo "scale=1; $passed_checks * 100 / $total_checks" | bc -l)
    echo "Success Rate: ${success_rate}%"
    
    if [[ $errors -eq 0 ]]; then
        if [[ $warnings -eq 0 ]]; then
            echo -e "\n${GREEN}🎉 VALIDATION PASSED - Deployment is healthy!${NC}"
            exit 0
        else
            echo -e "\n${YELLOW}⚠️  VALIDATION PASSED WITH WARNINGS${NC}"
            exit 0
        fi
    else
        echo -e "\n${RED}❌ VALIDATION FAILED - $errors critical issues found${NC}"
        exit 1
    fi
}

main "$@"