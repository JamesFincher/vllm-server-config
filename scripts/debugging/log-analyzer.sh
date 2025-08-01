#!/bin/bash
# vLLM Log Analysis and Parsing Tool
# Analyzes vLLM server logs for common issues, performance metrics, and patterns
#
# Usage: ./log-analyzer.sh [OPTIONS] [LOG_FILE]
# Options:
#   --errors-only     Show only error messages and critical issues
#   --performance     Show performance metrics and throughput analysis
#   --recent          Analyze only recent logs (last 1000 lines)
#   --follow          Continuously monitor logs (like tail -f)
#   --json            Output analysis in JSON format
#   --summary         Show summary statistics only
#   --help            Show this help message

set -e

# Configuration
LOG_DIR="/var/log/vllm"
DEFAULT_LINES=1000
ANALYSIS_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

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
ERRORS_ONLY=false
PERFORMANCE_ONLY=false
RECENT_ONLY=false
FOLLOW_MODE=false
JSON_OUTPUT=false
SUMMARY_ONLY=false
LOG_FILE=""

# Analysis data structures
declare -A ERROR_COUNTS
declare -A WARNING_COUNTS
declare -A PERFORMANCE_METRICS
declare -A REQUEST_PATTERNS
TIMELINE_DATA=()
CRITICAL_ISSUES=()

show_help() {
    cat << EOF
vLLM Log Analyzer - Comprehensive log analysis tool

Usage: $0 [OPTIONS] [LOG_FILE]

OPTIONS:
  --errors-only     Show only error messages and critical issues
  --performance     Show performance metrics and throughput analysis  
  --recent          Analyze only recent logs (last $DEFAULT_LINES lines)
  --follow          Continuously monitor logs (like tail -f)
  --json            Output analysis in JSON format
  --summary         Show summary statistics only
  --help            Show this help message

LOG_FILE:
  Path to specific log file to analyze. If not specified, will use the most
  recent log file from $LOG_DIR

EXAMPLES:
  $0                                    # Analyze most recent log
  $0 --errors-only                     # Show only errors and critical issues
  $0 --performance --json              # Performance metrics in JSON format
  $0 --follow                          # Live monitoring mode
  $0 /path/to/specific.log             # Analyze specific log file
  $0 --recent --summary                # Quick summary of recent activity

ERROR PATTERNS DETECTED:
  • CUDA out of memory errors
  • Model loading failures  
  • API authentication issues
  • Network connection problems
  • GPU communication (NCCL) errors
  • Token limit exceeded errors
  • Process crashes and restarts

PERFORMANCE METRICS:
  • Request throughput (requests/second)
  • Token generation speed (tokens/second)
  • Response latency percentiles
  • Memory usage patterns
  • GPU utilization trends
  • Queue depths and wait times
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --errors-only)
            ERRORS_ONLY=true
            shift
            ;;
        --performance)
            PERFORMANCE_ONLY=true
            shift
            ;;
        --recent)
            RECENT_ONLY=true
            shift
            ;;
        --follow)
            FOLLOW_MODE=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --summary)
            SUMMARY_ONLY=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            LOG_FILE="$1"
            shift
            ;;
    esac
done

# Utility functions
log() {
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "$1"
    fi
}

debug_log() {
    if [[ -n "$DEBUG" && "$JSON_OUTPUT" == "false" ]]; then
        echo -e "${CYAN}[DEBUG] $1${NC}" >&2
    fi
}

# Find the most recent log file if none specified
find_recent_log() {
    if [[ -n "$LOG_FILE" && -f "$LOG_FILE" ]]; then
        echo "$LOG_FILE"
        return
    fi
    
    if [[ -d "$LOG_DIR" ]]; then
        local recent_log=$(find "$LOG_DIR" -name "vllm-*.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
        if [[ -n "$recent_log" ]]; then
            echo "$recent_log"
            return
        fi
    fi
    
    # Check for logs in current directory or common locations
    for location in "." "/root" "/var/log" "/tmp"; do
        local found_log=$(find "$location" -maxdepth 1 -name "vllm*.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
        if [[ -n "$found_log" ]]; then
            echo "$found_log"
            return
        fi
    done
    
    echo ""
}

# Parse log line for structured data
parse_log_line() {
    local line="$1"
    local timestamp=""
    local level=""
    local component=""
    local message=""
    
    # Extract timestamp (multiple formats supported)
    if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}[,\.][0-9]+) ]]; then
        timestamp="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^(INFO|DEBUG|WARNING|ERROR|CRITICAL)[[:space:]]+([0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
        level="${BASH_REMATCH[1]}"
        timestamp="${BASH_REMATCH[2]}"
    fi
    
    # Extract log level
    if [[ "$line" =~ (INFO|DEBUG|WARNING|ERROR|CRITICAL) ]]; then
        level="${BASH_REMATCH[1]}"
    fi
    
    # Extract component/module
    if [[ "$line" =~ \[([a-zA-Z0-9_\.]+)\] ]]; then
        component="${BASH_REMATCH[1]}"
    fi
    
    # Extract message (everything after level and component)
    message=$(echo "$line" | sed -E 's/^[^[:alpha:]]*[A-Z]+[[:space:]]*[0-9-]+[[:space:]]*[0-9:,\.]+[[:space:]]*(\[[^\]]+\])?[[:space:]]*//')
    
    echo "$timestamp|$level|$component|$message"
}

