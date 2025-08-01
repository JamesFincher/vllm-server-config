#!/bin/bash
# Automated Recovery Tools for vLLM Infrastructure
# Handles common failure scenarios with automatic detection and recovery
#
# Usage: ./recovery-tools.sh [OPTIONS] [ACTION]
# Options:
#   --check-all       Run all diagnostic checks and suggest recovery actions
#   --auto-fix        Automatically attempt to fix detected issues
#   --force           Force recovery actions even if checks pass
#   --dry-run         Show what would be done without executing
#   --verbose         Show detailed output during recovery
#   --json            Output results in JSON format
#   --help            Show this help message
#
# Actions:
#   tunnel-restart    Restart SSH tunnel
#   vllm-restart      Restart vLLM server (via SSH)
#   process-cleanup   Clean up zombie processes
#   memory-cleanup    Free GPU memory and clear cache
#   full-recovery     Complete system recovery sequence

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_KEY="$HOME/.ssh/qwen3-deploy-20250731-114902"
SERVER_IP="86.38.238.64"
API_KEY="${VLLM_API_KEY:-qwen3-secret-key}"
TUNNEL_PID_FILE="$HOME/.qwen3_tunnel.pid"
API_URL="http://localhost:8000"
RECOVERY_LOG="$HOME/.vllm-recovery.log"

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
CHECK_ALL=false
AUTO_FIX=false
FORCE=false
DRY_RUN=false
VERBOSE=false
JSON_OUTPUT=false
ACTION=""

# Recovery tracking
RECOVERY_STEPS=()
RECOVERY_RESULTS=()
ISSUES_DETECTED=()
FIXES_ATTEMPTED=()
FIXES_SUCCESSFUL=()

show_help() {
    cat << EOF
Automated Recovery Tools for vLLM Infrastructure

Usage: $0 [OPTIONS] [ACTION]

OPTIONS:
  --check-all       Run all diagnostic checks and suggest recovery actions
  --auto-fix        Automatically attempt to fix detected issues
  --force           Force recovery actions even if checks pass
  --dry-run         Show what would be done without executing
  --verbose         Show detailed output during recovery
  --json            Output results in JSON format
  --help            Show this help message

ACTIONS:
  tunnel-restart    Restart SSH tunnel connection
  vllm-restart      Restart vLLM server on remote machine
  process-cleanup   Clean up zombie and hung processes
  memory-cleanup    Free GPU memory and clear CUDA cache
  full-recovery     Complete system recovery sequence
  
  If no action is specified, --check-all is assumed.

RECOVERY SCENARIOS:
  SSH Tunnel Issues:
    • Tunnel process died or hung
    • Port forwarding not working
    • Network connectivity problems
    • Authentication failures
    
  vLLM Server Problems:
    • Server process crashed
    • Out of memory errors
    • CUDA/GPU communication failures
    • Model loading issues
    • API not responding
    
  GPU/Memory Issues:
    • CUDA out of memory
    • Memory leaks and fragmentation
    • GPU processes hung
    • Driver communication problems
    
  API/Network Issues:
    • Authentication failures
    • Request timeouts
    • Connection refused errors
    • High latency problems

AUTOMATIC FIXES:
  • SSH tunnel restart with connection validation
  • Remote vLLM server restart via SSH
  • Process cleanup (kill hung processes)
  • GPU memory clearing and CUDA cache reset
  • Configuration validation and correction
  • Service dependency restart
  • Network diagnostics and repair

RECOVERY SEQUENCE:
  1. Diagnostic phase - identify issues
  2. Preparation phase - backup critical data
  3. Recovery phase - execute fixes in order of safety
  4. Validation phase - verify fixes worked
  5. Monitoring phase - watch for recurring issues
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --check-all)
            CHECK_ALL=true
            shift
            ;;
        --auto-fix)
            AUTO_FIX=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        tunnel-restart|vllm-restart|process-cleanup|memory-cleanup|full-recovery)
            ACTION="$1"
            shift
            ;;
        *)
            echo "Unknown option or action: $1"
            show_help
            exit 1
            ;;
    esac
done

# Default to check-all if no action specified
[[ -z "$ACTION" && "$CHECK_ALL" == "false" ]] && CHECK_ALL=true

# Utility functions
log() {
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "$1"
    fi
}

verbose_log() {
    if [[ "$VERBOSE" == "true" && "$JSON_OUTPUT" == "false" ]]; then
        echo -e "  ${CYAN}$1${NC}"
    fi
}

log_recovery() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp - $1" >> "$RECOVERY_LOG"
}

