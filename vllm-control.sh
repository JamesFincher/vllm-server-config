#!/bin/bash
# vLLM Master Control Script
# Unified interface for all vLLM deployment, monitoring, backup, and recovery operations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

show_banner() {
    echo -e "${PURPLE}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                      vLLM Control Center                        ║
║                 Unified Management Interface                     ║
║                                                                  ║
║  🚀 Deploy    📊 Monitor    💾 Backup    🔄 Recover             ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

show_help() {
    show_banner
    cat << EOF

USAGE:
    $0 <category> <command> [options]

CATEGORIES & COMMANDS:

  ${CYAN}🚀 DEPLOYMENT${NC}
    deploy full                    Complete one-command deployment
    deploy quick                   Quick deployment with defaults
    deploy custom                  Interactive deployment configuration
    deploy status                  Show deployment status

  ${CYAN}📊 MONITORING${NC}
    monitor start                  Start monitoring services
    monitor stop                   Stop monitoring services
    monitor status                 Show monitoring status
    monitor dashboard              Open monitoring dashboard
    monitor check                  Run single health check

  ${CYAN}💾 BACKUP${NC}
    backup create [type]           Create backup (daily|weekly|monthly|snapshot)
    backup list                    List available backups
    backup status                  Show backup system status
    backup restore <name>          Restore from backup
    backup cleanup                 Clean old backups

  ${CYAN}🔄 RECOVERY${NC}
    recovery monitor               Start automatic error recovery
    recovery diagnose              Diagnose current issues
    recovery rollback [target]     Rollback to previous state
    recovery emergency             Emergency recovery mode
    recovery test                  Test recovery mechanisms

  ${CYAN}🔧 MAINTENANCE${NC}
    maintenance validate           Validate entire system
    maintenance logs               Show recent logs
    maintenance cleanup            System cleanup
    maintenance update             Update system components

  ${CYAN}ℹ️  INFORMATION${NC}
    info system                    Show system information
    info performance               Show performance metrics
    info config                    Show configuration
    info services                  Show all service statuses

GLOBAL OPTIONS:
    --help                         Show this help
    --version                      Show version information
    --verbose                      Enable verbose output
    --dry-run                      Show what would be done

EXAMPLES:
    $0 deploy full --api-key "your-key"
    $0 monitor dashboard
    $0 backup create snapshot
    $0 recovery rollback
    $0 info system

QUICK COMMANDS:
    $0 status                      Overall system status
    $0 restart                     Restart all services  
    $0 emergency                   Emergency recovery

EOF
}

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

check_prerequisites() {
    # Check if running as root for system operations
    if [[ $EUID -ne 0 ]] && [[ "$1" =~ ^(deploy|backup|recovery) ]]; then
        error "System operations require root privileges. Use: sudo $0 $*"
        exit 1
    fi
    
    # Check if base directory exists
    if [[ ! -d "$SCRIPT_DIR" ]]; then
        error "Script directory not found: $SCRIPT_DIR"
        exit 1
    fi
}

handle_deployment() {
    local subcommand="$1"
    shift || true
    
    case "$subcommand" in
        full)
            log "Starting full deployment..."
            "$SCRIPT_DIR/deploy.sh" "$@"
            ;;
        quick)
            log "Starting quick deployment..."
            "$SCRIPT_DIR/deploy.sh" --mode development "$@"
            ;;
        custom)
            log "Starting interactive deployment..."
            echo "Custom deployment configuration:"
            read -p "API Key: " api_key
            read -p "Context Length (default 700000): " context_length
            context_length=${context_length:-700000}
            read -p "Deployment Mode (production/development/testing): " mode
            mode=${mode:-production}
            
            "$SCRIPT_DIR/deploy.sh" --api-key "$api_key" --context-length "$context_length" --mode "$mode" "$@"
            ;;
        status)
            if systemctl is-active --quiet vllm-server 2>/dev/null; then
                success "Deployment: ACTIVE"
            else
                error "Deployment: INACTIVE"
            fi
            ;;
        *)
            error "Unknown deployment command: $subcommand"
            echo "Available: full, quick, custom, status"
            exit 1
            ;;
    esac
}

