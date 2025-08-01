#!/bin/bash
# Comprehensive Health Check Script for vLLM Server Infrastructure
# Checks all system components: GPUs, vLLM server, model, API, tunnels
#
# Usage: ./health-check.sh [--verbose] [--json] [--fix-issues]
# Options:
#   --verbose     Show detailed output for all checks
#   --json        Output results in JSON format
#   --fix-issues  Attempt to automatically fix detected issues

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/var/log/vllm"
API_KEY="${VLLM_API_KEY:-qwen3-secret-key}"
API_URL="http://localhost:8000"
SSH_KEY="$HOME/.ssh/qwen3-deploy-20250731-114902"
SERVER_IP="86.38.238.64"
TUNNEL_PID_FILE="$HOME/.qwen3_tunnel.pid"

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Flags
VERBOSE=false
JSON_OUTPUT=false
FIX_ISSUES=false
ISSUES_FOUND=()
FIXES_APPLIED=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE=true
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
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--verbose] [--json] [--fix-issues]"
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

verbose_log() {
    if [[ "$VERBOSE" == "true" && "$JSON_OUTPUT" == "false" ]]; then
        echo -e "  ${CYAN}$1${NC}"
    fi
}

check_status() {
    local name="$1"
    local status="$2"
    local details="$3"
    
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        if [[ "$status" == "PASS" ]]; then
            echo -e "${GREEN}✅ $name${NC}"
            [[ -n "$details" ]] && verbose_log "$details"
        elif [[ "$status" == "WARN" ]]; then
            echo -e "${YELLOW}⚠️  $name${NC}"
            [[ -n "$details" ]] && echo -e "  ${YELLOW}$details${NC}"
        else
            echo -e "${RED}❌ $name${NC}"
            [[ -n "$details" ]] && echo -e "  ${RED}$details${NC}"
            ISSUES_FOUND+=("$name: $details")
        fi
    fi
}

# JSON result tracking
declare -A RESULTS

add_result() {
    local category="$1"
    local check="$2"
    local status="$3"
    local details="$4"
    
    RESULTS["${category}_${check}"]="$status|$details"
}

# Health check functions
check_system_dependencies() {
    log "${BOLD}=== System Dependencies ===${NC}"
    
    # Check Python environment
    if [[ -f "/opt/vllm/bin/activate" ]]; then
        check_status "Python vLLM Environment" "PASS" "Found at /opt/vllm/bin/activate"
        add_result "system" "python_env" "PASS" "vLLM environment available"
        
        # Check vLLM installation
        if source /opt/vllm/bin/activate && python -c "import vllm" 2>/dev/null; then
            local vllm_version=$(source /opt/vllm/bin/activate && python -c "import vllm; print(vllm.__version__)" 2>/dev/null)
            check_status "vLLM Installation" "PASS" "Version: $vllm_version"
            add_result "system" "vllm" "PASS" "Version: $vllm_version"
        else
            check_status "vLLM Installation" "FAIL" "vLLM not importable"
            add_result "system" "vllm" "FAIL" "Import failed"
        fi
    else
        check_status "Python vLLM Environment" "FAIL" "Environment not found at /opt/vllm"
        add_result "system" "python_env" "FAIL" "Environment missing"
    fi
    
    # Check model files
    if [[ -d "/models/qwen3" ]]; then
        local model_size=$(du -sh /models/qwen3 2>/dev/null | cut -f1)
        check_status "Model Files" "PASS" "Size: $model_size"
        add_result "system" "model_files" "PASS" "Size: $model_size"
        
        # Check key model files
        local config_exists="FAIL"
        [[ -f "/models/qwen3/config.json" ]] && config_exists="PASS"
        check_status "Model Configuration" "$config_exists" "config.json present"
        add_result "system" "model_config" "$config_exists" "config.json check"
    else
        check_status "Model Files" "FAIL" "Directory /models/qwen3 not found"
        add_result "system" "model_files" "FAIL" "Directory missing"
    fi
    
    # Check CUDA/GPU
    if command -v nvidia-smi &> /dev/null; then
        local gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits | head -1)
        if [[ "$gpu_count" -ge "4" ]]; then
            check_status "GPU Hardware" "PASS" "$gpu_count GPUs detected"
            add_result "system" "gpu_hardware" "PASS" "$gpu_count GPUs"
        else
            check_status "GPU Hardware" "WARN" "Only $gpu_count GPUs detected (need 4)"
            add_result "system" "gpu_hardware" "WARN" "Insufficient GPUs: $gpu_count"
        fi
    else
        check_status "GPU Hardware" "FAIL" "nvidia-smi not available"
        add_result "system" "gpu_hardware" "FAIL" "nvidia-smi missing"
    fi
    
    log ""
}