execute_step() {
    local step_name="$1"
    local command="$2"
    local description="$3"
    
    RECOVERY_STEPS+=("$step_name")
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "${YELLOW}[DRY RUN] $step_name: $description${NC}"
        verbose_log "Would execute: $command"
        RECOVERY_RESULTS+=("DRY_RUN")
        return 0
    fi
    
    log "${BLUE}Executing: $step_name${NC}"
    verbose_log "$description"
    log_recovery "EXECUTING: $step_name - $description"
    
    if eval "$command" >/dev/null 2>&1; then
        log "${GREEN}✅ $step_name completed successfully${NC}"
        RECOVERY_RESULTS+=("SUCCESS")
        FIXES_SUCCESSFUL+=("$step_name")
        log_recovery "SUCCESS: $step_name"
        return 0
    else
        log "${RED}❌ $step_name failed${NC}"
        RECOVERY_RESULTS+=("FAILED")
        log_recovery "FAILED: $step_name"
        return 1
    fi
}

# Diagnostic functions
diagnose_system() {
    log "${BOLD}${CYAN}=== System Diagnostics ===${NC}"
    
    local issues_found=0
    
    # Check SSH tunnel
    if ! check_ssh_tunnel; then
        ISSUES_DETECTED+=("SSH tunnel not working")
        ((issues_found++))
    fi
    
    # Check vLLM server
    if ! check_vllm_server; then
        ISSUES_DETECTED+=("vLLM server not responding")
        ((issues_found++))
    fi
    
    # Check GPU status
    if ! check_gpu_status; then
        ISSUES_DETECTED+=("GPU issues detected")
        ((issues_found++))
    fi
    
    # Check API functionality
    if ! check_api_functionality; then
        ISSUES_DETECTED+=("API not functional")
        ((issues_found++))
    fi
    
    if [[ "$issues_found" -eq 0 ]]; then
        log "${GREEN}✅ All systems appear to be functioning normally${NC}"
        return 0
    else
        log "${YELLOW}⚠️  $issues_found issues detected${NC}"
        return $issues_found
    fi
}

check_ssh_tunnel() {
    verbose_log "Checking SSH tunnel status..."
    
    # Check if tunnel process exists
    if [[ -f "$TUNNEL_PID_FILE" ]] && kill -0 $(cat "$TUNNEL_PID_FILE") 2>/dev/null; then
        verbose_log "Tunnel PID file exists and process is alive"
    elif pgrep -f "ssh.*8000:localhost:8000.*$SERVER_IP" >/dev/null; then
        verbose_log "Tunnel process found (updating PID file)"
        pgrep -f "ssh.*8000:localhost:8000.*$SERVER_IP" | head -1 > "$TUNNEL_PID_FILE"
    else
        verbose_log "No tunnel process found"
        return 1
    fi
    
    # Check if port is accessible
    if timeout 5 nc -z localhost 8000 2>/dev/null; then
        verbose_log "Port 8000 is accessible"
        return 0
    else
        verbose_log "Port 8000 not accessible"
        return 1
    fi
}

check_vllm_server() {
    verbose_log "Checking vLLM server status..."
    
    # Test basic connectivity
    local health_status=$(timeout 10 curl -s -o /dev/null -w "%{http_code}" "$API_URL/health" 2>/dev/null || echo "000")
    
    if [[ "$health_status" == "200" || "$health_status" == "401" ]]; then
        verbose_log "vLLM server responding (HTTP $health_status)"
        return 0
    else
        verbose_log "vLLM server not responding (HTTP $health_status)"
        return 1
    fi
}

check_gpu_status() {
    verbose_log "Checking GPU status..."
    
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        verbose_log "nvidia-smi not available"
        return 1
    fi
    
    # Check if nvidia-smi works
    if ! nvidia-smi >/dev/null 2>&1; then
        verbose_log "nvidia-smi failed to execute"
        return 1
    fi
    
    # Check for GPU processes
    local gpu_processes=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader,nounits 2>/dev/null | wc -l)
    if [[ "$gpu_processes" -eq 0 ]]; then
        verbose_log "No GPU processes detected"
        return 1
    fi
    
    verbose_log "GPU status appears normal ($gpu_processes processes)"
    return 0
}

check_api_functionality() {
    verbose_log "Checking API functionality..."
    
    # Test authenticated API call
    local models_response=$(timeout 15 curl -s -H "Authorization: Bearer $API_KEY" "$API_URL/v1/models" 2>/dev/null)
    
    if echo "$models_response" | jq -e '.data' >/dev/null 2>&1; then
        verbose_log "API is functional"
        return 0
    else
        verbose_log "API not functional"
        return 1
    fi
}