handle_monitoring() {
    local subcommand="$1"
    shift || true
    
    case "$subcommand" in
        start)
            if command -v vllm-monitor > /dev/null 2>&1; then
                vllm-monitor start
            else
                log "Starting monitoring services..."
                systemctl start vllm-health-monitor 2>/dev/null || warning "Health monitor service not found"
                systemctl start vllm-dashboard 2>/dev/null || warning "Dashboard service not found"
            fi
            ;;
        stop)
            if command -v vllm-monitor > /dev/null 2>&1; then
                vllm-monitor stop
            else
                log "Stopping monitoring services..."
                systemctl stop vllm-health-monitor 2>/dev/null || true
                systemctl stop vllm-dashboard 2>/dev/null || true
            fi
            ;;
        status)
            if command -v vllm-monitor > /dev/null 2>&1; then
                vllm-monitor status
            else
                echo "Health Monitor:" $(systemctl is-active vllm-health-monitor 2>/dev/null || echo "not installed")
                echo "Dashboard:" $(systemctl is-active vllm-dashboard 2>/dev/null || echo "not installed")
            fi
            ;;
        dashboard)
            if command -v vllm-monitor > /dev/null 2>&1; then
                vllm-monitor dashboard
            else
                echo "Monitoring dashboard should be available at: http://localhost:3000"
            fi
            ;;
        check)
            if command -v vllm-monitor > /dev/null 2>&1; then
                vllm-monitor check
            elif [[ -f "$SCRIPT_DIR/automation/monitoring/health-monitor.py" ]]; then
                python3 "$SCRIPT_DIR/automation/monitoring/health-monitor.py" --check-once
            else
                # Basic health check
                if curl -f -s --max-time 10 "http://localhost:8000/health" > /dev/null; then
                    success "API health check passed"
                else
                    error "API health check failed"
                fi
            fi
            ;;
        *)
            error "Unknown monitoring command: $subcommand"
            echo "Available: start, stop, status, dashboard, check"
            exit 1
            ;;
    esac
}

handle_backup() {
    local subcommand="$1"
    shift || true
    
    case "$subcommand" in
        create)
            local backup_type="${1:-daily}"
            if command -v vllm-backup > /dev/null 2>&1; then
                vllm-backup create "$backup_type"
            else
                error "Backup system not installed"
                exit 1
            fi
            ;;
        list)
            if command -v vllm-backup > /dev/null 2>&1; then
                vllm-backup list
            else
                error "Backup system not installed"
                exit 1
            fi
            ;;
        status)
            if command -v vllm-backup > /dev/null 2>&1; then
                vllm-backup status
            else
                error "Backup system not installed"
                exit 1
            fi
            ;;
        restore)
            local backup_name="$1"
            if [[ -z "$backup_name" ]]; then
                error "Backup name required for restore"
                exit 1
            fi
            if command -v vllm-backup > /dev/null 2>&1; then
                vllm-backup restore "$backup_name" "$@"
            else
                error "Backup system not installed"
                exit 1
            fi
            ;;
        cleanup)
            if command -v vllm-backup > /dev/null 2>&1; then
                vllm-backup cleanup
            else
                error "Backup system not installed"
                exit 1
            fi
            ;;
        *)
            error "Unknown backup command: $subcommand"
            echo "Available: create, list, status, restore, cleanup"
            exit 1
            ;;
    esac
}

