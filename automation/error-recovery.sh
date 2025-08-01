#!/bin/bash
# Comprehensive Error Handling and Recovery System for vLLM Server
# Provides automated error detection, diagnosis, and recovery mechanisms

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/vllm-deployment/error-recovery.log"
STATE_FILE="/var/lib/vllm/error-recovery-state.json"
RECOVERY_ROOT="/opt/vllm-recovery"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Recovery configuration
MAX_RECOVERY_ATTEMPTS=3
RECOVERY_TIMEOUT=600  # 10 minutes
HEALTH_CHECK_INTERVAL=30
AUTO_RECOVERY_ENABLED=true

# Error patterns and signatures
declare -A ERROR_PATTERNS=(
    ["CUDA_OUT_OF_MEMORY"]="CUDA out of memory|cuda runtime error|out of GPU memory"
    ["MODEL_LOADING_FAILED"]="Failed to load model|Model loading error|Unable to load"
    ["API_TIMEOUT"]="Request timeout|Connection timeout|Timeout error"
    ["GPU_COMMUNICATION_ERROR"]="NCCL error|GPU communication failed|CUDA error"
    ["SERVICE_CRASH"]="Segmentation fault|Core dumped|Process died"
    ["DISK_FULL"]="No space left on device|Disk full|Storage error"
    ["MEMORY_EXHAUSTED"]="Cannot allocate memory|Out of memory|Memory error"
    ["CONFIG_ERROR"]="Configuration error|Invalid config|Config parse error"
    ["PERMISSION_ERROR"]="Permission denied|Access denied|Unauthorized"
    ["NETWORK_ERROR"]="Connection refused|Network unreachable|DNS error"
)

# Recovery strategies for each error type
declare -A RECOVERY_STRATEGIES=(
    ["CUDA_OUT_OF_MEMORY"]="restart_with_lower_memory"
    ["MODEL_LOADING_FAILED"]="check_model_files_and_restart"
    ["API_TIMEOUT"]="restart_service"
    ["GPU_COMMUNICATION_ERROR"]="reset_gpus_and_restart"
    ["SERVICE_CRASH"]="capture_core_dump_and_restart"
    ["DISK_FULL"]="cleanup_logs_and_restart"
    ["MEMORY_EXHAUSTED"]="restart_with_lower_memory"
    ["CONFIG_ERROR"]="restore_config_and_restart"
    ["PERMISSION_ERROR"]="fix_permissions_and_restart"
    ["NETWORK_ERROR"]="check_network_and_restart"
)

# Create necessary directories
mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$STATE_FILE")" "$RECOVERY_ROOT"/{logs,dumps,temp}

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] [RECOVERY]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

critical() {
    echo -e "${PURPLE}[CRITICAL]${NC} $1" | tee -a "$LOG_FILE"
}

save_recovery_state() {
    local state="$1"
    local error_type="$2"
    local attempt="$3"
    local message="$4"
    
    local state_data=$(cat << EOF
{
    "timestamp": "$(date -Iseconds)",
    "hostname": "$(hostname)",
    "state": "$state",
    "error_type": "$error_type",
    "recovery_attempt": $attempt,
    "message": "$message",
    "max_attempts": $MAX_RECOVERY_ATTEMPTS,
    "auto_recovery_enabled": $AUTO_RECOVERY_ENABLED
}
EOF
    )
    
    echo "$state_data" > "$STATE_FILE"
}

get_recovery_state() {
    if [[ -f "$STATE_FILE" ]]; then
        jq -r '.state' "$STATE_FILE" 2>/dev/null || echo "unknown"
    else
        echo "none"
    fi
}

detect_error_type() {
    local log_content="$1"
    
    for error_type in "${!ERROR_PATTERNS[@]}"; do
        if echo "$log_content" | grep -iE "${ERROR_PATTERNS[$error_type]}" > /dev/null; then
            echo "$error_type"
            return 0
        fi
    done
    
    echo "UNKNOWN_ERROR"
}

