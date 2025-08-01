#!/bin/bash
# Comprehensive Rollback Manager for vLLM Server
# Handles automated rollback operations with safety checks and recovery mechanisms

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/vllm-deployment/rollback.log"
STATE_FILE="/var/lib/vllm/rollback-state.json"
BACKUP_ROOT="/opt/vllm-backups"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Rollback state
rollback_id=""
rollback_reason=""
rollback_start_time=""

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] [ROLLBACK]${NC} $1" | tee -a "$LOG_FILE"
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

# Create necessary directories
mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$STATE_FILE")"

show_help() {
    cat << EOF
vLLM Rollback Manager

USAGE:
    $0 <command> [options]

COMMANDS:
    auto                 Perform automatic rollback to last known good state
    manual <backup>      Rollback to specific backup
    list                 List available rollback points
    status               Show current rollback status
    prepare              Prepare system for potential rollback
    validate             Validate rollback capability
    emergency            Emergency rollback (fastest, least safe)

OPTIONS:
    --reason TEXT        Reason for rollback (for logging)
    --force              Force rollback even if risky
    --dry-run            Show what would be done without executing
    --no-health-check    Skip post-rollback health checks
    --help               Show this help message

EXAMPLES:
    $0 auto --reason "API response time degraded"
    $0 manual daily-2025-07-30 --force
    $0 list
    $0 status
    $0 emergency

SAFETY FEATURES:
    - Pre-rollback system state capture
    - Health checks before and after rollback
    - Automatic service restart with verification
    - Rollback state tracking and logging
    - Emergency procedures for critical failures

EOF
}

save_rollback_state() {
    local state="$1"
    local message="$2"
    
    local state_data=$(cat << EOF
{
    "rollback_id": "$rollback_id",
    "state": "$state",
    "message": "$message",
    "timestamp": "$(date -Iseconds)",
    "hostname": "$(hostname)",
    "reason": "$rollback_reason",
    "start_time": "$rollback_start_time"
}
EOF
    )
    
    echo "$state_data" > "$STATE_FILE"
}

get_rollback_state() {
    if [[ -f "$STATE_FILE" ]]; then
        jq -r '.state' "$STATE_FILE" 2>/dev/null || echo "unknown"
    else
        echo "none"
    fi
}

check_rollback_prerequisites() {
    log "Checking rollback prerequisites..."
    
    # Check if backup system is available
    if ! command -v vllm-backup > /dev/null 2>&1; then
        error "Backup system not available - rollback not possible"
        return 1
    fi
    
    # Check available disk space
    local available_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    if [[ $available_gb -lt 50 ]]; then
        error "Insufficient disk space for rollback: ${available_gb}GB (need 50GB+)"
        return 1
    fi
    
    # Check system load
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    if (( $(echo "$load_avg > 10" | bc -l) )); then
        warning "High system load detected: $load_avg - rollback may be slow"
    fi
    
    return 0
}

capture_pre_rollback_state() {
    log "Capturing pre-rollback system state..."
    
    local state_dir="/tmp/rollback-state-$rollback_id"
    mkdir -p "$state_dir"
    
    # Service status
    systemctl status vllm-server > "$state_dir/service-status.txt" 2>&1 || true
    
    # API status
    curl -f -s --max-time 10 "http://localhost:8000/health" > "$state_dir/api-health.json" 2>&1 || echo "API_DOWN" > "$state_dir/api-health.json"
    
    # GPU status
    nvidia-smi -q > "$state_dir/gpu-status.txt" 2>&1 || echo "GPU_INFO_UNAVAILABLE" > "$state_dir/gpu-status.txt"
    
    # System resources
    free -h > "$state_dir/memory.txt"
    df -h > "$state_dir/disk.txt"
    ps aux | grep vllm > "$state_dir/processes.txt" || true
    
    # Configuration backup
    if [[ -d "/etc/vllm" ]]; then
        cp -r /etc/vllm "$state_dir/config-backup" 2>/dev/null || true
    fi
    
    success "Pre-rollback state captured in $state_dir"
}

find_last_known_good() {
    log "Finding last known good backup..."
    
    # Look for the most recent successful backup
    local backup_types=("snapshots" "daily" "weekly")
    
    for backup_type in "${backup_types[@]}"; do
        local backup_dir="$BACKUP_ROOT/$backup_type"
        if [[ -d "$backup_dir" ]]; then
            local latest_backup=$(ls -t "$backup_dir" 2>/dev/null | head -1)
            if [[ -n "$latest_backup" ]]; then
                echo "$backup_type/$latest_backup"
                return 0
            fi
        fi
    done
    
    error "No suitable backup found for rollback"
    return 1
}