handle_recovery() {
    local subcommand="$1"
    shift || true
    
    case "$subcommand" in
        monitor)
            if [[ -f "$SCRIPT_DIR/automation/error-recovery.sh" ]]; then
                "$SCRIPT_DIR/automation/error-recovery.sh" monitor
            else
                error "Error recovery system not found"
                exit 1
            fi
            ;;
        diagnose)
            if [[ -f "$SCRIPT_DIR/automation/error-recovery.sh" ]]; then
                "$SCRIPT_DIR/automation/error-recovery.sh" diagnose
            else
                error "Error recovery system not found"
                exit 1
            fi
            ;;
        rollback)
            local target="$1"
            if [[ -f "$SCRIPT_DIR/automation/validation/rollback-manager.sh" ]]; then
                if [[ -n "$target" ]]; then
                    "$SCRIPT_DIR/automation/validation/rollback-manager.sh" manual "$target" "$@"
                else
                    "$SCRIPT_DIR/automation/validation/rollback-manager.sh" auto "$@"
                fi
            else
                error "Rollback system not found"
                exit 1
            fi
            ;;
        emergency)
            if [[ -f "$SCRIPT_DIR/automation/validation/rollback-manager.sh" ]]; then
                "$SCRIPT_DIR/automation/validation/rollback-manager.sh" emergency "$@"
            else
                error "Emergency recovery system not found"
                exit 1
            fi
            ;;
        test)
            if [[ -f "$SCRIPT_DIR/automation/error-recovery.sh" ]]; then
                "$SCRIPT_DIR/automation/error-recovery.sh" test-recovery
            else
                error "Error recovery system not found"
                exit 1
            fi
            ;;
        *)
            error "Unknown recovery command: $subcommand"
            echo "Available: monitor, diagnose, rollback, emergency, test"
            exit 1
            ;;
    esac
}

handle_maintenance() {
    local subcommand="$1"
    shift || true
    
    case "$subcommand" in
        validate)
            if [[ -f "$SCRIPT_DIR/automation/validation/validate-deployment.sh" ]]; then
                "$SCRIPT_DIR/automation/validation/validate-deployment.sh" "$@"
            else
                error "Validation system not found"
                exit 1
            fi
            ;;
        logs)
            log "Recent vLLM logs:"
            if [[ -d "/var/log/vllm" ]]; then
                find /var/log/vllm -name "*.log" -mtime -1 -exec tail -20 {} \; 2>/dev/null || echo "No recent logs found"
            else
                journalctl -u vllm-server --no-pager -n 20 2>/dev/null || echo "No service logs found"
            fi
            ;;
        cleanup)
            log "Performing system cleanup..."
            # Clean old logs
            find /var/log/vllm -name "*.log" -mtime +7 -delete 2>/dev/null || true
            # Clean temporary files
            rm -rf /tmp/vllm-* 2>/dev/null || true
            # Clean old diagnostics
            find /opt/vllm-recovery -name "diagnostics-*" -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
            success "System cleanup completed"
            ;;
        update)
            log "Updating system components..."
            # This would contain update logic for the vLLM system
            warning "Update functionality not yet implemented"
            ;;
        *)
            error "Unknown maintenance command: $subcommand"
            echo "Available: validate, logs, cleanup, update"
            exit 1
            ;;
    esac
}