collect_diagnostic_info() {
    local error_type="$1"
    local diagnostic_dir="$RECOVERY_ROOT/diagnostics-$(date +%Y%m%d-%H%M%S)"
    
    log "Collecting diagnostic information for $error_type..."
    mkdir -p "$diagnostic_dir"
    
    # System information
    uname -a > "$diagnostic_dir/system-info.txt"
    free -h > "$diagnostic_dir/memory.txt"
    df -h > "$diagnostic_dir/disk-usage.txt"
    
    # Service information
    systemctl status vllm-server > "$diagnostic_dir/service-status.txt" 2>&1 || true
    journalctl -u vllm-server --no-pager -n 100 > "$diagnostic_dir/service-logs.txt" 2>&1 || true
    
    # GPU information
    nvidia-smi -q > "$diagnostic_dir/gpu-status.txt" 2>&1 || echo "GPU info unavailable" > "$diagnostic_dir/gpu-status.txt"
    
    # Process information
    ps aux | grep vllm > "$diagnostic_dir/processes.txt" || echo "No vLLM processes" > "$diagnostic_dir/processes.txt"
    
    # Network information
    ss -tuln > "$diagnostic_dir/network-ports.txt"
    
    # vLLM specific logs
    if [[ -d "/var/log/vllm" ]]; then
        cp -r /var/log/vllm "$diagnostic_dir/vllm-logs" 2>/dev/null || true
    fi
    
    # Configuration files
    if [[ -d "/etc/vllm" ]]; then
        cp -r /etc/vllm "$diagnostic_dir/config" 2>/dev/null || true
    fi
    
    # Error-specific diagnostics
    case "$error_type" in
        "CUDA_OUT_OF_MEMORY"|"GPU_COMMUNICATION_ERROR")
            nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv > "$diagnostic_dir/gpu-memory.csv" 2>&1 || true
            ;;
        "DISK_FULL")
            du -h /var/log > "$diagnostic_dir/log-sizes.txt" 2>&1 || true
            du -h /tmp > "$diagnostic_dir/tmp-sizes.txt" 2>&1 || true
            ;;
        "MEMORY_EXHAUSTED")
            cat /proc/meminfo > "$diagnostic_dir/meminfo.txt"
            slabtop -o > "$diagnostic_dir/slab-info.txt" 2>&1 || true
            ;;
    esac
    
    success "Diagnostic information collected in $diagnostic_dir"
    echo "$diagnostic_dir"
}

send_alert() {
    local severity="$1"
    local error_type="$2"
    local message="$3"
    local diagnostic_dir="${4:-}"
    
    log "Sending $severity alert for $error_type"
    
    # Create alert payload
    local alert_message="vLLM Server Error Recovery Alert

Severity: $severity
Error Type: $error_type
Host: $(hostname)
Time: $(date)
Message: $message

$(if [[ -n "$diagnostic_dir" ]]; then echo "Diagnostics: $diagnostic_dir"; fi)"
    
    # Send to monitoring system if available
    if command -v vllm-monitor > /dev/null 2>&1; then
        # Integration with monitoring system
        echo "ALERT:$severity:$error_type:$message" >> /tmp/vllm-alerts.txt
    fi
    
    # Slack notification (if configured)
    if [[ -n "${SLACK_WEBHOOK:-}" ]]; then
        local color="danger"
        case "$severity" in
            "WARNING") color="warning" ;;
            "INFO") color="good" ;;
        esac
        
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"attachments\":[{\"color\":\"$color\",\"title\":\"vLLM $severity: $error_type\",\"text\":\"$alert_message\"}]}" \
            "$SLACK_WEBHOOK" > /dev/null 2>&1 || true
    fi
}

