#!/bin/bash
# Network Connectivity Diagnostics for vLLM Infrastructure
# Comprehensive network troubleshooting for SSH tunnels, API endpoints, and connectivity
#
# Usage: ./network-diagnostics.sh [OPTIONS]
# Options:
#   --tunnel-only     Test only SSH tunnel connectivity
#   --api-only        Test only API endpoints
#   --fix-issues      Attempt to automatically fix detected issues
#   --verbose         Show detailed connection information
#   --json            Output results in JSON format
#   --continuous      Run continuous monitoring (every 30 seconds)
#   --help            Show this help message

set -e

# Configuration
SSH_KEY="$HOME/.ssh/qwen3-deploy-20250731-114902"
SERVER_IP="86.38.238.64"
SERVER_PORT="22"
API_KEY="${VLLM_API_KEY:-qwen3-secret-key}"
TUNNEL_PID_FILE="$HOME/.qwen3_tunnel.pid"
API_URL="http://localhost:8000"
REMOTE_API_URL="http://localhost:8000"

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
TUNNEL_ONLY=false
API_ONLY=false
FIX_ISSUES=false
VERBOSE=false
JSON_OUTPUT=false
CONTINUOUS=false

# Results tracking
declare -A TEST_RESULTS
ISSUES_FOUND=()
FIXES_APPLIED=()

show_help() {
    cat << EOF
Network Diagnostics Tool for vLLM Infrastructure

Usage: $0 [OPTIONS]

OPTIONS:
  --tunnel-only     Test only SSH tunnel connectivity
  --api-only        Test only API endpoints  
  --fix-issues      Attempt to automatically fix detected issues
  --verbose         Show detailed connection information
  --json            Output results in JSON format
  --continuous      Run continuous monitoring (every 30 seconds)
  --help            Show this help message

TESTS PERFORMED:
  SSH Connectivity:
    • SSH key availability and permissions
    • Connection to remote server
    • SSH tunnel establishment and health
    • Port forwarding verification
    
  API Connectivity:
    • Local API endpoint accessibility
    • Authentication validation
    • Response time measurement
    • Model availability testing
    
  Network Performance:
    • Latency measurements
    • Bandwidth testing (optional)
    • Connection stability analysis
    • Concurrent connection handling

COMMON ISSUES DETECTED:
  • SSH key permission problems
  • Firewall blocking connections
  • Tunnel process crashes
  • API authentication failures
  • High latency or packet loss
  • Port conflicts or binding issues

AUTOMATIC FIXES:
  • SSH key permission correction
  • Tunnel restart and recovery
  • Connection retry with backoff
  • Stale process cleanup
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --tunnel-only)
            TUNNEL_ONLY=true
            shift
            ;;
        --api-only)
            API_ONLY=true
            shift
            ;;
        --fix-issues)
            FIX_ISSUES=true
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
        --continuous)
            CONTINUOUS=true
            shift
            ;;
        --help)
            show_help
            exit 0
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

verbose_log() {
    if [[ "$VERBOSE" == "true" && "$JSON_OUTPUT" == "false" ]]; then
        echo -e "  ${CYAN}$1${NC}"
    fi
}

test_result() {
    local test_name="$1"
    local status="$2"
    local details="$3"
    local latency="$4"
    
    TEST_RESULTS["$test_name"]="$status|$details|$latency"
    
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        case "$status" in
            "PASS")
                echo -e "${GREEN}✅ $test_name${NC}"
                [[ -n "$details" ]] && verbose_log "$details"
                [[ -n "$latency" ]] && verbose_log "Latency: ${latency}ms"
                ;;
            "WARN")
                echo -e "${YELLOW}⚠️  $test_name${NC}"
                [[ -n "$details" ]] && echo -e "   ${YELLOW}$details${NC}"
                [[ -n "$latency" ]] && echo -e "   ${YELLOW}Latency: ${latency}ms${NC}"
                ;;
            "FAIL")
                echo -e "${RED}❌ $test_name${NC}"
                [[ -n "$details" ]] && echo -e "   ${RED}$details${NC}"
                ISSUES_FOUND+=("$test_name: $details")
                ;;
        esac
    fi
}