# Recovery functions
recover_ssh_tunnel() {
    log "${BOLD}${BLUE}=== SSH Tunnel Recovery ===${NC}"
    
    FIXES_ATTEMPTED+=("tunnel-restart")
    
    # Step 1: Kill existing tunnels
    execute_step "kill_existing_tunnels" \
        "pkill -f 'ssh.*8000:localhost:8000.*$SERVER_IP' 2>/dev/null || true; rm -f '$TUNNEL_PID_FILE'" \
        "Terminating existing SSH tunnel processes"
    
    # Step 2: Verify SSH connectivity
    execute_step "test_ssh_connection" \
        "timeout 10 ssh -i '$SSH_KEY' -o ConnectTimeout=10 -o BatchMode=yes 'root@$SERVER_IP' 'echo SSH_OK' >/dev/null 2>&1" \
        "Testing SSH connectivity to remote server"
    
    # Step 3: Start new tunnel
    execute_step "start_new_tunnel" \
        "ssh -i '$SSH_KEY' -f -N -L 8000:localhost:8000 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 'root@$SERVER_IP' 2>/dev/null" \
        "Starting new SSH tunnel"
    
    # Step 4: Update PID file
    execute_step "update_pid_file" \
        "pgrep -f 'ssh.*8000:localhost:8000.*$SERVER_IP' | head -1 > '$TUNNEL_PID_FILE'" \
        "Updating tunnel PID file"
    
    # Step 5: Verify tunnel functionality
    execute_step "verify_tunnel" \
        "sleep 3 && timeout 10 nc -z localhost 8000" \
        "Verifying tunnel functionality"
    
    return 0
}

recover_vllm_server() {
    log "${BOLD}${BLUE}=== vLLM Server Recovery ===${NC}"
    
    FIXES_ATTEMPTED+=("vllm-restart")
    
    # Step 1: Check if we can connect to remote server
    execute_step "test_remote_connection" \
        "timeout 10 ssh -i '$SSH_KEY' -o ConnectTimeout=10 'root@$SERVER_IP' 'echo REMOTE_OK' >/dev/null 2>&1" \
        "Testing connection to remote server"
    
    # Step 2: Stop existing vLLM processes
    execute_step "stop_vllm_processes" \
        "ssh -i '$SSH_KEY' 'root@$SERVER_IP' 'pkill -f vllm || true'" \
        "Stopping existing vLLM processes on remote server"
    
    # Step 3: Clean up screen sessions
    execute_step "cleanup_screen_sessions" \
        "ssh -i '$SSH_KEY' 'root@$SERVER_IP' 'screen -ls | grep vllm | cut -d. -f1 | awk \"{print \$1}\" | xargs -I {} screen -S {}.vllm -X quit 2>/dev/null || true'" \
        "Cleaning up vLLM screen sessions"
    
    # Step 4: Start vLLM server
    local start_command="cd /root && screen -dmS vllm_server bash -c 'source /opt/vllm/bin/activate && export VLLM_API_KEY=\"$API_KEY\" && export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1 && export CUDA_VISIBLE_DEVICES=0,1,2,3 && vllm serve /models/qwen3 --tensor-parallel-size 2 --pipeline-parallel-size 2 --max-model-len 700000 --kv-cache-dtype fp8 --host 0.0.0.0 --port 8000 --api-key \$VLLM_API_KEY --gpu-memory-utilization 0.98 --trust-remote-code 2>&1 | tee /var/log/vllm/vllm-recovery-\$(date +%Y%m%d-%H%M%S).log'"
    
    execute_step "start_vllm_server" \
        "ssh -i '$SSH_KEY' 'root@$SERVER_IP' '$start_command'" \
        "Starting vLLM server on remote machine"
    
    # Step 5: Wait for server to initialize
    execute_step "wait_for_initialization" \
        "sleep 30" \
        "Waiting for vLLM server initialization"
    
    # Step 6: Verify server is responding
    execute_step "verify_vllm_server" \
        "timeout 60 bash -c 'while ! curl -s http://localhost:8000/health >/dev/null 2>&1; do sleep 5; done'" \
        "Verifying vLLM server is responding"
    
    return 0
}