restart_service() {
    log "Restarting vLLM service..."
    
    # Stop service gracefully
    if systemctl is-active --quiet vllm-server; then
        systemctl stop vllm-server
        
        # Wait for graceful shutdown
        local wait_count=0
        while pgrep -f vllm > /dev/null && [[ $wait_count -lt 30 ]]; do
            sleep 2
            ((wait_count++))
        done
        
        # Force kill if necessary
        if pgrep -f vllm > /dev/null; then
            warning "Force killing remaining vLLM processes..."
            pkill -9 -f vllm || true
            sleep 5
        fi
    fi
    
    # Start service
    systemctl start vllm-server
    
    # Wait for service to be ready
    local ready_wait=0
    while [[ $ready_wait -lt 180 ]]; do  # 3 minutes
        if systemctl is-active --quiet vllm-server; then
            if curl -f -s --max-time 10 "http://localhost:8000/health" > /dev/null 2>&1; then
                success "Service restarted and healthy"
                return 0
            fi
        fi
        sleep 10
        ((ready_wait+=10))
        log "Waiting for service to be ready... (${ready_wait}s)"
    done
    
    error "Service restart failed or service not responding"
    return 1
}

restart_with_lower_memory() {
    log "Restarting with reduced memory configuration..."
    
    # Modify configuration to use less memory
    local config_file="/etc/vllm/deployment.conf"
    if [[ -f "$config_file" ]]; then
        # Backup current config
        cp "$config_file" "${config_file}.backup-$(date +%Y%m%d-%H%M%S)"
        
        # Reduce memory settings
        sed -i 's/GPU_MEMORY_UTILIZATION=0.98/GPU_MEMORY_UTILIZATION=0.90/' "$config_file" || true
        sed -i 's/CONTEXT_LENGTH=[0-9]*/CONTEXT_LENGTH=400000/' "$config_file" || true
        
        log "Reduced GPU memory utilization to 90% and context length to 400k"
    fi
    
    restart_service
}

reset_gpus_and_restart() {
    log "Resetting GPUs and restarting service..."
    
    # Reset GPUs
    if command -v nvidia-smi > /dev/null 2>&1; then
        nvidia-smi --gpu-reset -i 0,1,2,3 || warning "GPU reset may have failed"
        sleep 10
    fi
    
    restart_service
}

check_model_files_and_restart() {
    log "Checking model files and restarting..."
    
    local model_path="/models/qwen3"
    if [[ ! -d "$model_path" ]]; then
        error "Model directory not found: $model_path"
        return 1
    fi
    
    # Check essential model files
    local essential_files=("config.json")
    for file in "${essential_files[@]}"; do
        if [[ ! -f "$model_path/$file" ]]; then
            error "Essential model file missing: $model_path/$file"
            return 1
        fi
    done
    
    # Check model directory size (should be around 450GB)
    local model_size_gb=$(du -s "$model_path" | awk '{print int($1/1024/1024)}')
    if [[ $model_size_gb -lt 400 ]]; then
        error "Model directory appears incomplete: ${model_size_gb}GB (expected ~450GB)"
        return 1
    fi
    
    success "Model files appear correct"
    restart_service
}

cleanup_logs_and_restart() {
    log "Cleaning up logs to free disk space..."
    
    # Clean old log files
    find /var/log/vllm -name "*.log" -mtime +7 -delete 2>/dev/null || true
    
    # Clean temporary files
    rm -rf /tmp/vllm-* 2>/dev/null || true
    
    # Clean old core dumps
    find /var/crash -name "core.*" -mtime +3 -delete 2>/dev/null || true
    
    # Clean old diagnostic files
    find "$RECOVERY_ROOT" -name "diagnostics-*" -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
    
    local freed_space=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    log "Disk cleanup completed, available space: ${freed_space}GB"
    
    restart_service
}

restore_config_and_restart() {
    log "Restoring configuration and restarting..."
    
    # Look for backup configuration
    local config_dir="/etc/vllm"
    local backup_config=$(find "$config_dir" -name "*.backup-*" | sort -r | head -1)
    
    if [[ -n "$backup_config" ]]; then
        local original_config="${backup_config%.backup-*}"
        cp "$backup_config" "$original_config"
        success "Restored configuration from $backup_config"
    else
        warning "No backup configuration found, using template"
        # Restore from template if available
        if [[ -f "$SCRIPT_DIR/../configs/environment-template.sh" ]]; then
            cp "$SCRIPT_DIR/../configs/environment-template.sh" "$config_dir/environment.sh"
        fi
    fi
    
    restart_service
}