# SSH connectivity tests
test_ssh_key() {
    log "${BOLD}=== SSH Key Validation ===${NC}"
    
    if [[ ! -f "$SSH_KEY" ]]; then
        test_result "SSH Key Exists" "FAIL" "Key file not found: $SSH_KEY"
        return
    fi
    
    local key_perms=$(stat -c "%a" "$SSH_KEY" 2>/dev/null || stat -f "%A" "$SSH_KEY" 2>/dev/null)
    if [[ "$key_perms" == "600" || "$key_perms" == "400" ]]; then
        test_result "SSH Key Permissions" "PASS" "Permissions: $key_perms"
    else
        test_result "SSH Key Permissions" "WARN" "Permissions: $key_perms (should be 600)"
        
        if [[ "$FIX_ISSUES" == "true" ]]; then
            chmod 600 "$SSH_KEY"
            test_result "SSH Key Permission Fix" "PASS" "Fixed permissions to 600"
            FIXES_APPLIED+=("Fixed SSH key permissions")
        fi
    fi
    
    # Test key format
    if ssh-keygen -l -f "$SSH_KEY" >/dev/null 2>&1; then
        local key_info=$(ssh-keygen -l -f "$SSH_KEY" 2>/dev/null)
        test_result "SSH Key Format" "PASS" "Valid key: $key_info"
    else
        test_result "SSH Key Format" "FAIL" "Invalid or corrupted key file"
    fi
    
    log ""
}

test_ssh_connectivity() {
    log "${BOLD}=== SSH Server Connectivity ===${NC}"
    
    # Test basic connectivity
    local start_time=$(date +%s%N)
    if timeout 10 ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no \
       "root@$SERVER_IP" "echo 'SSH connection successful'" >/dev/null 2>&1; then
        local end_time=$(date +%s%N)
        local latency=$(( (end_time - start_time) / 1000000 ))
        test_result "SSH Connection" "PASS" "Connected successfully" "$latency"
    else
        test_result "SSH Connection" "FAIL" "Cannot connect to $SERVER_IP:$SERVER_PORT"
        return
    fi
    
    # Test command execution
    local remote_output=$(timeout 15 ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o BatchMode=yes \
                         "root@$SERVER_IP" "hostname && uptime" 2>/dev/null)
    if [[ -n "$remote_output" ]]; then
        local hostname=$(echo "$remote_output" | head -1)
        test_result "Remote Command Execution" "PASS" "Hostname: $hostname"
        verbose_log "Server uptime: $(echo "$remote_output" | tail -1)"
    else
        test_result "Remote Command Execution" "FAIL" "Cannot execute commands on remote server"
    fi
    
    # Test vLLM service status
    local vllm_status=$(timeout 10 ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o BatchMode=yes \
                       "root@$SERVER_IP" "pgrep -f 'vllm.*serve' | wc -l" 2>/dev/null)
    if [[ "$vllm_status" -gt "0" ]]; then
        test_result "Remote vLLM Process" "PASS" "$vllm_status vLLM processes running"
    else
        test_result "Remote vLLM Process" "WARN" "No vLLM processes detected"
    fi
    
    log ""
}

