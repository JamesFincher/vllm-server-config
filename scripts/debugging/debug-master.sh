#!/bin/bash
# Master Debugging and Troubleshooting Script for vLLM Infrastructure
# Orchestrates all debugging tools and provides a unified interface
#
# Usage: ./debug-master.sh [OPTIONS] [COMMAND]
# Options:
#   --quick           Run quick health check and show summary
#   --full            Run comprehensive diagnostics across all systems
#   --monitor         Start real-time monitoring dashboard
#   --fix             Automatically attempt to fix detected issues
#   --json            Output all results in JSON format
#   --verbose         Show detailed output from all tools
#   --help            Show this help message
#
# Commands:
#   health            Run system health checks
#   logs              Analyze vLLM server logs
#   network           Test network connectivity
#   gpu               Monitor GPU resources
#   recover           Run recovery tools
#   status            Show current system status

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEALTH_CHECK_SCRIPT="$SCRIPT_DIR/health-check.sh"
LOG_ANALYZER_SCRIPT="$SCRIPT_DIR/log-analyzer.sh"
NETWORK_DIAG_SCRIPT="$SCRIPT_DIR/network-diagnostics.sh"
GPU_MONITOR_SCRIPT="$SCRIPT_DIR/gpu-monitor.sh"
RECOVERY_SCRIPT="$SCRIPT_DIR/recovery-tools.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Flags
QUICK=false
FULL=false
MONITOR=false
FIX=false
JSON_OUTPUT=false
VERBOSE=false
COMMAND=""

show_help() {
    cat << EOF
Master Debugging and Troubleshooting Script for vLLM Infrastructure

Usage: $0 [OPTIONS] [COMMAND]

OPTIONS:
  --quick           Run quick health check and show summary
  --full            Run comprehensive diagnostics across all systems
  --monitor         Start real-time monitoring dashboard
  --fix             Automatically attempt to fix detected issues
  --json            Output all results in JSON format
  --verbose         Show detailed output from all tools
  --help            Show this help message

COMMANDS:
  health            Run system health checks
  logs              Analyze vLLM server logs
  network           Test network connectivity  
  gpu               Monitor GPU resources
  recover           Run recovery tools
  status            Show current system status

QUICK DIAGNOSTICS:
  $0 --quick        # Fast system overview
  $0 status         # Current status summary
  $0 health         # Comprehensive health check

MONITORING:
  $0 --monitor      # Real-time dashboard
  $0 gpu --realtime # GPU monitoring
  $0 logs --follow  # Live log monitoring

TROUBLESHOOTING:
  $0 --full         # Complete diagnostic sweep
  $0 --fix          # Auto-fix detected issues
  $0 recover        # Manual recovery tools

ANALYSIS:
  $0 logs --errors-only     # Show only errors
  $0 logs --performance     # Performance metrics
  $0 network --verbose      # Detailed network tests
  $0 gpu --history          # GPU usage history

EXAMPLES:
  # Quick health check
  $0 --quick
  
  # Full diagnostic with auto-fix
  $0 --full --fix
  
  # Real-time monitoring
  $0 --monitor
  
  # Analyze recent errors
  $0 logs --errors-only --recent
  
  # Test network and fix issues
  $0 network --fix-issues
  
  # Monitor GPU in real-time
  $0 gpu --realtime

TOOL DESCRIPTIONS:
  Health Check:     Comprehensive system component validation
  Log Analyzer:     Parse and analyze vLLM server logs
  Network Diag:     SSH tunnel and API connectivity testing
  GPU Monitor:      Real-time GPU resource tracking
  Recovery Tools:   Automated failure recovery and repair
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --quick)
            QUICK=true
            shift
            ;;
        --full)
            FULL=true
            shift
            ;;
        --monitor)
            MONITOR=true
            shift
            ;;
        --fix)
            FIX=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        health|logs|network|gpu|recover|status)
            COMMAND="$1"
            shift
            break  # Allow remaining args to pass through to the specific tool
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Utility functions
log() {
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "$1"
    fi
}

run_tool() {
    local tool_script="$1"
    local tool_args="$2"
    local tool_name="$3"
    
    if [[ ! -f "$tool_script" ]]; then
        log "${RED}Error: $tool_name script not found: $tool_script${NC}"
        return 1
    fi
    
    if [[ ! -x "$tool_script" ]]; then
        chmod +x "$tool_script"
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        log "${CYAN}Running: $tool_script $tool_args${NC}"
    fi
    
    "$tool_script" $tool_args
}

show_banner() {
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        log "${CYAN}${BOLD}"
        log "╔════════════════════════════════════════════════════════════════╗"
        log "║                vLLM Infrastructure Debugging Suite            ║"
        log "║                      $(date '+%Y-%m-%d %H:%M:%S')                      ║"
        log "╚════════════════════════════════════════════════════════════════╝"
        log "${NC}"
    fi
}