handle_info() {
    local subcommand="$1"
    shift || true
    
    case "$subcommand" in
        system)
            echo -e "${CYAN}System Information:${NC}"
            echo "Hostname: $(hostname)"
            echo "OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo 'Unknown')"
            echo "Kernel: $(uname -r)"
            echo "Uptime: $(uptime -p 2>/dev/null || uptime)"
            echo "Load: $(uptime | awk -F'load average:' '{print $2}')"
            echo
            echo -e "${CYAN}Hardware:${NC}"
            echo "CPU: $(nproc) cores"
            echo "Memory: $(free -h | awk '/^Mem:/ {print $2}')"
            echo "GPUs: $(nvidia-smi -L 2>/dev/null | wc -l || echo '0')"
            ;;
        performance)
            echo -e "${CYAN}Performance Metrics:${NC}"
            if curl -f -s --max-time 5 "http://localhost:8000/health" > /dev/null 2>&1; then
                echo "API Status: HEALTHY"
                # Test API response time
                local start_time=$(date +%s.%3N)
                curl -f -s --max-time 10 "http://localhost:8000/health" > /dev/null 2>&1
                local end_time=$(date +%s.%3N)
                local response_time=$(echo "$end_time - $start_time" | bc -l)
                echo "API Response Time: ${response_time}s"
            else
                echo "API Status: UNHEALTHY"
            fi
            
            if command -v nvidia-smi > /dev/null 2>&1; then
                echo
                echo "GPU Utilization:"
                nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits | \
                    awk -F, '{printf "GPU %s (%s): %s/%s MB (%.1f%%), %s%% util\n", $1, $2, $3, $4, ($3/$4)*100, $5}'
            fi
            ;;
        config)
            echo -e "${CYAN}Configuration:${NC}"
            if [[ -f "/etc/vllm/deployment.conf" ]]; then
                grep -v "API_KEY\|PASSWORD" /etc/vllm/deployment.conf 2>/dev/null || echo "No configuration found"
            else
                echo "No deployment configuration found"
            fi
            ;;
        services)
            echo -e "${CYAN}Service Status:${NC}"
            echo "vLLM Server: $(systemctl is-active vllm-server 2>/dev/null || echo 'not installed')"
            echo "Health Monitor: $(systemctl is-active vllm-health-monitor 2>/dev/null || echo 'not installed')"
            echo "Dashboard: $(systemctl is-active vllm-dashboard 2>/dev/null || echo 'not installed')"
            ;;
        *)
            error "Unknown info command: $subcommand"
            echo "Available: system, performance, config, services"
            exit 1
            ;;
    esac
}

handle_quick_commands() {
    local command="$1"
    shift || true
    
    case "$command" in
        status)
            echo -e "${CYAN}=== vLLM System Status ===${NC}"
            echo
            handle_info services
            echo
            handle_info performance
            ;;
        restart)
            log "Restarting all vLLM services..."
            systemctl restart vllm-server 2>/dev/null || warning "vLLM server not found"
            systemctl restart vllm-health-monitor 2>/dev/null || true
            systemctl restart vllm-dashboard 2>/dev/null || true
            success "Services restarted"
            ;;
        emergency)
            warning "Initiating emergency recovery..."
            handle_recovery emergency "$@"
            ;;
        *)
            return 1  # Not a quick command
            ;;
    esac
    
    return 0  # Was handled as quick command
}

main() {
    # Handle quick commands first
    if [[ $# -gt 0 ]] && handle_quick_commands "$1" "${@:2}"; then
        return 0
    fi
    
    # Parse global options
    local verbose=false
    local dry_run=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --version)
                echo "vLLM Control Center v2.0"
                exit 0
                ;;
            --verbose)
                verbose=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -*)
                error "Unknown global option: $1"
                exit 1
                ;;
            *)
                break
                ;;
        esac
    done
    
    # Check for command
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi
    
    local category="$1"
    shift
    
    # Check for subcommand
    if [[ $# -eq 0 ]]; then
        error "Subcommand required for category: $category"
        exit 1
    fi
    
    local subcommand="$1"
    shift
    
    # Add dry-run and verbose flags to remaining args if set
    local extra_args=()
    if [[ "$dry_run" == "true" ]]; then
        extra_args+=("--dry-run")
    fi
    if [[ "$verbose" == "true" ]]; then
        extra_args+=("--verbose")
    fi
    
    # Check prerequisites for system operations
    check_prerequisites "$category"
    
    # Route to appropriate handler
    case "$category" in
        deploy)
            handle_deployment "$subcommand" "${extra_args[@]}" "$@"
            ;;
        monitor)
            handle_monitoring "$subcommand" "${extra_args[@]}" "$@"
            ;;
        backup)
            handle_backup "$subcommand" "${extra_args[@]}" "$@"
            ;;
        recovery)
            handle_recovery "$subcommand" "${extra_args[@]}" "$@"
            ;;
        maintenance)
            handle_maintenance "$subcommand" "${extra_args[@]}" "$@"
            ;;
        info)
            handle_info "$subcommand" "${extra_args[@]}" "$@"
            ;;
        *)
            error "Unknown category: $category"
            echo
            echo "Available categories: deploy, monitor, backup, recovery, maintenance, info"
            echo "Use --help for detailed information"
            exit 1
            ;;
    esac
}

main "$@"