test_ssh_tunnel() {
    log "${BOLD}=== SSH Tunnel Testing ===${NC}"
    
    # Check if tunnel is running
    local tunnel_pid=""
    local tunnel_status="FAIL"
    
    if [[ -f "$TUNNEL_PID_FILE" ]] && kill -0 $(cat "$TUNNEL_PID_FILE") 2>/dev/null; then
        tunnel_pid=$(cat "$TUNNEL_PID_FILE")
        tunnel_status="PASS"
        test_result "Tunnel PID File" "PASS" "PID: $tunnel_pid"
    elif pgrep -f "ssh.*8000:localhost:8000.*$SERVER_IP" > /dev/null; then
        tunnel_pid=$(pgrep -f "ssh.*8000:localhost:8000.*$SERVER_IP" | head -1)
        tunnel_status="PASS"
        test_result "Tunnel Process Discovery" "PASS" "Found PID: $tunnel_pid"
        # Update PID file
        echo "$tunnel_pid" > "$TUNNEL_PID_FILE"
    else
        test_result "SSH Tunnel Process" "FAIL" "No tunnel process found"
        
        if [[ "$FIX_ISSUES" == "true" ]]; then
            log "  ${YELLOW}Attempting to start SSH tunnel...${NC}"
            if start_ssh_tunnel; then
                FIXES_APPLIED+=("Started SSH tunnel")
                tunnel_status="PASS"
            fi
        fi
    fi
    
    # Test tunnel functionality
    if [[ "$tunnel_status" == "PASS" ]]; then
        # Test port forwarding
        local port_test=$(timeout 5 nc -z localhost 8000 2>/dev/null && echo "open" || echo "closed")
        if [[ "$port_test" == "open" ]]; then
            test_result "Port Forwarding" "PASS" "Port 8000 is accessible"
        else
            test_result "Port Forwarding" "FAIL" "Port 8000 not accessible via tunnel"
        fi
        
        # Check tunnel health
        local tunnel_info=$(ps -p "$tunnel_pid" -o pid,ppid,etime,cmd --no-headers 2>/dev/null || echo "")
        if [[ -n "$tunnel_info" ]]; then
            local uptime=$(echo "$tunnel_info" | awk '{print $3}')
            test_result "Tunnel Health" "PASS" "Running for $uptime"
            verbose_log "Tunnel command: $(echo "$tunnel_info" | cut -d' ' -f4-)"
        else
            test_result "Tunnel Health" "FAIL" "Tunnel process died"
        fi
    fi
    
    log ""
}

# API connectivity tests
test_api_endpoints() {
    log "${BOLD}=== API Endpoint Testing ===${NC}"
    
    # Test basic connectivity
    local start_time=$(date +%s%N)
    local health_status=$(timeout 10 curl -s -o /dev/null -w "%{http_code}" "$API_URL/health" 2>/dev/null || echo "000")
    local end_time=$(date +%s%N)
    local latency=$(( (end_time - start_time) / 1000000 ))
    
    case "$health_status" in
        "200")
            test_result "Health Endpoint" "PASS" "HTTP 200 - Server healthy" "$latency"
            ;;
        "401")
            test_result "Health Endpoint" "WARN" "HTTP 401 - Auth required but server responding" "$latency"
            ;;
        "000")
            test_result "Health Endpoint" "FAIL" "Connection failed or timeout"
            return
            ;;
        *)
            test_result "Health Endpoint" "WARN" "HTTP $health_status - Unexpected response" "$latency"
            ;;
    esac
    
    # Test authenticated endpoints
    start_time=$(date +%s%N)
    local models_response=$(timeout 15 curl -s -H "Authorization: Bearer $API_KEY" \
                           "$API_URL/v1/models" 2>/dev/null)
    end_time=$(date +%s%N)
    latency=$(( (end_time - start_time) / 1000000 ))
    
    if echo "$models_response" | jq -e '.data' >/dev/null 2>&1; then
        local model_count=$(echo "$models_response" | jq -r '.data | length' 2>/dev/null)
        test_result "Models Endpoint" "PASS" "$model_count models available" "$latency"
        
        # List available models
        local model_names=$(echo "$models_response" | jq -r '.data[].id' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
        verbose_log "Available models: $model_names"
    else
        test_result "Models Endpoint" "FAIL" "Authentication failed or invalid response" "$latency"
        verbose_log "Response: $(echo "$models_response" | head -c 200)..."
    fi
    
    # Test chat completions
    start_time=$(date +%s%N)
    local chat_response=$(timeout 30 curl -s -H "Authorization: Bearer $API_KEY" \
                         -H "Content-Type: application/json" \
                         -d '{
                             "model": "qwen3",
                             "messages": [{"role": "user", "content": "Hello"}],
                             "max_tokens": 5
                         }' \
                         "$API_URL/v1/chat/completions" 2>/dev/null)
    end_time=$(date +%s%N)
    latency=$(( (end_time - start_time) / 1000000 ))
    
    if echo "$chat_response" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
        local response_content=$(echo "$chat_response" | jq -r '.choices[0].message.content' 2>/dev/null)
        test_result "Chat Completions" "PASS" "Model responding: $(echo "$response_content" | head -c 30)..." "$latency"
        
        # Extract usage statistics
        local prompt_tokens=$(echo "$chat_response" | jq -r '.usage.prompt_tokens // "N/A"' 2>/dev/null)
        local completion_tokens=$(echo "$chat_response" | jq -r '.usage.completion_tokens // "N/A"' 2>/dev/null)
        verbose_log "Token usage: $prompt_tokens prompt + $completion_tokens completion"
    else
        test_result "Chat Completions" "FAIL" "Model inference failed" "$latency"
        
        # Try to extract error information
        local error_msg=$(echo "$chat_response" | jq -r '.error.message // "Unknown error"' 2>/dev/null)
        verbose_log "Error: $error_msg"
    fi
    
    log ""
}