run_quick_check() {
    show_banner
    log "${YELLOW}Running quick system check...${NC}"
    log ""
    
    # Build arguments
    local args=""
    [[ "$JSON_OUTPUT" == "true" ]] && args+=" --json"
    [[ "$VERBOSE" == "true" ]] && args+=" --verbose"
    [[ "$FIX" == "true" ]] && args+=" --fix-issues"
    
    # Quick health check
    run_tool "$HEALTH_CHECK_SCRIPT" "$args" "Health Check"
    
    local health_exit_code=$?
    
    if [[ "$health_exit_code" -eq 0 ]]; then
        log ""
        log "${GREEN}✅ Quick check completed - System appears healthy${NC}"
    elif [[ "$health_exit_code" -eq 2 ]]; then
        log ""
        log "${YELLOW}⚠️  Quick check completed with warnings${NC}"
        log "Run '$0 --full' for detailed analysis"
    else
        log ""
        log "${RED}❌ Quick check failed - Issues detected${NC}"
        log "Run '$0 --full --fix' to diagnose and repair"
    fi
    
    return $health_exit_code
}

run_full_diagnostics() {
    show_banner
    log "${YELLOW}Running comprehensive system diagnostics...${NC}"
    log ""
    
    local overall_status=0
    local args=""
    [[ "$JSON_OUTPUT" == "true" ]] && args+=" --json"
    [[ "$VERBOSE" == "true" ]] && args+=" --verbose"
    [[ "$FIX" == "true" ]] && args+=" --fix-issues --auto-fix"
    
    # 1. System Health Check
    log "${BOLD}${BLUE}1. System Health Check${NC}"
    run_tool "$HEALTH_CHECK_SCRIPT" "$args" "Health Check"
    local health_status=$?
    [[ "$health_status" -gt "$overall_status" ]] && overall_status=$health_status
    log ""
    
    # 2. Network Diagnostics
    log "${BOLD}${BLUE}2. Network Connectivity${NC}"
    run_tool "$NETWORK_DIAG_SCRIPT" "$args" "Network Diagnostics"
    local network_status=$?
    [[ "$network_status" -gt "$overall_status" ]] && overall_status=$network_status
    log ""
    
    # 3. GPU Status
    log "${BOLD}${BLUE}3. GPU Monitoring${NC}"
    local gpu_args="--summary"
    [[ "$JSON_OUTPUT" == "true" ]] && gpu_args+=" --json"
    run_tool "$GPU_MONITOR_SCRIPT" "$gpu_args" "GPU Monitor"
    local gpu_status=$?
    [[ "$gpu_status" -gt "$overall_status" ]] && overall_status=$gpu_status
    log ""
    
    # 4. Log Analysis
    log "${BOLD}${BLUE}4. Log Analysis${NC}"
    local log_args="--summary --recent"
    [[ "$JSON_OUTPUT" == "true" ]] && log_args+=" --json"
    run_tool "$LOG_ANALYZER_SCRIPT" "$log_args" "Log Analyzer"
    local log_status=$?
    [[ "$log_status" -gt "$overall_status" ]] && overall_status=$log_status
    log ""
    
    # 5. Recovery Check (if fixing is enabled)
    if [[ "$FIX" == "true" ]]; then
        log "${BOLD}${BLUE}5. Recovery Tools${NC}"
        local recovery_args="--check-all --auto-fix"
        [[ "$JSON_OUTPUT" == "true" ]] && recovery_args+=" --json"
        run_tool "$RECOVERY_SCRIPT" "$recovery_args" "Recovery Tools"
        local recovery_status=$?
        [[ "$recovery_status" -gt "$overall_status" ]] && overall_status=$recovery_status
        log ""
    fi
    
    # Summary
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        log "${BOLD}${CYAN}=== Comprehensive Diagnostics Summary ===${NC}"
        case $overall_status in
            0)
                log "${GREEN}🎉 All systems operational - No issues detected${NC}"
                ;;
            2)
                log "${YELLOW}⚠️  System operational with warnings${NC}"
                log "Monitor for potential issues"
                ;;
            *)
                log "${RED}❌ Issues detected requiring attention${NC}"
                log "Review the diagnostic output above for details"
                ;;
        esac
    fi
    
    return $overall_status
}