check_gpu_status() {
    log "${BOLD}=== GPU Status ===${NC}"
    
    if command -v nvidia-smi &> /dev/null; then
        # Check GPU memory usage
        local gpu_info=$(nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits)
        local gpu_issues=0
        
        while IFS=, read -r index name mem_used mem_total gpu_util; do
            # Clean up values
            index=$(echo "$index" | xargs)
            name=$(echo "$name" | xargs)
            mem_used=$(echo "$mem_used" | xargs)
            mem_total=$(echo "$mem_total" | xargs)
            gpu_util=$(echo "$gpu_util" | xargs)
            
            local mem_percent=$((mem_used * 100 / mem_total))
            
            verbose_log "GPU $index ($name): ${mem_used}MB/${mem_total}MB (${mem_percent}%), Util: ${gpu_util}%"
            
            if [[ "$mem_percent" -lt "90" && "$mem_percent" -gt "5" ]]; then
                check_status "GPU $index Memory" "PASS" "${mem_percent}% used (${mem_used}MB/${mem_total}MB)"
                add_result "gpu" "gpu${index}_memory" "PASS" "${mem_percent}% used"
            elif [[ "$mem_percent" -ge "90" ]]; then
                check_status "GPU $index Memory" "WARN" "High usage: ${mem_percent}% (${mem_used}MB/${mem_total}MB)"
                add_result "gpu" "gpu${index}_memory" "WARN" "High usage: ${mem_percent}%"
                ((gpu_issues++))
            else
                check_status "GPU $index Memory" "WARN" "Low usage: ${mem_percent}% - may indicate no load"
                add_result "gpu" "gpu${index}_memory" "WARN" "Low usage: ${mem_percent}%"
            fi
        done <<< "$gpu_info"
        
        # Check for zombie processes
        local gpu_processes=$(nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader,nounits 2>/dev/null || echo "")
        if [[ -n "$gpu_processes" ]]; then
            local process_count=$(echo "$gpu_processes" | wc -l)
            check_status "GPU Processes" "PASS" "$process_count active processes"
            add_result "gpu" "processes" "PASS" "$process_count processes"
            verbose_log "Active GPU processes:"
            while IFS=, read -r pid name mem; do
                verbose_log "  PID: $(echo $pid | xargs), Process: $(echo $name | xargs), Memory: $(echo $mem | xargs)MB"
            done <<< "$gpu_processes"
        else
            check_status "GPU Processes" "WARN" "No GPU processes detected"
            add_result "gpu" "processes" "WARN" "No processes found"
        fi
        
    else
        check_status "GPU Monitoring" "FAIL" "nvidia-smi not available"
        add_result "gpu" "monitoring" "FAIL" "nvidia-smi missing"
    fi
    
    log ""
}

check_network_connectivity() {
    log "${BOLD}=== Network Connectivity ===${NC}"
    
    # Check SSH tunnel
    local tunnel_status="FAIL"
    if [[ -f "$TUNNEL_PID_FILE" ]] && kill -0 $(cat "$TUNNEL_PID_FILE") 2>/dev/null; then
        tunnel_status="PASS"
        local tunnel_pid=$(cat "$TUNNEL_PID_FILE")
        check_status "SSH Tunnel (PID file)" "PASS" "PID: $tunnel_pid"
        add_result "network" "tunnel_pidfile" "PASS" "PID: $tunnel_pid"
    elif pgrep -f "ssh.*8000:localhost:8000.*$SERVER_IP" > /dev/null; then
        tunnel_status="PASS"
        local tunnel_pid=$(pgrep -f "ssh.*8000:localhost:8000.*$SERVER_IP")
        check_status "SSH Tunnel (process)" "PASS" "PID: $tunnel_pid"
        add_result "network" "tunnel_process" "PASS" "PID: $tunnel_pid"
    else
        check_status "SSH Tunnel" "FAIL" "No tunnel process found"
        add_result "network" "tunnel" "FAIL" "No tunnel found"
        
        if [[ "$FIX_ISSUES" == "true" ]]; then
            log "  ${YELLOW}Attempting to start SSH tunnel...${NC}"
            if start_ssh_tunnel; then
                FIXES_APPLIED+=("Started SSH tunnel")
                tunnel_status="PASS"
            fi
        fi
    fi
    
    # Test local API connectivity
    if [[ "$tunnel_status" == "PASS" ]]; then
        local api_test=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" "$API_URL/health" 2>/dev/null || echo "000")
        if [[ "$api_test" == "200" ]]; then
            check_status "API Health Endpoint" "PASS" "HTTP 200 response"
            add_result "network" "api_health" "PASS" "HTTP 200"
        elif [[ "$api_test" == "401" ]]; then
            check_status "API Health Endpoint" "WARN" "HTTP 401 - Auth required but server responding"
            add_result "network" "api_health" "WARN" "HTTP 401 - auth required"
        else
            check_status "API Health Endpoint" "FAIL" "HTTP $api_test - Server not responding"
            add_result "network" "api_health" "FAIL" "HTTP $api_test"
        fi
        
        # Test authenticated API call
        local models_test=$(curl -s --max-time 10 -H "Authorization: Bearer $API_KEY" "$API_URL/v1/models" 2>/dev/null)
        if echo "$models_test" | grep -q '"object": "list"'; then
            local model_count=$(echo "$models_test" | jq -r '.data | length' 2>/dev/null || echo "unknown")
            check_status "API Models Endpoint" "PASS" "$model_count models available"
            add_result "network" "api_models" "PASS" "$model_count models"
        else
            check_status "API Models Endpoint" "FAIL" "Invalid response or auth failure"
            add_result "network" "api_models" "FAIL" "Invalid response"
            verbose_log "Response: $(echo "$models_test" | head -c 200)..."
        fi
    fi
    
    log ""
}