fix_permissions_and_restart() {
    log "Fixing permissions and restarting..."
    
    # Fix common permission issues
    chown -R root:root /etc/vllm/ 2>/dev/null || true
    chmod 755 /etc/vllm/ 2>/dev/null || true
    chmod 644 /etc/vllm/*.conf 2>/dev/null || true
    
    chown -R root:root /var/log/vllm/ 2>/dev/null || true
    chmod 755 /var/log/vllm/ 2>/dev/null || true
    
    chown -R root:root /models/qwen3/ 2>/dev/null || true
    
    success "Permissions fixed"
    restart_service
}

check_network_and_restart() {
    log "Checking network connectivity and restarting..."
    
    # Check basic connectivity
    if ! ping -c 3 8.8.8.8 > /dev/null 2>&1; then
        error "No internet connectivity"
        return 1
    fi
    
    # Check if port 8000 is available
    if ss -tuln | grep ":8000 " > /dev/null; then
        warning "Port 8000 already in use"
        # Try to identify what's using it
        local port_user=$(ss -tulnp | grep ":8000 " | awk '{print $7}')
        log "Port 8000 used by: $port_user"
        
        # Kill process using port 8000 if it's not our service
        if [[ "$port_user" != *"vllm"* ]]; then
            local pid=$(echo "$port_user" | grep -o '[0-9]*' | head -1)
            if [[ -n "$pid" ]]; then
                kill "$pid" 2>/dev/null || true
                sleep 5
            fi
        fi
    fi
    
    restart_service
}

capture_core_dump_and_restart() {
    log "Capturing core dump and restarting..."
    
    # Look for recent core dumps
    local core_dumps=$(find /var/crash /tmp -name "core.*" -mtime -1 2>/dev/null || true)
    
    if [[ -n "$core_dumps" ]]; then
        local dump_dir="$RECOVERY_ROOT/dumps/crash-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$dump_dir"
        
        for dump in $core_dumps; do
            cp "$dump" "$dump_dir/" 2>/dev/null || true
        done
        
        success "Core dumps saved to $dump_dir"
    fi
    
    restart_service
}

perform_recovery() {
    local error_type="$1"
    local attempt="$2"
    
    log "Performing recovery for $error_type (attempt $attempt/$MAX_RECOVERY_ATTEMPTS)"
    save_recovery_state "recovering" "$error_type" "$attempt" "Executing recovery strategy"
    
    local strategy="${RECOVERY_STRATEGIES[$error_type]:-restart_service}"
    
    if command -v "$strategy" > /dev/null 2>&1; then
        if $strategy; then
            success "Recovery strategy '$strategy' completed successfully"
            return 0
        else
            error "Recovery strategy '$strategy' failed"
            return 1
        fi
    else
        error "Unknown recovery strategy: $strategy"
        restart_service  # Fallback
    fi
}

monitor_and_recover() {
    log "Starting continuous monitoring and recovery..."
    
    local consecutive_failures=0
    local last_error_type=""
    local recovery_attempts=0
    
    while true; do
        # Check service health
        if systemctl is-active --quiet vllm-server; then
            # Check API health
            if curl -f -s --max-time 10 "http://localhost:8000/health" > /dev/null 2>&1; then
                # Service is healthy
                if [[ $consecutive_failures -gt 0 ]]; then
                    success "Service recovered after $consecutive_failures failures"
                    send_alert "INFO" "RECOVERY_SUCCESS" "Service recovered successfully"
                    consecutive_failures=0
                    recovery_attempts=0
                    save_recovery_state "healthy" "NONE" 0 "Service is healthy"
                fi
                
                sleep "$HEALTH_CHECK_INTERVAL"
                continue
            fi
        fi
        
        # Service is unhealthy
        ((consecutive_failures++))
        log "Service health check failed (failure #$consecutive_failures)"
        
        # Collect recent logs for error analysis
        local recent_logs=$(journalctl -u vllm-server --no-pager -n 50 --since "5 minutes ago" 2>/dev/null || echo "")
        if [[ -d "/var/log/vllm" ]]; then
            recent_logs+=" $(find /var/log/vllm -name "*.log" -mtime -1 -exec tail -50 {} \; 2>/dev/null)"
        fi
        
        # Detect error type
        local error_type=$(detect_error_type "$recent_logs")
        log "Detected error type: $error_type"
        
        # Collect diagnostics
        local diagnostic_dir=$(collect_diagnostic_info "$error_type")
        
        # Check if this is a new error or continuation of previous error
        if [[ "$error_type" != "$last_error_type" ]]; then
            recovery_attempts=0
            last_error_type="$error_type"
        fi
        
        ((recovery_attempts++))
        
        if [[ $recovery_attempts -le $MAX_RECOVERY_ATTEMPTS ]]; then
            send_alert "WARNING" "$error_type" "Attempting recovery (attempt $recovery_attempts/$MAX_RECOVERY_ATTEMPTS)" "$diagnostic_dir"
            
            if perform_recovery "$error_type" "$recovery_attempts"; then
                success "Recovery attempt $recovery_attempts succeeded"
                sleep "$HEALTH_CHECK_INTERVAL"
                continue
            else
                error "Recovery attempt $recovery_attempts failed"
            fi
        else
            # Max recovery attempts reached
            critical "Maximum recovery attempts ($MAX_RECOVERY_ATTEMPTS) reached for $error_type"
            send_alert "CRITICAL" "$error_type" "Maximum recovery attempts reached. Manual intervention required." "$diagnostic_dir"
            save_recovery_state "failed" "$error_type" "$recovery_attempts" "Maximum recovery attempts reached"
            
            if [[ "$AUTO_RECOVERY_ENABLED" == "true" ]]; then
                log "Switching to emergency recovery mode..."
                if command -v "$SCRIPT_DIR/validation/rollback-manager.sh" > /dev/null 2>&1; then
                    bash "$SCRIPT_DIR/validation/rollback-manager.sh" emergency --reason "Automated recovery failed for $error_type"
                fi
            fi
            
            # Wait longer before next attempt
            sleep 300  # 5 minutes
            recovery_attempts=0
        fi
        
        sleep "$HEALTH_CHECK_INTERVAL"
    done
}

show_help() {
    cat << EOF
vLLM Error Recovery System

USAGE:
    $0 <command> [options]

COMMANDS:
    monitor              Start continuous monitoring and recovery
    diagnose             Diagnose current system state
    recover <error_type> Perform specific recovery action
    test-recovery        Test recovery mechanisms
    status               Show recovery system status
    enable-auto          Enable automatic recovery
    disable-auto         Disable automatic recovery

ERROR TYPES:
$(for error_type in "${!ERROR_PATTERNS[@]}"; do
    echo "    $error_type"
done)

OPTIONS:
    --max-attempts N     Set maximum recovery attempts (default: $MAX_RECOVERY_ATTEMPTS)
    --timeout N          Set recovery timeout in seconds (default: $RECOVERY_TIMEOUT)
    --interval N         Set health check interval (default: $HEALTH_CHECK_INTERVAL)
    --help               Show this help message

EXAMPLES:
    $0 monitor                           # Start continuous monitoring
    $0 diagnose                         # Diagnose current issues
    $0 recover CUDA_OUT_OF_MEMORY       # Perform specific recovery
    $0 test-recovery                    # Test recovery mechanisms

EOF
}

diagnose_system() {
    log "Running system diagnosis..."
    
    local issues_found=0
    
    # Check service status
    if ! systemctl is-active --quiet vllm-server; then
        error "vLLM service is not running"
        ((issues_found++))
    fi
    
    # Check API health
    if ! curl -f -s --max-time 10 "http://localhost:8000/health" > /dev/null 2>&1; then
        error "API health check failed"
        ((issues_found++))
    fi
    
    # Check GPU status
    if command -v nvidia-smi > /dev/null 2>&1; then
        if ! nvidia-smi > /dev/null 2>&1; then
            error "GPU status check failed"
            ((issues_found++))
        fi
    fi
    
    # Check disk space
    local available_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    if [[ $available_gb -lt 50 ]]; then
        warning "Low disk space: ${available_gb}GB"
        ((issues_found++))
    fi
    
    # Check memory usage
    local memory_usage=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
    if (( $(echo "$memory_usage > 95" | bc -l) )); then
        warning "High memory usage: ${memory_usage}%"
        ((issues_found++))
    fi
    
    # Analyze recent logs for errors
    local log_errors=0
    if [[ -d "/var/log/vllm" ]]; then
        log_errors=$(find /var/log/vllm -name "*.log" -mtime -1 -exec grep -i "error\|exception\|failed" {} \; 2>/dev/null | wc -l)
    fi
    
    if [[ $log_errors -gt 20 ]]; then
        warning "High error count in recent logs: $log_errors"
        ((issues_found++))
    fi
    
    if [[ $issues_found -eq 0 ]]; then
        success "System diagnosis completed - no issues found"
    else
        warning "System diagnosis completed - $issues_found issues found"
    fi
    
    return $issues_found
}

test_recovery_mechanisms() {
    log "Testing recovery mechanisms..."
    
    local tests_passed=0
    local total_tests=0
    
    # Test service restart
    ((total_tests++))
    log "Testing service restart..."
    if restart_service; then
        success "Service restart test passed"
        ((tests_passed++))
    else
        error "Service restart test failed"
    fi
    
    # Test diagnostic collection
    ((total_tests++))
    log "Testing diagnostic collection..."
    if diagnostic_dir=$(collect_diagnostic_info "TEST_ERROR"); then
        if [[ -d "$diagnostic_dir" ]]; then
            success "Diagnostic collection test passed"
            ((tests_passed++))
            rm -rf "$diagnostic_dir"  # Cleanup test diagnostics
        else
            error "Diagnostic collection test failed - directory not created"
        fi
    else
        error "Diagnostic collection test failed"
    fi
    
    # Test error pattern detection
    ((total_tests++))
    log "Testing error pattern detection..."
    local test_log="CUDA out of memory error occurred"
    local detected_error=$(detect_error_type "$test_log")
    if [[ "$detected_error" == "CUDA_OUT_OF_MEMORY" ]]; then
        success "Error pattern detection test passed"
        ((tests_passed++))
    else
        error "Error pattern detection test failed: detected '$detected_error'"
    fi
    
    log "Recovery mechanism tests completed: $tests_passed/$total_tests passed"
    return $((total_tests - tests_passed))
}

main() {
    local command="${1:-help}"
    shift || true
    
    # Parse global options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --max-attempts)
                MAX_RECOVERY_ATTEMPTS="$2"
                shift 2
                ;;
            --timeout)
                RECOVERY_TIMEOUT="$2"
                shift 2
                ;;
            --interval)
                HEALTH_CHECK_INTERVAL="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            -*) 
                error "Unknown option: $1"
                exit 1
                ;;
            *) 
                break
                ;;
        esac
    done
    
    case "$command" in
        monitor)
            monitor_and_recover
            ;;
        diagnose)
            diagnose_system
            ;;
        recover)
            local error_type="${1:-UNKNOWN_ERROR}"
            if [[ -n "${RECOVERY_STRATEGIES[$error_type]:-}" ]]; then
                perform_recovery "$error_type" 1
            else
                error "Unknown error type: $error_type"
                exit 1
            fi
            ;;
        test-recovery)
            test_recovery_mechanisms
            ;;
        status)
            if [[ -f "$STATE_FILE" ]]; then
                cat "$STATE_FILE" | jq .
            else
                log "No recovery state information available"
            fi
            ;;
        enable-auto)
            AUTO_RECOVERY_ENABLED=true
            log "Automatic recovery enabled"
            ;;
        disable-auto)
            AUTO_RECOVERY_ENABLED=false
            log "Automatic recovery disabled"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "Unknown command: $command. Use 'help' for usage information."
            exit 1
            ;;
    esac
}

main "$@"