# Analyze error patterns
analyze_errors() {
    local log_content="$1"
    
    # Common error patterns
    local patterns=(
        "CUDA out of memory:OutOfMemoryError"
        "RuntimeError.*CUDA:CUDAError"
        "ConnectionError.*API:ConnectionIssue"
        "AuthenticationError.*401:AuthError"
        "Model.*not found:ModelMissing"
        "NCCL.*error:NCCLError"
        "Token.*limit.*exceeded:TokenLimit"
        "Process.*crashed:ProcessCrash"
        "Failed to load:LoadFailure"
        "Timeout.*request:RequestTimeout"
        "GPU.*not available:GPUUnavailable"
        "Memory.*allocation.*failed:MemoryAllocation"
    )
    
    while IFS= read -r line; do
        if [[ "$line" =~ (ERROR|CRITICAL|FATAL) ]]; then
            for pattern in "${patterns[@]}"; do
                local regex=$(echo "$pattern" | cut -d':' -f1)
                local category=$(echo "$pattern" | cut -d':' -f2)
                
                if [[ "$line" =~ $regex ]]; then
                    ERROR_COUNTS["$category"]=$((${ERROR_COUNTS["$category"]:-0} + 1))
                    
                    # Mark as critical if it's a severe error
                    if [[ "$line" =~ (CUDA out of memory|Process.*crashed|FATAL) ]]; then
                        CRITICAL_ISSUES+=("$line")
                    fi
                fi
            done
            
            # Count generic errors by component
            local parsed=$(parse_log_line "$line")
            local component=$(echo "$parsed" | cut -d'|' -f3)
            if [[ -n "$component" ]]; then
                ERROR_COUNTS["component_$component"]=$((${ERROR_COUNTS["component_$component"]:-0} + 1))
            fi
        fi
        
        if [[ "$line" =~ WARNING ]]; then
            local parsed=$(parse_log_line "$line")
            local component=$(echo "$parsed" | cut -d'|' -f3)
            if [[ -n "$component" ]]; then
                WARNING_COUNTS["component_$component"]=$((${WARNING_COUNTS["component_$component"]:-0} + 1))
            fi
        fi
    done <<< "$log_content"
}