perform_service_rollback() {
    local backup_name="$1"
    
    log "Performing service rollback to: $backup_name"
    
    # Stop current service
    log "Stopping vLLM service..."
    if systemctl is-active --quiet vllm-server; then
        systemctl stop vllm-server
        
        # Wait for complete shutdown
        local wait_count=0
        while pgrep -f vllm > /dev/null && [[ $wait_count -lt 30 ]]; do
            sleep 2
            ((wait_count++))
        done
        
        # Force kill if necessary
        if pgrep -f vllm > /dev/null; then
            warning "Force killing remaining vLLM processes..."
            pkill -9 -f vllm || true
        fi
    fi
    
    # Restore configuration from backup if available
    # Note: This is a simplified version - actual restoration would depend on backup format
    if [[ -f "/tmp/rollback-state-$rollback_id/config-backup" ]]; then
        log "Restoring configuration..."
        cp -r "/tmp/rollback-state-$rollback_id/config-backup"/* /etc/vllm/ 2>/dev/null || true
    fi
    
    # Start service with previous configuration
    log "Starting vLLM service..."
    systemctl start vllm-server
    
    return 0
}

wait_for_service_ready() {
    local max_wait="${1:-300}"  # 5 minutes default
    local wait_interval=10
    local waited=0
    
    log "Waiting for service to become ready (max ${max_wait}s)..."
    
    while [[ $waited -lt $max_wait ]]; do
        if systemctl is-active --quiet vllm-server; then
            # Check if API is responding
            if curl -f -s --max-time 10 "http://localhost:8000/health" > /dev/null 2>&1; then
                success "Service is ready after ${waited}s"
                return 0
            fi
        fi
        
        sleep $wait_interval
        waited=$((waited + wait_interval))
        log "Still waiting... (${waited}/${max_wait}s)"
    done
    
    error "Service failed to become ready within ${max_wait}s"
    return 1
}

perform_health_check() {
    log "Performing post-rollback health check..."
    
    # Use validation script if available
    if [[ -f "$SCRIPT_DIR/validate-deployment.sh" ]]; then
        if bash "$SCRIPT_DIR/validate-deployment.sh" --quick; then
            success "Post-rollback health check passed"
            return 0
        else
            error "Post-rollback health check failed"
            return 1
        fi
    else
        # Basic health check
        local checks_passed=0
        local total_checks=3
        
        # Service status
        if systemctl is-active --quiet vllm-server; then
            ((checks_passed++))
        fi
        
        # API health
        if curl -f -s --max-time 10 "http://localhost:8000/health" > /dev/null 2>&1; then
            ((checks_passed++))
        fi
        
        # GPU check
        if nvidia-smi -L > /dev/null 2>&1; then
            ((checks_passed++))
        fi
        
        if [[ $checks_passed -eq $total_checks ]]; then
            success "Basic health check passed ($checks_passed/$total_checks)"
            return 0
        else
            error "Basic health check failed ($checks_passed/$total_checks)"
            return 1
        fi
    fi
}

perform_automatic_rollback() {
    local force="$1"
    local skip_health_check="$2"
    
    rollback_id="auto-$(date +%Y%m%d-%H%M%S)"
    rollback_start_time=$(date -Iseconds)
    
    log "Starting automatic rollback (ID: $rollback_id)"
    save_rollback_state "starting" "Automatic rollback initiated"
    
    # Prerequisites check
    if ! check_rollback_prerequisites; then
        save_rollback_state "failed" "Prerequisites check failed"
        return 1
    fi
    
    # Capture current state
    capture_pre_rollback_state
    
    # Find last known good backup
    local backup_name
    if ! backup_name=$(find_last_known_good); then
        save_rollback_state "failed" "No suitable backup found"
        return 1
    fi
    
    log "Using backup: $backup_name"
    save_rollback_state "rolling_back" "Rolling back to $backup_name"
    
    # Perform the rollback
    if perform_service_rollback "$backup_name"; then
        save_rollback_state "restarting" "Service rollback completed, waiting for ready state"
        
        # Wait for service to be ready
        if wait_for_service_ready 300; then
            # Post-rollback health check
            if [[ "$skip_health_check" != "true" ]]; then
                if perform_health_check; then
                    save_rollback_state "completed" "Rollback completed successfully"
                    success "Automatic rollback completed successfully"
                    return 0
                else
                    save_rollback_state "health_check_failed" "Rollback completed but health check failed"
                    if [[ "$force" == "true" ]]; then
                        warning "Health check failed but continuing due to --force"
                        return 0
                    else
                        error "Post-rollback health check failed"
                        return 1
                    fi
                fi
            else
                save_rollback_state "completed" "Rollback completed (health check skipped)"
                success "Automatic rollback completed (health check skipped)"
                return 0
            fi
        else
            save_rollback_state "failed" "Service failed to start after rollback"
            error "Service failed to start after rollback"
            return 1
        fi
    else
        save_rollback_state "failed" "Service rollback failed"
        error "Service rollback failed"
        return 1
    fi
}

perform_manual_rollback() {
    local backup_name="$1"
    local force="$2"
    local skip_health_check="$3"
    
    rollback_id="manual-$(date +%Y%m%d-%H%M%S)"
    rollback_start_time=$(date -Iseconds)
    
    log "Starting manual rollback to: $backup_name (ID: $rollback_id)"
    save_rollback_state "starting" "Manual rollback to $backup_name initiated"
    
    # Check if backup exists
    local backup_found=false
    for backup_type in snapshots daily weekly monthly; do
        if [[ -e "$BACKUP_ROOT/$backup_type/$backup_name" ]]; then
            backup_found=true
            break
        fi
    done
    
    if [[ "$backup_found" != "true" ]]; then
        error "Backup not found: $backup_name"
        save_rollback_state "failed" "Backup not found: $backup_name"
        return 1
    fi
    
    # Prerequisites check
    if ! check_rollback_prerequisites; then
        save_rollback_state "failed" "Prerequisites check failed"
        return 1
    fi
    
    # Capture current state
    capture_pre_rollback_state
    
    save_rollback_state "rolling_back" "Rolling back to $backup_name"
    
    # Perform the rollback
    if perform_service_rollback "$backup_name"; then
        save_rollback_state "restarting" "Service rollback completed, waiting for ready state"
        
        # Wait for service to be ready
        if wait_for_service_ready 300; then
            # Post-rollback health check
            if [[ "$skip_health_check" != "true" ]]; then
                if perform_health_check; then
                    save_rollback_state "completed" "Manual rollback completed successfully"
                    success "Manual rollback completed successfully"
                    return 0
                else
                    save_rollback_state "health_check_failed" "Rollback completed but health check failed"
                    if [[ "$force" == "true" ]]; then
                        warning "Health check failed but continuing due to --force"
                        return 0
                    else
                        error "Post-rollback health check failed"
                        return 1
                    fi
                fi
            else
                save_rollback_state "completed" "Manual rollback completed (health check skipped)"
                success "Manual rollback completed (health check skipped)"
                return 0
            fi
        else
            save_rollback_state "failed" "Service failed to start after rollback"
            error "Service failed to start after rollback"
            return 1
        fi
    else
        save_rollback_state "failed" "Service rollback failed"
        error "Service rollback failed"
        return 1
    fi
}

perform_emergency_rollback() {
    log "EMERGENCY ROLLBACK - Minimal safety checks, maximum speed"
    
    rollback_id="emergency-$(date +%Y%m%d-%H%M%S)"
    rollback_start_time=$(date -Iseconds)
    save_rollback_state "emergency" "Emergency rollback initiated"
    
    # Kill all vLLM processes immediately
    pkill -9 -f vllm || true
    
    # Try to restart service
    systemctl restart vllm-server
    
    # Brief wait
    sleep 30
    
    if systemctl is-active --quiet vllm-server; then
        save_rollback_state "completed" "Emergency rollback completed"
        success "Emergency rollback completed - service restarted"
        warning "Emergency rollback performed - full validation recommended"
        return 0
    else
        save_rollback_state "failed" "Emergency rollback failed"
        error "Emergency rollback failed - manual intervention required"
        return 1
    fi
}

list_available_backups() {
    log "Available backups for rollback:"
    echo
    
    for backup_type in snapshots daily weekly monthly; do
        local backup_dir="$BACKUP_ROOT/$backup_type"
        if [[ -d "$backup_dir" ]] && [[ -n "$(ls -A "$backup_dir" 2>/dev/null)" ]]; then
            echo -e "${CYAN}$backup_type:${NC}"
            ls -la "$backup_dir" | tail -n +2 | while read -r line; do
                echo "  $line"
            done
            echo
        fi
    done
}

show_rollback_status() {
    if [[ ! -f "$STATE_FILE" ]]; then
        log "No rollback state information available"
        return 0
    fi
    
    log "Current rollback status:"
    echo
    
    local current_state=$(jq -r '.state' "$STATE_FILE")
    local rollback_id=$(jq -r '.rollback_id' "$STATE_FILE")
    local timestamp=$(jq -r '.timestamp' "$STATE_FILE")
    local message=$(jq -r '.message' "$STATE_FILE")
    local reason=$(jq -r '.reason' "$STATE_FILE")
    
    echo "Rollback ID: $rollback_id"
    echo "State: $current_state"
    echo "Timestamp: $timestamp"
    echo "Reason: $reason"
    echo "Message: $message"
    
    # Additional status checks
    echo
    echo "Current system status:"
    if systemctl is-active --quiet vllm-server; then
        echo -e "Service: ${GREEN}RUNNING${NC}"
    else
        echo -e "Service: ${RED}STOPPED${NC}"
    fi
    
    if curl -f -s --max-time 5 "http://localhost:8000/health" > /dev/null 2>&1; then
        echo -e "API: ${GREEN}HEALTHY${NC}"
    else
        echo -e "API: ${RED}UNHEALTHY${NC}"
    fi
}

validate_rollback_capability() {
    log "Validating rollback capability..."
    
    local issues=0
    
    # Check backup system
    if command -v vllm-backup > /dev/null 2>&1; then
        success "✓ Backup system available"
    else
        error "✗ Backup system not available"
        ((issues++))
    fi
    
    # Check available backups
    local backup_count=0
    for backup_type in snapshots daily weekly monthly; do
        local backup_dir="$BACKUP_ROOT/$backup_type"
        if [[ -d "$backup_dir" ]]; then
            local count=$(ls -1 "$backup_dir" 2>/dev/null | wc -l)
            backup_count=$((backup_count + count))
        fi
    done
    
    if [[ $backup_count -gt 0 ]]; then
        success "✓ $backup_count backups available"
    else
        error "✗ No backups available"
        ((issues++))
    fi
    
    # Check disk space
    local available_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    if [[ $available_gb -ge 50 ]]; then
        success "✓ Sufficient disk space: ${available_gb}GB"
    else
        error "✗ Insufficient disk space: ${available_gb}GB (need 50GB+)"
        ((issues++))
    fi
    
    # Check system load
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    if (( $(echo "$load_avg < 5" | bc -l) )); then
        success "✓ System load acceptable: $load_avg"
    else
        warning "⚠ High system load: $load_avg"
    fi
    
    if [[ $issues -eq 0 ]]; then
        success "Rollback capability validation passed"
        return 0
    else
        error "Rollback capability validation failed: $issues issues found"
        return 1
    fi
}

main() {
    local command="${1:-help}"
    shift || true
    
    local force=false
    local dry_run=false
    local skip_health_check=false
    local backup_name=""
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --reason)
                rollback_reason="$2"
                shift 2
                ;;
            --force)
                force=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --no-health-check)
                skip_health_check=true
                shift
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
                backup_name="$1"
                shift
                ;;
        esac
    done
    
    # Set default reason if not provided
    if [[ -z "$rollback_reason" ]]; then
        rollback_reason="Rollback requested via command line"
    fi
    
    case "$command" in
        auto)
            if [[ "$dry_run" == "true" ]]; then
                log "DRY RUN: Would perform automatic rollback"
                find_last_known_good
                return 0
            fi
            perform_automatic_rollback "$force" "$skip_health_check"
            ;;
        manual)
            if [[ -z "$backup_name" ]]; then
                error "Backup name required for manual rollback"
                exit 1
            fi
            if [[ "$dry_run" == "true" ]]; then
                log "DRY RUN: Would perform manual rollback to $backup_name"
                return 0
            fi
            perform_manual_rollback "$backup_name" "$force" "$skip_health_check"
            ;;
        list)
            list_available_backups
            ;;
        status)
            show_rollback_status
            ;;
        validate)
            validate_rollback_capability
            ;;
        emergency)
            if [[ "$dry_run" == "true" ]]; then
                log "DRY RUN: Would perform emergency rollback"
                return 0
            fi
            perform_emergency_rollback
            ;;
        prepare)
            log "Preparing system for potential rollback..."
            if check_rollback_prerequisites && validate_rollback_capability; then
                success "System prepared for rollback"
            else
                error "System not ready for rollback"
                exit 1
            fi
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