check_vllm_server() {
    log "${BOLD}=== vLLM Server Status ===${NC}"
    
    # Check for vLLM processes
    local vllm_processes=$(pgrep -f "vllm.*serve" 2>/dev/null || echo "")
    if [[ -n "$vllm_processes" ]]; then
        local process_count=$(echo "$vllm_processes" | wc -w)
        check_status "vLLM Server Process" "PASS" "$process_count processes running"
        add_result "server" "process" "PASS" "$process_count processes"
        
        # Get detailed process info
        while read -r pid; do
            [[ -z "$pid" ]] && continue
            local process_info=$(ps -p "$pid" -o pid,ppid,cmd --no-headers 2>/dev/null || echo "")
            verbose_log "PID $pid: $(echo "$process_info" | cut -c1-80)..."
        done <<< "$vllm_processes"
    else
        check_status "vLLM Server Process" "FAIL" "No vLLM processes found"
        add_result "server" "process" "FAIL" "No processes"
        
        if [[ "$FIX_ISSUES" == "true" ]]; then
            log "  ${YELLOW}Attempting to start vLLM server...${NC}"
            if start_vllm_server; then
                FIXES_APPLIED+=("Started vLLM server")
            fi
        fi
    fi
    
    # Check screen sessions
    local screen_sessions=$(screen -ls 2>/dev/null | grep vllm || echo "")
    if [[ -n "$screen_sessions" ]]; then
        check_status "Screen Sessions" "PASS" "vLLM screen session active"
        add_result "server" "screen" "PASS" "Session active"
        verbose_log "$screen_sessions"
    else
        check_status "Screen Sessions" "WARN" "No vLLM screen sessions found"
        add_result "server" "screen" "WARN" "No sessions"
    fi
    
    # Check log files
    if [[ -d "$LOG_DIR" ]]; then
        local latest_log=$(find "$LOG_DIR" -name "vllm-*.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
        if [[ -n "$latest_log" ]]; then
            local log_age=$(stat -c %Y "$latest_log" 2>/dev/null || echo "0")
            local current_time=$(date +%s)
            local age_minutes=$(( (current_time - log_age) / 60 ))
            
            if [[ "$age_minutes" -lt "30" ]]; then
                check_status "Server Logs" "PASS" "Recent log: $latest_log ($age_minutes min old)"
                add_result "server" "logs" "PASS" "Recent log available"
            else
                check_status "Server Logs" "WARN" "Log file old: $age_minutes minutes"
                add_result "server" "logs" "WARN" "Old log file"
            fi
            
            # Check for recent errors in logs
            local error_count=$(grep -c "ERROR\|CRITICAL\|FATAL" "$latest_log" 2>/dev/null | tail -100 || echo "0")
            if [[ "$error_count" -gt "0" ]]; then
                check_status "Log Errors" "WARN" "$error_count errors found in recent logs"
                add_result "server" "log_errors" "WARN" "$error_count errors"
            else
                check_status "Log Errors" "PASS" "No recent errors in logs"
                add_result "server" "log_errors" "PASS" "No errors"
            fi
        else
            check_status "Server Logs" "WARN" "No log files found in $LOG_DIR"
            add_result "server" "logs" "WARN" "No log files"
        fi
    else
        check_status "Log Directory" "WARN" "Log directory $LOG_DIR does not exist"
        add_result "server" "log_dir" "WARN" "Directory missing"
    fi
    
    log ""
}

check_model_status() {
    log "${BOLD}=== Model Status ===${NC}"
    
    # Test model inference
    if curl -s --max-time 5 "$API_URL/health" >/dev/null 2>&1; then
        local test_response=$(curl -s --max-time 30 \
            -H "Authorization: Bearer $API_KEY" \
            -H "Content-Type: application/json" \
            -d '{
                "model": "qwen3",
                "messages": [{"role": "user", "content": "Say hello"}],
                "max_tokens": 10
            }' \
            "$API_URL/v1/chat/completions" 2>/dev/null)
        
        if echo "$test_response" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
            local response_content=$(echo "$test_response" | jq -r '.choices[0].message.content' 2>/dev/null)
            check_status "Model Inference" "PASS" "Response: $(echo "$response_content" | head -c 50)..."
            add_result "model" "inference" "PASS" "Working"
            
            # Check token usage
            local prompt_tokens=$(echo "$test_response" | jq -r '.usage.prompt_tokens // 0' 2>/dev/null)
            local completion_tokens=$(echo "$test_response" | jq -r '.usage.completion_tokens // 0' 2>/dev/null)
            verbose_log "Token usage: $prompt_tokens prompt + $completion_tokens completion"
            
        else
            check_status "Model Inference" "FAIL" "Invalid response from model"
            add_result "model" "inference" "FAIL" "Invalid response"
            verbose_log "Response: $(echo "$test_response" | head -c 200)..."
        fi
        
        # Performance test
        local start_time=$(date +%s.%N)
        local perf_response=$(curl -s --max-time 60 \
            -H "Authorization: Bearer $API_KEY" \
            -H "Content-Type: application/json" \
            -d '{
                "model": "qwen3",
                "messages": [{"role": "user", "content": "Write a short Python function to calculate fibonacci numbers"}],
                "max_tokens": 100
            }' \
            "$API_URL/v1/chat/completions" 2>/dev/null)
        local end_time=$(date +%s.%N)
        
        if echo "$perf_response" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
            local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "unknown")
            local tokens=$(echo "$perf_response" | jq -r '.usage.completion_tokens // 0' 2>/dev/null)
            local tokens_per_sec=$(echo "scale=2; $tokens / $duration" | bc 2>/dev/null || echo "unknown")
            
            check_status "Model Performance" "PASS" "${tokens} tokens in ${duration}s (${tokens_per_sec} tok/s)"
            add_result "model" "performance" "PASS" "${tokens_per_sec} tok/s"
        else
            check_status "Model Performance" "WARN" "Performance test failed"
            add_result "model" "performance" "WARN" "Test failed"
        fi
    else
        check_status "Model Inference" "FAIL" "API not accessible for testing"
        add_result "model" "inference" "FAIL" "API not accessible"
    fi
    
    log ""
}