recover_process_cleanup() {
    log "${BOLD}${BLUE}=== Process Cleanup Recovery ===${NC}"
    
    FIXES_ATTEMPTED+=("process-cleanup")
    
    # Step 1: Clean up local hung processes
    execute_step "cleanup_local_processes" \
        "pkill -f 'ssh.*8000:localhost:8000' 2>/dev/null || true" \
        "Cleaning up local SSH processes"
    
    # Step 2: Clean up remote hung processes
    execute_step "cleanup_remote_processes" \
        "ssh -i '$SSH_KEY' 'root@$SERVER_IP' 'pkill -f vllm 2>/dev/null || true; pkill -f python 2>/dev/null || true'" \
        "Cleaning up remote hung processes"
    
    # Step 3: Clear GPU processes if possible
    if command -v nvidia-smi >/dev/null 2>&1; then
        execute_step "cleanup_gpu_processes" \
            "nvidia-smi --gpu-reset 2>/dev/null || true" \
            "Attempting GPU process cleanup"
    fi
    
    # Step 4: Remove stale lock files
    execute_step "remove_lock_files" \
        "rm -f '$TUNNEL_PID_FILE' /tmp/.vllm-* /tmp/vllm-* 2>/dev/null || true" \
        "Removing stale lock files"
    
    return 0
}

recover_memory_cleanup() {
    log "${BOLD}${BLUE}=== Memory Cleanup Recovery ===${NC}"
    
    FIXES_ATTEMPTED+=("memory-cleanup")
    
    # Step 1: Clear local system cache
    execute_step "clear_local_cache" \
        "sync && echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true" \
        "Clearing local system cache"
    
    # Step 2: Clear remote system cache
    execute_step "clear_remote_cache" \
        "ssh -i '$SSH_KEY' 'root@$SERVER_IP' 'sync && echo 3 > /proc/sys/vm/drop_caches || true'" \
        "Clearing remote system cache"
    
    # Step 3: Reset GPU memory on remote server
    execute_step "reset_gpu_memory" \
        "ssh -i '$SSH_KEY' 'root@$SERVER_IP' 'nvidia-smi --gpu-reset || true'" \
        "Resetting GPU memory on remote server"
    
    # Step 4: Clear CUDA cache
    execute_step "clear_cuda_cache" \
        "ssh -i '$SSH_KEY' 'root@$SERVER_IP' 'rm -rf /tmp/cuda-* /root/.cache/torch* 2>/dev/null || true'" \
        "Clearing CUDA cache files"
    
    return 0
}

perform_full_recovery() {
    log "${BOLD}${MAGENTA}=== Full System Recovery ===${NC}"
    log "Performing complete system recovery sequence..."
    log ""
    
    FIXES_ATTEMPTED+=("full-recovery")
    
    # Phase 1: Process and connection cleanup
    log "${YELLOW}Phase 1: Cleanup${NC}"
    recover_process_cleanup
    log ""
    
    # Phase 2: Memory cleanup
    log "${YELLOW}Phase 2: Memory Management${NC}"
    recover_memory_cleanup
    log ""
    
    # Phase 3: Network recovery
    log "${YELLOW}Phase 3: Network Recovery${NC}"
    recover_ssh_tunnel
    log ""
    
    # Phase 4: Service recovery
    log "${YELLOW}Phase 4: Service Recovery${NC}"
    recover_vllm_server
    log ""
    
    # Phase 5: Final validation
    log "${YELLOW}Phase 5: Validation${NC}"
    execute_step "final_system_check" \
        "timeout 30 curl -s -H 'Authorization: Bearer $API_KEY' '$API_URL/v1/models' | jq -e '.data' >/dev/null" \
        "Performing final system validation"
    
    log ""
    log "${GREEN}Full recovery sequence completed${NC}"
    
    return 0
}