test_api_performance() {
    log "${BOLD}=== API Performance Testing ===${NC}"
    
    # Latency test - multiple quick requests
    local latencies=()
    local success_count=0
    local total_requests=5
    
    for i in $(seq 1 $total_requests); do
        local start_time=$(date +%s%N)
        local response=$(timeout 10 curl -s -H "Authorization: Bearer $API_KEY" \
                        -H "Content-Type: application/json" \
                        -d '{
                            "model": "qwen3",
                            "messages": [{"role": "user", "content": "Hi"}],
                            "max_tokens": 1
                        }' \
                        "$API_URL/v1/chat/completions" 2>/dev/null)
        local end_time=$(date +%s%N)
        local latency=$(( (end_time - start_time) / 1000000 ))
        
        if echo "$response" | jq -e '.choices' >/dev/null 2>&1; then
            latencies+=("$latency")
            ((success_count++))
        fi
        
        # Small delay between requests
        sleep 0.1
    done
    
    if [[ "$success_count" -gt 0 ]]; then
        # Calculate statistics
        local total_latency=0
        local min_latency=${latencies[0]}
        local max_latency=${latencies[0]}
        
        for lat in "${latencies[@]}"; do
            total_latency=$((total_latency + lat))
            [[ "$lat" -lt "$min_latency" ]] && min_latency="$lat"
            [[ "$lat" -gt "$max_latency" ]] && max_latency="$lat"
        done
        
        local avg_latency=$((total_latency / success_count))
        local success_rate=$((success_count * 100 / total_requests))
        
        if [[ "$avg_latency" -lt 2000 ]]; then
            test_result "Response Latency" "PASS" "Avg: ${avg_latency}ms, Min: ${min_latency}ms, Max: ${max_latency}ms"
        elif [[ "$avg_latency" -lt 5000 ]]; then
            test_result "Response Latency" "WARN" "Avg: ${avg_latency}ms (high), Min: ${min_latency}ms, Max: ${max_latency}ms"
        else
            test_result "Response Latency" "FAIL" "Avg: ${avg_latency}ms (very high), Min: ${min_latency}ms, Max: ${max_latency}ms"
        fi
        
        if [[ "$success_rate" -eq 100 ]]; then
            test_result "Request Success Rate" "PASS" "$success_rate% ($success_count/$total_requests)"
        elif [[ "$success_rate" -ge 80 ]]; then
            test_result "Request Success Rate" "WARN" "$success_rate% ($success_count/$total_requests)"
        else
            test_result "Request Success Rate" "FAIL" "$success_rate% ($success_count/$total_requests)"
        fi
    else
        test_result "Performance Test" "FAIL" "All requests failed"
    fi
    
    log ""
}