# Auto-fix functions
start_ssh_tunnel() {
    if [[ ! -f "$SSH_KEY" ]]; then
        log "  ${RED}SSH key not found: $SSH_KEY${NC}"
        return 1
    fi
    
    # Start tunnel in background
    ssh -i "$SSH_KEY" -f -N -L 8000:localhost:8000 "root@$SERVER_IP" 2>/dev/null
    local ssh_pid=$!
    
    # Save PID
    echo "$ssh_pid" > "$TUNNEL_PID_FILE"
    
    # Wait a moment and test
    sleep 2
    if kill -0 "$ssh_pid" 2>/dev/null; then
        log "  ${GREEN}SSH tunnel started successfully (PID: $ssh_pid)${NC}"
        return 0
    else
        log "  ${RED}Failed to start SSH tunnel${NC}"
        return 1
    fi
}

start_vllm_server() {
    local start_script="/Users/jamesfincher/backup/server_backup_20250731_155918/scripts/production/start-vllm-server.sh"
    
    if [[ -f "$start_script" ]]; then
        log "  ${YELLOW}Starting vLLM server via SSH...${NC}"
        # This would need to be executed on the remote server
        # For now, just indicate what should be done
        log "  ${YELLOW}Run on remote server: $start_script${NC}"
        return 1
    else
        log "  ${RED}Start script not found: $start_script${NC}"
        return 1
    fi
}