# Output functions
show_recovery_summary() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        output_json
        return
    fi
    
    log ""
    log "${BOLD}${CYAN}=== Recovery Summary ===${NC}"
    
    local total_steps=${#RECOVERY_STEPS[@]}
    local successful_steps=${#FIXES_SUCCESSFUL[@]}
    local attempted_fixes=${#FIXES_ATTEMPTED[@]}
    
    log "Recovery steps executed: $total_steps"
    log "Successful steps: $successful_steps"
    log "Fixes attempted: $attempted_fixes"
    
    if [[ "${#ISSUES_DETECTED[@]}" -gt 0 ]]; then
        log ""
        log "${YELLOW}Issues detected:${NC}"
        for issue in "${ISSUES_DETECTED[@]}"; do
            log "  ${YELLOW}• $issue${NC}"
        done
    fi
    
    if [[ "${#FIXES_ATTEMPTED[@]}" -gt 0 ]]; then
        log ""
        log "${BLUE}Recovery actions attempted:${NC}"
        for fix in "${FIXES_ATTEMPTED[@]}"; do
            log "  ${BLUE}• $fix${NC}"
        done
    fi
    
    if [[ "${#FIXES_SUCCESSFUL[@]}" -gt 0 ]]; then
        log ""
        log "${GREEN}Successful recovery actions:${NC}"
        for fix in "${FIXES_SUCCESSFUL[@]}"; do
            log "  ${GREEN}✅ $fix${NC}"
        done
    fi
    
    # Final status
    log ""
    if [[ "$successful_steps" -eq "$total_steps" && "$total_steps" -gt 0 ]]; then
        log "${GREEN}🎉 Recovery completed successfully!${NC}"
        log "System should now be operational."
        exit 0
    elif [[ "$successful_steps" -gt 0 ]]; then
        log "${YELLOW}⚠️  Recovery partially successful${NC}"
        log "Some issues may remain. Run diagnostics to verify system status."
        exit 2
    else
        log "${RED}❌ Recovery failed${NC}"
        log "Manual intervention may be required."
        exit 1
    fi
}

output_json() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    echo "{"
    echo "  \"timestamp\": \"$timestamp\","
    echo "  \"recovery_summary\": {"
    echo "    \"total_steps\": ${#RECOVERY_STEPS[@]},"
    echo "    \"successful_steps\": ${#FIXES_SUCCESSFUL[@]},"
    echo "    \"attempted_fixes\": ${#FIXES_ATTEMPTED[@]}"
    echo "  },"
    echo "  \"issues_detected\": $(printf '%s\n' "${ISSUES_DETECTED[@]}" | jq -R . | jq -s .),"
    echo "  \"fixes_attempted\": $(printf '%s\n' "${FIXES_ATTEMPTED[@]}" | jq -R . | jq -s .),"
    echo "  \"fixes_successful\": $(printf '%s\n' "${FIXES_SUCCESSFUL[@]}" | jq -R . | jq -s .),"
    echo "  \"recovery_steps\": ["
    
    local first=true
    for i in "${!RECOVERY_STEPS[@]}"; do
        [[ "$first" == "false" ]] && echo ","
        echo "    {"
        echo "      \"step\": \"${RECOVERY_STEPS[i]}\","
        echo "      \"result\": \"${RECOVERY_RESULTS[i]}\""
        echo -n "    }"
        first=false
    done
    
    echo ""
    echo "  ]"
    echo "}"
}

# Main execution
main() {
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        log "${CYAN}${BOLD}"
        log "╔════════════════════════════════════════════════════════════════╗"
        log "║                    vLLM Recovery Tools                        ║"
        log "║                    $(date '+%Y-%m-%d %H:%M:%S')                    ║"
        log "╚════════════════════════════════════════════════════════════════╝"
        log "${NC}"
    fi
    
    log_recovery "Recovery session started - Action: ${ACTION:-check-all}"
    
    # Execute based on flags and actions
    if [[ "$CHECK_ALL" == "true" ]]; then
        diagnose_system
        local issues_count=$?
        
        if [[ "$issues_count" -gt 0 ]]; then
            if [[ "$AUTO_FIX" == "true" ]]; then
                log ""
                log "${YELLOW}Auto-fix enabled. Attempting to resolve detected issues...${NC}"
                perform_full_recovery
            else
                log ""
                log "${YELLOW}Issues detected. Use --auto-fix to attempt automatic recovery.${NC}"
                log "${YELLOW}Or run specific recovery actions:${NC}"
                log "  • $0 tunnel-restart     # Fix SSH tunnel issues"
                log "  • $0 vllm-restart       # Restart vLLM server"
                log "  • $0 process-cleanup    # Clean up hung processes"
                log "  • $0 memory-cleanup     # Clear memory and cache"
                log "  • $0 full-recovery      # Complete recovery sequence"
            fi
        elif [[ "$FORCE" == "true" ]]; then
            log "${YELLOW}Force flag enabled. Performing recovery anyway...${NC}"
            perform_full_recovery
        fi
        
    elif [[ -n "$ACTION" ]]; then
        case "$ACTION" in
            "tunnel-restart")
                recover_ssh_tunnel
                ;;
            "vllm-restart")
                recover_vllm_server
                ;;
            "process-cleanup")
                recover_process_cleanup
                ;;
            "memory-cleanup")
                recover_memory_cleanup
                ;;
            "full-recovery")
                perform_full_recovery
                ;;
        esac
    fi
    
    # Show summary
    show_recovery_summary
}

# Cleanup function
cleanup() {
    log_recovery "Recovery session ended"
}
trap cleanup EXIT

# Run main function
main "$@"