# Analyze performance metrics
analyze_performance() {
    local log_content="$1"
    
    local request_times=()
    local token_counts=()
    local throughput_samples=()
    local memory_usage=()
    local gpu_usage=()
    
    while IFS= read -r line; do
        # Request completion time
        if [[ "$line" =~ completed.*in[[:space:]]+([0-9\.]+)[[:space:]]*s ]]; then
            request_times+=("${BASH_REMATCH[1]}")
        fi
        
        # Token generation metrics
        if [[ "$line" =~ ([0-9]+)[[:space:]]*tokens/s ]]; then
            throughput_samples+=("${BASH_REMATCH[1]}")
        fi
        
        # Token counts
        if [[ "$line" =~ generated[[:space:]]+([0-9]+)[[:space:]]*tokens ]]; then
            token_counts+=("${BASH_REMATCH[1]}")
        fi
        
        # Memory usage
        if [[ "$line" =~ GPU.*memory.*([0-9]+)%.*usage ]]; then
            gpu_usage+=("${BASH_REMATCH[1]}")
        fi
        
        if [[ "$line" =~ memory.*([0-9\.]+).*GiB ]]; then
            memory_usage+=("${BASH_REMATCH[1]}")
        fi
        
        # Request patterns
        if [[ "$line" =~ (POST|GET).*(/v1/[^[:space:]]+) ]]; then
            local endpoint="${BASH_REMATCH[2]}"
            REQUEST_PATTERNS["$endpoint"]=$((${REQUEST_PATTERNS["$endpoint"]:-0} + 1))
        fi
        
    done <<< "$log_content"
    
    # Calculate statistics
    if [[ ${#request_times[@]} -gt 0 ]]; then
        local total=0
        local count=${#request_times[@]}
        for time in "${request_times[@]}"; do
            total=$(echo "$total + $time" | bc 2>/dev/null || echo "$total")
        done
        local avg=$(echo "scale=3; $total / $count" | bc 2>/dev/null || echo "0")
        PERFORMANCE_METRICS["avg_request_time"]="$avg"
        PERFORMANCE_METRICS["total_requests"]="$count"
    fi
    
    if [[ ${#throughput_samples[@]} -gt 0 ]]; then
        local total=0
        for sample in "${throughput_samples[@]}"; do
            total=$((total + sample))
        done
        local avg=$((total / ${#throughput_samples[@]}))
        PERFORMANCE_METRICS["avg_throughput"]="$avg"
    fi
    
    if [[ ${#token_counts[@]} -gt 0 ]]; then
        local total=0
        for count in "${token_counts[@]}"; do
            total=$((total + count))
        done
        PERFORMANCE_METRICS["total_tokens_generated"]="$total"
    fi
}

# Analyze timeline patterns
analyze_timeline() {
    local log_content="$1"
    
    local current_hour=""
    local hourly_requests=0
    local hourly_errors=0
    
    while IFS= read -r line; do
        local parsed=$(parse_log_line "$line")
        local timestamp=$(echo "$parsed" | cut -d'|' -f1)
        local level=$(echo "$parsed" | cut -d'|' -f2)
        
        # Extract hour from timestamp
        local hour=""
        if [[ "$timestamp" =~ ([0-9]{2}:[0-9]{2}) ]]; then
            hour="${BASH_REMATCH[1]:0:2}"
        fi
        
        if [[ -n "$hour" && "$hour" != "$current_hour" ]]; then
            if [[ -n "$current_hour" ]]; then
                TIMELINE_DATA+=("$current_hour:$hourly_requests:$hourly_errors")
            fi
            current_hour="$hour"
            hourly_requests=0
            hourly_errors=0
        fi
        
        # Count requests and errors for this hour
        if [[ "$line" =~ (POST|GET) ]]; then
            ((hourly_requests++))
        fi
        
        if [[ "$level" =~ (ERROR|CRITICAL) ]]; then
            ((hourly_errors++))
        fi
        
    done <<< "$log_content"
    
    # Add final hour
    if [[ -n "$current_hour" ]]; then
        TIMELINE_DATA+=("$current_hour:$hourly_requests:$hourly_errors")
    fi
}

# Display results
display_summary() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        output_json
        return
    fi
    
    log "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════╗"
    log "║                       vLLM Log Analysis                         ║"
    log "║                    $(date '+%Y-%m-%d %H:%M:%S')                        ║"
    log "╚══════════════════════════════════════════════════════════════════╝${NC}"
    log ""
    
    # Error Analysis
    if [[ "$PERFORMANCE_ONLY" == "false" ]]; then
        log "${BOLD}${RED}=== Error Analysis ===${NC}"
        if [[ ${#ERROR_COUNTS[@]} -gt 0 ]]; then
            for error_type in $(printf '%s\n' "${!ERROR_COUNTS[@]}" | sort -V); do
                local count=${ERROR_COUNTS[$error_type]}
                local display_name=$(echo "$error_type" | sed 's/component_//' | sed 's/_/ /g')
                log "${RED}• $display_name: $count occurrences${NC}"
            done
        else
            log "${GREEN}✅ No errors detected${NC}"
        fi
        
        # Critical Issues
        if [[ ${#CRITICAL_ISSUES[@]} -gt 0 ]]; then
            log ""
            log "${BOLD}${RED}=== Critical Issues ===${NC}"
            for issue in "${CRITICAL_ISSUES[@]}"; do
                local short_issue=$(echo "$issue" | head -c 100)
                log "${RED}⚠️  $short_issue...${NC}"
            done
        fi
        
        log ""
    fi
    
    # Performance Analysis
    if [[ "$ERRORS_ONLY" == "false" ]]; then
        log "${BOLD}${GREEN}=== Performance Metrics ===${NC}"
        
        if [[ -n "${PERFORMANCE_METRICS[total_requests]}" ]]; then
            log "${GREEN}📊 Total Requests: ${PERFORMANCE_METRICS[total_requests]}${NC}"
        fi
        
        if [[ -n "${PERFORMANCE_METRICS[avg_request_time]}" ]]; then
            log "${GREEN}⏱️  Average Request Time: ${PERFORMANCE_METRICS[avg_request_time]}s${NC}"
        fi
        
        if [[ -n "${PERFORMANCE_METRICS[avg_throughput]}" ]]; then
            log "${GREEN}🚀 Average Throughput: ${PERFORMANCE_METRICS[avg_throughput]} tokens/s${NC}"
        fi
        
        if [[ -n "${PERFORMANCE_METRICS[total_tokens_generated]}" ]]; then
            log "${GREEN}🎯 Total Tokens Generated: ${PERFORMANCE_METRICS[total_tokens_generated]}${NC}"
        fi
        
        # Request patterns
        if [[ ${#REQUEST_PATTERNS[@]} -gt 0 ]]; then
            log ""
            log "${BOLD}${BLUE}=== API Endpoint Usage ===${NC}"
            for endpoint in $(printf '%s\n' "${!REQUEST_PATTERNS[@]}" | sort -nr -k2); do
                local count=${REQUEST_PATTERNS[$endpoint]}
                log "${BLUE}• $endpoint: $count requests${NC}"
            done
        fi
        
        log ""
    fi
    
    # Timeline Analysis (if not summary only)
    if [[ "$SUMMARY_ONLY" == "false" && ${#TIMELINE_DATA[@]} -gt 0 ]]; then
        log "${BOLD}${MAGENTA}=== Hourly Activity Timeline ===${NC}"
        log "${MAGENTA}Hour  | Requests | Errors${NC}"
        log "${MAGENTA}------|----------|-------${NC}"
        for entry in "${TIMELINE_DATA[@]}"; do
            local hour=$(echo "$entry" | cut -d':' -f1)
            local requests=$(echo "$entry" | cut -d':' -f2)
            local errors=$(echo "$entry" | cut -d':' -f3)
            printf "${MAGENTA}%5s | %8s | %6s${NC}\n" "$hour" "$requests" "$errors"
        done
        log ""
    fi
    
    # Recommendations
    if [[ "$SUMMARY_ONLY" == "false" ]]; then
        show_recommendations
    fi
}

# Show recommendations based on analysis
show_recommendations() {
    log "${BOLD}${YELLOW}=== Recommendations ===${NC}"
    
    local recommendations=()
    
    # Check for high error rates
    local total_errors=0
    for count in "${ERROR_COUNTS[@]}"; do
        total_errors=$((total_errors + count))
    done
    
    if [[ "$total_errors" -gt 10 ]]; then
        recommendations+=("High error rate detected ($total_errors errors). Check system resources and configuration.")
    fi
    
    # Check for CUDA memory issues
    if [[ -n "${ERROR_COUNTS[OutOfMemoryError]}" && "${ERROR_COUNTS[OutOfMemoryError]}" -gt 0 ]]; then
        recommendations+=("CUDA memory issues detected. Consider reducing max_model_len or batch size.")
    fi
    
    # Check for performance issues
    if [[ -n "${PERFORMANCE_METRICS[avg_request_time]}" ]]; then
        local avg_time=$(echo "${PERFORMANCE_METRICS[avg_request_time]}" | cut -d'.' -f1)
        if [[ "$avg_time" -gt 10 ]]; then
            recommendations+=("High average request time (${PERFORMANCE_METRICS[avg_request_time]}s). Consider optimizing GPU utilization.")
        fi
    fi
    
    # Check for low throughput
    if [[ -n "${PERFORMANCE_METRICS[avg_throughput]}" && "${PERFORMANCE_METRICS[avg_throughput]}" -lt 20 ]]; then
        recommendations+=("Low token throughput (${PERFORMANCE_METRICS[avg_throughput]} tokens/s). Check GPU memory utilization.")
    fi
    
    # Check for authentication issues
    if [[ -n "${ERROR_COUNTS[AuthError]}" && "${ERROR_COUNTS[AuthError]}" -gt 0 ]]; then
        recommendations+=("Authentication errors detected. Verify API key configuration.")
    fi
    
    # Generic recommendations if no specific issues
    if [[ ${#recommendations[@]} -eq 0 ]]; then
        recommendations+=(
            "System appears healthy. Continue monitoring for trends."
            "Consider setting up automated log rotation to manage disk space."
            "Monitor GPU memory usage during peak loads."
        )
    fi
    
    for rec in "${recommendations[@]}"; do
        log "${YELLOW}• $rec${NC}"
    done
    
    log ""
    log "${CYAN}For detailed troubleshooting, run:${NC}"
    log "${CYAN}  ./health-check.sh --verbose${NC}"
    log "${CYAN}  ./gpu-monitor.sh --realtime${NC}"
    log "${CYAN}  ./recovery-tools.sh --check-all${NC}"
}

# JSON output
output_json() {
    local error_json="{"
    local first=true
    for key in "${!ERROR_COUNTS[@]}"; do
        [[ "$first" == "false" ]] && error_json+=", "
        error_json+="\"$key\": ${ERROR_COUNTS[$key]}"
        first=false
    done
    error_json+="}"
    
    local perf_json="{"
    first=true
    for key in "${!PERFORMANCE_METRICS[@]}"; do
        [[ "$first" == "false" ]] && perf_json+=", "
        perf_json+="\"$key\": \"${PERFORMANCE_METRICS[$key]}\""
        first=false
    done
    perf_json+="}"
    
    local requests_json="{"
    first=true
    for key in "${!REQUEST_PATTERNS[@]}"; do
        [[ "$first" == "false" ]] && requests_json+=", "
        requests_json+="\"$key\": ${REQUEST_PATTERNS[$key]}"
        first=false
    done
    requests_json+="}"
    
    cat << EOF
{
  "timestamp": "$ANALYSIS_TIMESTAMP",
  "log_file": "$ACTUAL_LOG_FILE",
  "analysis": {
    "errors": $error_json,
    "performance": $perf_json,
    "requests": $requests_json,
    "critical_issues": $(printf '%s\n' "${CRITICAL_ISSUES[@]}" | jq -R . | jq -s .),
    "timeline": $(printf '%s\n' "${TIMELINE_DATA[@]}" | jq -R . | jq -s .)
  }
}
EOF
}

# Follow mode (live monitoring)
follow_logs() {
    local log_file="$1"
    
    if [[ ! -f "$log_file" ]]; then
        log "${RED}Error: Log file not found: $log_file${NC}"
        exit 1
    fi
    
    log "${CYAN}Following log file: $log_file${NC}"
    log "${CYAN}Press Ctrl+C to stop${NC}"
    log ""
    
    tail -f "$log_file" | while IFS= read -r line; do
        local parsed=$(parse_log_line "$line")
        local level=$(echo "$parsed" | cut -d'|' -f2)
        local component=$(echo "$parsed" | cut -d'|' -f3)
        local message=$(echo "$parsed" | cut -d'|' -f4)
        
        case "$level" in
            "ERROR"|"CRITICAL"|"FATAL")
                echo -e "${RED}[ERROR] ${component:+[$component] }$message${NC}"
                ;;
            "WARNING")
                echo -e "${YELLOW}[WARN]  ${component:+[$component] }$message${NC}"
                ;;
            "INFO")
                if [[ "$line" =~ (token|request|completion|performance) ]]; then
                    echo -e "${GREEN}[INFO]  ${component:+[$component] }$message${NC}"
                else
                    echo -e "${CYAN}[INFO]  ${component:+[$component] }$message${NC}"
                fi
                ;;
            *)
                echo "$line"
                ;;
        esac
    done
}

# Main execution
main() {
    # Find log file to analyze
    ACTUAL_LOG_FILE=$(find_recent_log)
    
    if [[ -z "$ACTUAL_LOG_FILE" ]]; then
        log "${RED}Error: No log files found in $LOG_DIR or common locations${NC}"
        log "${YELLOW}Searched locations:${NC}"
        log "  • $LOG_DIR"
        log "  • Current directory"
        log "  • /root"
        log "  • /var/log"
        log "  • /tmp"
        exit 1
    fi
    
    if [[ ! -r "$ACTUAL_LOG_FILE" ]]; then
        log "${RED}Error: Cannot read log file: $ACTUAL_LOG_FILE${NC}"
        exit 1
    fi
    
    # Handle follow mode
    if [[ "$FOLLOW_MODE" == "true" ]]; then
        follow_logs "$ACTUAL_LOG_FILE"
        return
    fi
    
    # Read log content
    local log_content
    if [[ "$RECENT_ONLY" == "true" ]]; then
        log_content=$(tail -n "$DEFAULT_LINES" "$ACTUAL_LOG_FILE")
        log "${BLUE}Analyzing recent $DEFAULT_LINES lines from: $ACTUAL_LOG_FILE${NC}"
    else
        log_content=$(cat "$ACTUAL_LOG_FILE")
        log "${BLUE}Analyzing full log file: $ACTUAL_LOG_FILE${NC}"
    fi
    
    # Perform analysis
    if [[ "$PERFORMANCE_ONLY" == "false" ]]; then
        analyze_errors "$log_content"
    fi
    
    if [[ "$ERRORS_ONLY" == "false" ]]; then
        analyze_performance "$log_content"
        analyze_timeline "$log_content"
    fi
    
    # Display results
    display_summary
}

# Run main function
main "$@"