# Output functions
output_json() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local overall_status="PASS"
    
    # Determine overall status
    for key in "${!RESULTS[@]}"; do
        local status=$(echo "${RESULTS[$key]}" | cut -d'|' -f1)
        if [[ "$status" == "FAIL" ]]; then
            overall_status="FAIL"
            break
        elif [[ "$status" == "WARN" && "$overall_status" != "FAIL" ]]; then
            overall_status="WARN"
        fi
    done
    
    echo "{"
    echo "  \"timestamp\": \"$timestamp\","
    echo "  \"overall_status\": \"$overall_status\","
    echo "  \"checks\": {"
    
    local first=true
    for key in "${!RESULTS[@]}"; do
        local category=$(echo "$key" | cut -d'_' -f1)
        local check=$(echo "$key" | cut -d'_' -f2-)
        local status=$(echo "${RESULTS[$key]}" | cut -d'|' -f1)
        local details=$(echo "${RESULTS[$key]}" | cut -d'|' -f2-)
        
        [[ "$first" == "false" ]] && echo ","
        echo -n "    \"$key\": {\"category\": \"$category\", \"check\": \"$check\", \"status\": \"$status\", \"details\": \"$details\"}"
        first=false
    done
    
    echo ""
    echo "  },"
    echo "  \"issues_found\": $(printf '%s\n' "${ISSUES_FOUND[@]}" | jq -R . | jq -s .),"
    echo "  \"fixes_applied\": $(printf '%s\n' "${FIXES_APPLIED[@]}" | jq -R . | jq -s .)"
    echo "}"
}

show_summary() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        output_json
        return
    fi
    
    log "${BOLD}=== Health Check Summary ===${NC}"
    
    local pass_count=0
    local warn_count=0
    local fail_count=0
    
    for key in "${!RESULTS[@]}"; do
        local status=$(echo "${RESULTS[$key]}" | cut -d'|' -f1)
        case "$status" in
            "PASS") ((pass_count++)) ;;
            "WARN") ((warn_count++)) ;;
            "FAIL") ((fail_count++)) ;;
        esac
    done
    
    log "Total Checks: $((pass_count + warn_count + fail_count))"
    log "${GREEN}Passed: $pass_count${NC}"
    [[ "$warn_count" -gt "0" ]] && log "${YELLOW}Warnings: $warn_count${NC}"
    [[ "$fail_count" -gt "0" ]] && log "${RED}Failed: $fail_count${NC}"
    
    if [[ "${#ISSUES_FOUND[@]}" -gt "0" ]]; then
        log ""
        log "${RED}Issues Found:${NC}"
        for issue in "${ISSUES_FOUND[@]}"; do
            log "  ${RED}• $issue${NC}"
        done
    fi
    
    if [[ "${#FIXES_APPLIED[@]}" -gt "0" ]]; then
        log ""
        log "${GREEN}Fixes Applied:${NC}"
        for fix in "${FIXES_APPLIED[@]}"; do
            log "  ${GREEN}• $fix${NC}"
        done
    fi
    
    if [[ "$fail_count" -gt "0" ]]; then
        log ""
        log "${YELLOW}Recommended Actions:${NC}"
        log "  • Check vLLM server logs: tail -f $LOG_DIR/vllm-*.log"
        log "  • Verify SSH tunnel: ./scripts/debugging/network-diagnostics.sh"
        log "  • Monitor GPU usage: ./scripts/debugging/gpu-monitor.sh"
        log "  • Run with --fix-issues to attempt automatic repairs"
        exit 1
    elif [[ "$warn_count" -gt "0" ]]; then
        log ""
        log "${YELLOW}System operational with warnings. Monitor for issues.${NC}"
        exit 2
    else
        log ""
        log "${GREEN}All systems operational!${NC}"
        exit 0
    fi
}

# Main execution
main() {
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        log "${CYAN}${BOLD}"
        log "╔════════════════════════════════════════════════════════════════╗"
        log "║                 vLLM Infrastructure Health Check               ║"
        log "║                    $(date '+%Y-%m-%d %H:%M:%S')                    ║"
        log "╚════════════════════════════════════════════════════════════════╝"
        log "${NC}"
    fi
    
    check_system_dependencies
    check_gpu_status
    check_network_connectivity
    check_vllm_server
    check_model_status
    
    show_summary
}

# Trap for cleanup
cleanup() {
    if [[ -n "$temp_files" ]]; then
        rm -f $temp_files
    fi
}
trap cleanup EXIT

# Run main function
main "$@"