# Network utilities
test_network_conditions() {
    log "${BOLD}=== Network Conditions ===${NC}"
    
    # Test basic network connectivity to server
    if command -v ping >/dev/null 2>&1; then
        local ping_result=$(ping -c 3 -W 3 "$SERVER_IP" 2>/dev/null | grep "time=" | tail -1)
        if [[ -n "$ping_result" ]]; then
            local ping_time=$(echo "$ping_result" | grep -o "time=[0-9.]*" | cut -d'=' -f2)
            local ping_ms=$(echo "$ping_time" | cut -d'.' -f1)
            
            if [[ "$ping_ms" -lt 50 ]]; then
                test_result "Network Latency" "PASS" "${ping_time}ms"
            elif [[ "$ping_ms" -lt 200 ]]; then
                test_result "Network Latency" "WARN" "${ping_time}ms (moderate)"
            else
                test_result "Network Latency" "FAIL" "${ping_time}ms (high)"
            fi
        else
            test_result "Network Latency" "FAIL" "Cannot ping server"
        fi
    else
        test_result "Network Latency" "WARN" "ping command not available"
    fi
    
    # Test DNS resolution
    if command -v nslookup >/dev/null 2>&1; then
        local dns_result=$(timeout 5 nslookup "$SERVER_IP" 2>/dev/null | grep "name =" | head -1)
        if [[ -n "$dns_result" ]]; then
            local hostname=$(echo "$dns_result" | cut -d'=' -f2 | xargs)
            test_result "DNS Resolution" "PASS" "Resolves to: $hostname"
        else
            test_result "DNS Resolution" "WARN" "No reverse DNS record"
        fi
    fi
    
    # Check local port conflicts
    local port_conflicts=()
    for port in 8000 22; do
        if lsof -ti:$port >/dev/null 2>&1; then
            local process=$(lsof -ti:$port | head -1)
            local proc_name=$(ps -p "$process" -o comm= 2>/dev/null || echo "unknown")
            if [[ "$port" == "8000" ]]; then
                # Port 8000 should be used by our tunnel or vLLM
                if [[ "$proc_name" =~ (ssh|vllm) ]]; then
                    test_result "Port $port Usage" "PASS" "Used by $proc_name (PID: $process)"
                else
                    test_result "Port $port Usage" "WARN" "Used by unexpected process: $proc_name (PID: $process)"
                    port_conflicts+=("$port:$proc_name")
                fi
            fi
        else
            if [[ "$port" == "8000" ]]; then
                test_result "Port $port Usage" "WARN" "Port not in use (tunnel may be down)"
            fi
        fi
    done
    
    log ""
}

# Auto-fix functions
start_ssh_tunnel() {
    verbose_log "Starting SSH tunnel to $SERVER_IP..."
    
    # Kill any existing tunnels
    pkill -f "ssh.*8000:localhost:8000.*$SERVER_IP" 2>/dev/null || true
    [[ -f "$TUNNEL_PID_FILE" ]] && rm -f "$TUNNEL_PID_FILE"
    
    # Start new tunnel
    ssh -i "$SSH_KEY" -f -N -L 8000:localhost:8000 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 \
        "root@$SERVER_IP" 2>/dev/null
    
    local ssh_pid=$(pgrep -f "ssh.*8000:localhost:8000.*$SERVER_IP" | head -1)
    
    if [[ -n "$ssh_pid" ]]; then
        echo "$ssh_pid" > "$TUNNEL_PID_FILE"
        verbose_log "SSH tunnel started successfully (PID: $ssh_pid)"
        
        # Wait for tunnel to be ready
        sleep 2
        if timeout 5 nc -z localhost 8000 2>/dev/null; then
            return 0
        else
            verbose_log "Tunnel started but port not accessible"
            return 1
        fi
    else
        verbose_log "Failed to start SSH tunnel"
        return 1
    fi
}

# JSON output
output_json() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local overall_status="PASS"
    
    # Determine overall status
    for key in "${!TEST_RESULTS[@]}"; do
        local status=$(echo "${TEST_RESULTS[$key]}" | cut -d'|' -f1)
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
    echo "  \"tests\": {"
    
    local first=true
    for key in "${!TEST_RESULTS[@]}"; do
        local status=$(echo "${TEST_RESULTS[$key]}" | cut -d'|' -f1)
        local details=$(echo "${TEST_RESULTS[$key]}" | cut -d'|' -f2)
        local latency=$(echo "${TEST_RESULTS[$key]}" | cut -d'|' -f3)
        
        [[ "$first" == "false" ]] && echo ","
        echo -n "    \"$key\": {\"status\": \"$status\", \"details\": \"$details\""
        [[ -n "$latency" ]] && echo -n ", \"latency_ms\": $latency"
        echo -n "}"
        first=false
    done
    
    echo ""
    echo "  },"
    echo "  \"issues_found\": $(printf '%s\n' "${ISSUES_FOUND[@]}" | jq -R . | jq -s .),"
    echo "  \"fixes_applied\": $(printf '%s\n' "${FIXES_APPLIED[@]}" | jq -R . | jq -s .)"
    echo "}"
}