start_monitoring() {
    show_banner
    log "${CYAN}Starting real-time monitoring dashboard...${NC}"
    log "${CYAN}This will open multiple monitoring sessions${NC}"
    log "${CYAN}Press Ctrl+C in each window to stop monitoring${NC}"
    log ""
    
    # Start monitoring in different terminal windows/tabs if possible
    # For now, we'll run them sequentially with user choice
    
    log "${YELLOW}Available monitoring options:${NC}"
    log "1. Real-time GPU monitoring"
    log "2. Live log monitoring"
    log "3. Network connectivity monitoring"
    log "4. All monitoring (requires multiple terminals)"
    log ""
    
    if [[ -t 0 ]]; then  # Check if we have an interactive terminal
        read -p "Select option (1-4): " choice
        
        case $choice in
            1)
                run_tool "$GPU_MONITOR_SCRIPT" "--realtime" "GPU Monitor"
                ;;
            2)
                run_tool "$LOG_ANALYZER_SCRIPT" "--follow" "Log Analyzer"
                ;;
            3)
                run_tool "$NETWORK_DIAG_SCRIPT" "--continuous" "Network Diagnostics"
                ;;
            4)
                log "${YELLOW}Starting comprehensive monitoring...${NC}"
                log "Open additional terminals and run:"
                log "  Terminal 1: $GPU_MONITOR_SCRIPT --realtime"
                log "  Terminal 2: $LOG_ANALYZER_SCRIPT --follow"
                log "  Terminal 3: $NETWORK_DIAG_SCRIPT --continuous"
                log ""
                log "Starting GPU monitoring in this terminal..."
                run_tool "$GPU_MONITOR_SCRIPT" "--realtime" "GPU Monitor"
                ;;
            *)
                log "${RED}Invalid option${NC}"
                exit 1
                ;;
        esac
    else
        # Non-interactive, default to GPU monitoring
        run_tool "$GPU_MONITOR_SCRIPT" "--realtime" "GPU Monitor"
    fi
}

show_status() {
    show_banner
    log "${YELLOW}Current System Status${NC}"
    log ""
    
    # Quick status from each component
    local args="--summary"
    [[ "$JSON_OUTPUT" == "true" ]] && args+=" --json"
    [[ "$VERBOSE" == "true" ]] && args+=" --verbose"
    
    # Health status
    run_tool "$HEALTH_CHECK_SCRIPT" "$args" "Health Check"
    log ""
    
    # GPU status
    run_tool "$GPU_MONITOR_SCRIPT" "--summary" "GPU Status"
    log ""
    
    # Network status
    run_tool "$NETWORK_DIAG_SCRIPT" "--tunnel-only --api-only" "Network Status"
}

run_specific_command() {
    local cmd="$1"
    shift  # Remove command from args, pass rest to tool
    
    case "$cmd" in
        "health")
            local args="$*"
            [[ "$JSON_OUTPUT" == "true" ]] && args+=" --json"
            [[ "$VERBOSE" == "true" ]] && args+=" --verbose"
            [[ "$FIX" == "true" ]] && args+=" --fix-issues"
            run_tool "$HEALTH_CHECK_SCRIPT" "$args" "Health Check"
            ;;
        "logs")
            local args="$*"
            [[ "$JSON_OUTPUT" == "true" ]] && args+=" --json"
            run_tool "$LOG_ANALYZER_SCRIPT" "$args" "Log Analyzer"
            ;;
        "network")
            local args="$*"
            [[ "$JSON_OUTPUT" == "true" ]] && args+=" --json"
            [[ "$VERBOSE" == "true" ]] && args+=" --verbose"
            [[ "$FIX" == "true" ]] && args+=" --fix-issues"
            run_tool "$NETWORK_DIAG_SCRIPT" "$args" "Network Diagnostics"
            ;;
        "gpu")
            local args="$*"
            [[ "$JSON_OUTPUT" == "true" ]] && args+=" --json"
            run_tool "$GPU_MONITOR_SCRIPT" "$args" "GPU Monitor"
            ;;
        "recover")
            local args="$*"
            [[ "$JSON_OUTPUT" == "true" ]] && args+=" --json"
            [[ "$VERBOSE" == "true" ]] && args+=" --verbose"
            [[ "$FIX" == "true" ]] && args+=" --auto-fix"
            run_tool "$RECOVERY_SCRIPT" "$args" "Recovery Tools"
            ;;
        "status")
            show_status
            ;;
        *)
            log "${RED}Unknown command: $cmd${NC}"
            show_help
            exit 1
            ;;
    esac
}

# Main execution
main() {
    # Make sure all scripts are executable
    for script in "$HEALTH_CHECK_SCRIPT" "$LOG_ANALYZER_SCRIPT" "$NETWORK_DIAG_SCRIPT" "$GPU_MONITOR_SCRIPT" "$RECOVERY_SCRIPT"; do
        [[ -f "$script" && ! -x "$script" ]] && chmod +x "$script"
    done
    
    # Execute based on flags and commands
    if [[ -n "$COMMAND" ]]; then
        run_specific_command "$COMMAND" "$@"
    elif [[ "$QUICK" == "true" ]]; then
        run_quick_check
    elif [[ "$FULL" == "true" ]]; then
        run_full_diagnostics
    elif [[ "$MONITOR" == "true" ]]; then
        start_monitoring
    else
        # Default behavior - show status
        show_status
    fi
}

# Run main function
main "$@"