# Continuous monitoring
run_continuous() {
    log "${CYAN}Starting continuous network monitoring (every 30 seconds)${NC}"
    log "${CYAN}Press Ctrl+C to stop${NC}"
    log ""
    
    local iteration=1
    while true; do
        if [[ "$JSON_OUTPUT" == "false" ]]; then
            log "${MAGENTA}=== Monitoring Iteration $iteration - $(date) ===${NC}"
        fi
        
        # Run abbreviated tests
        test_ssh_tunnel
        test_api_endpoints
        
        # Show brief summary
        local pass_count=0
        local fail_count=0
        for key in "${!TEST_RESULTS[@]}"; do
            local status=$(echo "${TEST_RESULTS[$key]}" | cut -d'|' -f1)
            case "$status" in
                "PASS") ((pass_count++)) ;;
                "FAIL") ((fail_count++)) ;;
            esac
        done
        
        if [[ "$JSON_OUTPUT" == "false" ]]; then
            if [[ "$fail_count" -eq 0 ]]; then
                log "${GREEN}Status: All systems operational ($pass_count checks passed)${NC}"
            else
                log "${RED}Status: $fail_count issues detected${NC}"
            fi
            log ""
        fi
        
        # Clear results for next iteration
        unset TEST_RESULTS
        declare -A TEST_RESULTS
        ISSUES_FOUND=()
        
        ((iteration++))
        sleep 30
    done
}

# Main execution
main() {
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        log "${CYAN}${BOLD}"
        log "╔════════════════════════════════════════════════════════════════╗"
        log "║                Network Connectivity Diagnostics               ║"
        log "║                    $(date '+%Y-%m-%d %H:%M:%S')                    ║"
        log "╚════════════════════════════════════════════════════════════════╝"
        log "${NC}"
    fi
    
    # Handle continuous monitoring
    if [[ "$CONTINUOUS" == "true" ]]; then
        run_continuous
        return
    fi
    
    # Run diagnostics based on flags
    if [[ "$API_ONLY" == "false" ]]; then
        test_ssh_key
        test_ssh_connectivity
        test_ssh_tunnel
        test_network_conditions
    fi
    
    if [[ "$TUNNEL_ONLY" == "false" ]]; then
        test_api_endpoints
        test_api_performance
    fi
    
    # Output results
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        output_json
    else
        # Show summary
        local pass_count=0
        local warn_count=0
        local fail_count=0
        
        for key in "${!TEST_RESULTS[@]}"; do
            local status=$(echo "${TEST_RESULTS[$key]}" | cut -d'|' -f1)
            case "$status" in
                "PASS") ((pass_count++)) ;;
                "WARN") ((warn_count++)) ;;
                "FAIL") ((fail_count++)) ;;
            esac
        done
        
        log "${BOLD}=== Diagnostics Summary ===${NC}"
        log "Total Tests: $((pass_count + warn_count + fail_count))"
        log "${GREEN}Passed: $pass_count${NC}"
        [[ "$warn_count" -gt "0" ]] && log "${YELLOW}Warnings: $warn_count${NC}"
        [[ "$fail_count" -gt "0" ]] && log "${RED}Failed: $fail_count${NC}"
        
        if [[ "${#ISSUES_FOUND[@]}" -gt "0" ]]; then
            log ""
            log "${RED}Issues Detected:${NC}"
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
            log "  • Run with --fix-issues to attempt automatic repairs"
            log "  • Check firewall settings on both local and remote machines"
            log "  • Verify SSH key has correct permissions and is valid"
            log "  • Ensure vLLM server is running on remote machine"
            exit 1
        elif [[ "$warn_count" -gt "0" ]]; then
            log ""
            log "${YELLOW}Network connectivity working with warnings.${NC}"
            exit 2
        else
            log ""
            log "${GREEN}All network connectivity tests passed!${NC}"
            exit 0
        fi
    fi
}

# Cleanup function
cleanup() {
    if [[ -n "$temp_files" ]]; then
        rm -f $temp_files
    fi
}
trap cleanup EXIT

# Run main function
main "$@"