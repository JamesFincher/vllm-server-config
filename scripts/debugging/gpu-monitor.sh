#!/bin/bash
# GPU Monitoring and Resource Tracking Tool for vLLM Infrastructure
# Real-time and historical GPU monitoring with performance analysis
#
# Usage: ./gpu-monitor.sh [OPTIONS]
# Options:
#   --realtime        Show real-time GPU statistics (refreshes every 2 seconds)
#   --summary         Show current GPU status summary
#   --history         Show historical performance trends
#   --alerts          Check for and display GPU-related alerts
#   --json            Output results in JSON format
#   --log-file FILE   Log GPU metrics to specified file
#   --threshold-temp TEMP    Set temperature alert threshold (default: 85°C)
#   --threshold-mem PERCENT  Set memory usage alert threshold (default: 95%)
#   --help            Show this help message

set -e

# Configuration
LOG_FILE="${HOME}/.vllm-gpu-monitor.log"
ALERT_TEMP_THRESHOLD=85
ALERT_MEM_THRESHOLD=95
UPDATE_INTERVAL=2
HISTORY_LINES=100

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
REALTIME=false
SUMMARY=false
HISTORY=false
ALERTS_ONLY=false
JSON_OUTPUT=false
CUSTOM_LOG_FILE=""

# Data structures
declare -A GPU_DATA
declare -A ALERTS
declare -a HISTORICAL_DATA

show_help() {
    cat << EOF
GPU Monitoring and Resource Tracking Tool

Usage: $0 [OPTIONS]

OPTIONS:
  --realtime        Show real-time GPU statistics (refreshes every 2 seconds)
  --summary         Show current GPU status summary
  --history         Show historical performance trends
  --alerts          Check for and display GPU-related alerts
  --json            Output results in JSON format
  --log-file FILE   Log GPU metrics to specified file
  --threshold-temp TEMP    Set temperature alert threshold (default: ${ALERT_TEMP_THRESHOLD}°C)
  --threshold-mem PERCENT  Set memory usage alert threshold (default: ${ALERT_MEM_THRESHOLD}%)
  --help            Show this help message

MONITORING FEATURES:
  GPU Utilization:
    • GPU compute utilization percentage
    • Memory usage and availability
    • Temperature monitoring
    • Power consumption tracking
    • Clock speeds (core and memory)
    
  Performance Analysis:
    • Throughput calculations
    • Bottleneck identification
    • Resource efficiency metrics
    • Historical trend analysis
    
  Process Monitoring:
    • vLLM process GPU usage
    • Memory allocation per process
    • Process performance correlation
    • Resource contention detection
    
  Alert System:
    • Temperature threshold alerts
    • Memory usage warnings
    • Performance degradation detection
    • Hardware fault indicators

REAL-TIME DISPLAY:
  • Refreshing dashboard with color-coded status
  • Bar graphs for utilization and memory
  • Process list with GPU usage
  • Alert notifications

HISTORICAL ANALYSIS:
  • Performance trends over time
  • Peak usage identification
  • Efficiency pattern analysis
  • Capacity planning insights
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --realtime)
            REALTIME=true
            shift
            ;;
        --summary)
            SUMMARY=true
            shift
            ;;
        --history)
            HISTORY=true
            shift
            ;;
        --alerts)
            ALERTS_ONLY=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --log-file)
            CUSTOM_LOG_FILE="$2"
            shift 2
            ;;
        --threshold-temp)
            ALERT_TEMP_THRESHOLD="$2"
            shift 2
            ;;
        --threshold-mem)
            ALERT_MEM_THRESHOLD="$2"
            shift 2
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

# Use custom log file if specified
[[ -n "$CUSTOM_LOG_FILE" ]] && LOG_FILE="$CUSTOM_LOG_FILE"

# Utility functions
log() {
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "$1"
    fi
}

log_metric() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp|$1" >> "$LOG_FILE"
}

# Check if nvidia-smi is available
check_nvidia_tools() {
    if ! command -v nvidia-smi &> /dev/null; then
        log "${RED}Error: nvidia-smi not found. GPU monitoring requires NVIDIA drivers.${NC}"
        exit 1
    fi
    
    # Test nvidia-smi functionality
    if ! nvidia-smi >/dev/null 2>&1; then
        log "${RED}Error: nvidia-smi failed to execute. Check NVIDIA driver installation.${NC}"
        exit 1
    fi
}

# Collect GPU data
collect_gpu_data() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Get comprehensive GPU information
    local gpu_info=$(nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw,power.limit,clocks.current.graphics,clocks.current.memory,fan.speed --format=csv,noheader,nounits)
    
    # Get process information
    local process_info=$(nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader,nounits 2>/dev/null || echo "")
    
    # Clear previous data
    unset GPU_DATA
    declare -A GPU_DATA
    
    # Parse GPU data
    local gpu_index=0
    while IFS=, read -r index name temp util_gpu util_mem mem_used mem_total power_draw power_limit clock_gpu clock_mem fan_speed; do
        # Clean up values (remove spaces)
        index=$(echo "$index" | xargs)
        name=$(echo "$name" | xargs)
        temp=$(echo "$temp" | xargs)
        util_gpu=$(echo "$util_gpu" | xargs)
        util_mem=$(echo "$util_mem" | xargs)
        mem_used=$(echo "$mem_used" | xargs)
        mem_total=$(echo "$mem_total" | xargs)
        power_draw=$(echo "$power_draw" | xargs)
        power_limit=$(echo "$power_limit" | xargs)
        clock_gpu=$(echo "$clock_gpu" | xargs)
        clock_mem=$(echo "$clock_mem" | xargs)
        fan_speed=$(echo "$fan_speed" | xargs)
        
        # Calculate memory percentage
        local mem_percent=0
        if [[ "$mem_total" -gt 0 ]]; then
            mem_percent=$((mem_used * 100 / mem_total))
        fi
        
        # Store data
        GPU_DATA["gpu${index}_name"]="$name"
        GPU_DATA["gpu${index}_temp"]="$temp"
        GPU_DATA["gpu${index}_util_gpu"]="$util_gpu"
        GPU_DATA["gpu${index}_util_mem"]="$util_mem"
        GPU_DATA["gpu${index}_mem_used"]="$mem_used"
        GPU_DATA["gpu${index}_mem_total"]="$mem_total"
        GPU_DATA["gpu${index}_mem_percent"]="$mem_percent"
        GPU_DATA["gpu${index}_power_draw"]="$power_draw"
        GPU_DATA["gpu${index}_power_limit"]="$power_limit"
        GPU_DATA["gpu${index}_clock_gpu"]="$clock_gpu"
        GPU_DATA["gpu${index}_clock_mem"]="$clock_mem"
        GPU_DATA["gpu${index}_fan_speed"]="$fan_speed"
        
        ((gpu_index++))
    done <<< "$gpu_info"
    
    GPU_DATA["gpu_count"]="$gpu_index"
    GPU_DATA["timestamp"]="$timestamp"
    
    # Process GPU processes
    local process_count=0
    local total_process_memory=0
    
    if [[ -n "$process_info" ]]; then
        while IFS=, read -r pid process_name used_memory; do
            pid=$(echo "$pid" | xargs)
            process_name=$(echo "$process_name" | xargs)
            used_memory=$(echo "$used_memory" | xargs)
            
            GPU_DATA["process${process_count}_pid"]="$pid"
            GPU_DATA["process${process_count}_name"]="$process_name"
            GPU_DATA["process${process_count}_memory"]="$used_memory"
            
            total_process_memory=$((total_process_memory + used_memory))
            ((process_count++))
        done <<< "$process_info"
    fi
    
    GPU_DATA["process_count"]="$process_count"
    GPU_DATA["total_process_memory"]="$total_process_memory"
    
    # Log metrics if logging is enabled
    if [[ -n "$LOG_FILE" ]]; then
        local log_entry="$timestamp"
        for i in $(seq 0 $((gpu_index-1))); do
            log_entry+="|GPU$i:${GPU_DATA["gpu${i}_util_gpu"]}%:${GPU_DATA["gpu${i}_mem_percent"]}%:${GPU_DATA["gpu${i}_temp"]}C"
        done
        log_entry+="|PROCS:$process_count:${total_process_memory}MB"
        log_metric "$log_entry"
    fi
}

# Check for alerts
check_alerts() {
    unset ALERTS
    declare -A ALERTS
    local alert_count=0
    
    if [[ -z "${GPU_DATA[gpu_count]}" || "${GPU_DATA[gpu_count]}" -eq 0 ]]; then
        ALERTS["no_gpus"]="No GPUs detected or nvidia-smi failed"
        ((alert_count++))
        return
    fi
    
    # Check each GPU
    for i in $(seq 0 $((${GPU_DATA[gpu_count]}-1))); do
        local gpu_name="${GPU_DATA["gpu${i}_name"]}"
        local temp="${GPU_DATA["gpu${i}_temp"]}"
        local mem_percent="${GPU_DATA["gpu${i}_mem_percent"]}"
        local util_gpu="${GPU_DATA["gpu${i}_util_gpu"]}"
        local power_draw="${GPU_DATA["gpu${i}_power_draw"]}"
        local power_limit="${GPU_DATA["gpu${i}_power_limit"]}"
        
        # Temperature alerts
        if [[ "$temp" -gt "$ALERT_TEMP_THRESHOLD" ]]; then
            ALERTS["gpu${i}_temp"]="GPU $i temperature critical: ${temp}°C (threshold: ${ALERT_TEMP_THRESHOLD}°C)"
            ((alert_count++))
        elif [[ "$temp" -gt $((ALERT_TEMP_THRESHOLD - 10)) ]]; then
            ALERTS["gpu${i}_temp_warn"]="GPU $i temperature warning: ${temp}°C"
            ((alert_count++))
        fi
        
        # Memory alerts
        if [[ "$mem_percent" -gt "$ALERT_MEM_THRESHOLD" ]]; then
            ALERTS["gpu${i}_memory"]="GPU $i memory critical: ${mem_percent}% (${GPU_DATA["gpu${i}_mem_used"]}MB/${GPU_DATA["gpu${i}_mem_total"]}MB)"
            ((alert_count++))
        elif [[ "$mem_percent" -gt $((ALERT_MEM_THRESHOLD - 10)) ]]; then
            ALERTS["gpu${i}_memory_warn"]="GPU $i memory warning: ${mem_percent}%"
            ((alert_count++))
        fi
        
        # Low utilization alert (might indicate issues)
        if [[ "$util_gpu" -lt 5 && "${GPU_DATA[process_count]}" -gt 0 ]]; then
            ALERTS["gpu${i}_low_util"]="GPU $i low utilization: ${util_gpu}% despite active processes"
            ((alert_count++))
        fi
        
        # Power limit alerts
        if [[ "$power_draw" -gt 0 && "$power_limit" -gt 0 ]]; then
            local power_percent=$((power_draw * 100 / power_limit))
            if [[ "$power_percent" -gt 90 ]]; then
                ALERTS["gpu${i}_power"]="GPU $i near power limit: ${power_draw}W/${power_limit}W (${power_percent}%)"
                ((alert_count++))
            fi
        fi
    done
    
    # Process-related alerts
    if [[ "${GPU_DATA[process_count]}" -eq 0 ]]; then
        ALERTS["no_processes"]="No GPU processes detected - vLLM may not be running"
        ((alert_count++))
    fi
    
    # Check for memory leaks (total process memory vs available memory)
    local total_available=0
    for i in $(seq 0 $((${GPU_DATA[gpu_count]}-1))); do
        total_available=$((total_available + ${GPU_DATA["gpu${i}_mem_total"]}))
    done
    
    local process_memory=${GPU_DATA[total_process_memory]}
    if [[ "$process_memory" -gt 0 && "$total_available" -gt 0 ]]; then
        local process_memory_percent=$((process_memory * 100 / total_available))
        if [[ "$process_memory_percent" -gt 85 ]]; then
            ALERTS["high_memory_usage"]="High total GPU memory usage: ${process_memory}MB of ${total_available}MB (${process_memory_percent}%)"
            ((alert_count++))
        fi
    fi
    
    return $alert_count
}

# Display functions
show_gpu_bar() {
    local value="$1"
    local max_value="$2"
    local width="$3"
    local color="$4"
    
    local filled=$((value * width / max_value))
    local empty=$((width - filled))
    
    printf "${color}"
    for i in $(seq 1 $filled); do printf "█"; done
    printf "${NC}"
    for i in $(seq 1 $empty); do printf "░"; done
}

display_summary() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        output_json
        return
    fi
    
    collect_gpu_data
    check_alerts
    local alert_count=$?
    
    log "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════╗"
    log "║                       GPU Status Summary                        ║"
    log "║                    $(date '+%Y-%m-%d %H:%M:%S')                        ║"
    log "╚══════════════════════════════════════════════════════════════════╝${NC}"
    log ""
    
    if [[ "${GPU_DATA[gpu_count]}" -eq 0 ]]; then
        log "${RED}No GPUs detected or nvidia-smi failed${NC}"
        return
    fi
    
    # Display each GPU
    for i in $(seq 0 $((${GPU_DATA[gpu_count]}-1))); do
        local name="${GPU_DATA["gpu${i}_name"]}"
        local temp="${GPU_DATA["gpu${i}_temp"]}"
        local util_gpu="${GPU_DATA["gpu${i}_util_gpu"]}"
        local mem_percent="${GPU_DATA["gpu${i}_mem_percent"]}"
        local mem_used="${GPU_DATA["gpu${i}_mem_used"]}"
        local mem_total="${GPU_DATA["gpu${i}_mem_total"]}"
        local power_draw="${GPU_DATA["gpu${i}_power_draw"]}"
        local power_limit="${GPU_DATA["gpu${i}_power_limit"]}"
        
        # Color coding based on temperature and usage
        local temp_color="$GREEN"
        [[ "$temp" -gt $((ALERT_TEMP_THRESHOLD - 10)) ]] && temp_color="$YELLOW"
        [[ "$temp" -gt "$ALERT_TEMP_THRESHOLD" ]] && temp_color="$RED"
        
        local mem_color="$GREEN"
        [[ "$mem_percent" -gt $((ALERT_MEM_THRESHOLD - 10)) ]] && mem_color="$YELLOW"
        [[ "$mem_percent" -gt "$ALERT_MEM_THRESHOLD" ]] && mem_color="$RED"
        
        log "${BOLD}GPU $i: $name${NC}"
        log "  Temperature: ${temp_color}${temp}°C${NC}"
        log "  GPU Usage:   $(show_gpu_bar "$util_gpu" 100 20 "$BLUE") ${util_gpu}%"
        log "  Memory:      $(show_gpu_bar "$mem_percent" 100 20 "$mem_color") ${mem_percent}% (${mem_used}MB/${mem_total}MB)"
        
        if [[ "$power_draw" != "N/A" && "$power_limit" != "N/A" ]]; then
            local power_percent=$((power_draw * 100 / power_limit))
            local power_color="$GREEN"
            [[ "$power_percent" -gt 80 ]] && power_color="$YELLOW"
            [[ "$power_percent" -gt 90 ]] && power_color="$RED"
            log "  Power:       $(show_gpu_bar "$power_draw" "$power_limit" 20 "$power_color") ${power_draw}W/${power_limit}W"
        fi
        
        log ""
    done
    
    # Display processes
    if [[ "${GPU_DATA[process_count]}" -gt 0 ]]; then
        log "${BOLD}${BLUE}GPU Processes:${NC}"
        log "PID      | Process Name          | GPU Memory"
        log "---------|----------------------|------------"
        
        for i in $(seq 0 $((${GPU_DATA[process_count]}-1))); do
            local pid="${GPU_DATA["process${i}_pid"]}"
            local name="${GPU_DATA["process${i}_name"]}"
            local memory="${GPU_DATA["process${i}_memory"]}"
            
            # Highlight vLLM processes
            local name_color="$NC"
            [[ "$name" =~ vllm ]] && name_color="$GREEN"
            
            printf "%-8s | ${name_color}%-20s${NC} | %8s MB\n" "$pid" "$name" "$memory"
        done
        log ""
    else
        log "${YELLOW}No GPU processes detected${NC}"
        log ""
    fi
    
    # Display alerts
    if [[ "$alert_count" -gt 0 ]]; then
        log "${BOLD}${RED}Active Alerts ($alert_count):${NC}"
        for alert_key in "${!ALERTS[@]}"; do
            log "  ${RED}⚠️  ${ALERTS[$alert_key]}${NC}"
        done
        log ""
    else
        log "${GREEN}✅ No alerts - All GPUs operating normally${NC}"
        log ""
    fi
    
    # Quick stats
    local total_memory_used=0
    local total_memory_available=0
    local avg_temp=0
    local avg_util=0
    
    for i in $(seq 0 $((${GPU_DATA[gpu_count]}-1))); do
        total_memory_used=$((total_memory_used + ${GPU_DATA["gpu${i}_mem_used"]}))
        total_memory_available=$((total_memory_available + ${GPU_DATA["gpu${i}_mem_total"]}))
        avg_temp=$((avg_temp + ${GPU_DATA["gpu${i}_temp"]}))
        avg_util=$((avg_util + ${GPU_DATA["gpu${i}_util_gpu"]}))
    done
    
    if [[ "${GPU_DATA[gpu_count]}" -gt 0 ]]; then
        avg_temp=$((avg_temp / ${GPU_DATA[gpu_count]}))
        avg_util=$((avg_util / ${GPU_DATA[gpu_count]}))
        local total_mem_percent=$((total_memory_used * 100 / total_memory_available))
        
        log "${BOLD}${MAGENTA}Overall Statistics:${NC}"
        log "  Average Temperature: ${avg_temp}°C"
        log "  Average GPU Utilization: ${avg_util}%"
        log "  Total Memory Usage: ${total_memory_used}MB / ${total_memory_available}MB (${total_mem_percent}%)"
        log "  Active Processes: ${GPU_DATA[process_count]}"
    fi
}

display_realtime() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        log "${RED}Error: Real-time mode not compatible with JSON output${NC}"
        exit 1
    fi
    
    log "${CYAN}Real-time GPU monitoring (Press Ctrl+C to stop)${NC}"
    log "${CYAN}Update interval: ${UPDATE_INTERVAL} seconds${NC}"
    log ""
    
    # Hide cursor
    tput civis
    
    # Cleanup function to restore cursor
    cleanup_realtime() {
        tput cnorm
        exit 0
    }
    trap cleanup_realtime EXIT INT TERM
    
    local iteration=1
    while true; do
        # Clear screen and move to top
        clear
        
        log "${BOLD}${CYAN}GPU Real-time Monitor - Iteration $iteration - $(date '+%H:%M:%S')${NC}"
        log "${CYAN}$(printf '═%.0s' {1..70})${NC}"
        log ""
        
        collect_gpu_data
        check_alerts
        local alert_count=$?
        
        if [[ "${GPU_DATA[gpu_count]}" -eq 0 ]]; then
            log "${RED}No GPUs detected${NC}"
            sleep "$UPDATE_INTERVAL"
            continue
        fi
        
        # Display compact GPU info
        for i in $(seq 0 $((${GPU_DATA[gpu_count]}-1))); do
            local name="${GPU_DATA["gpu${i}_name"]}"
            local temp="${GPU_DATA["gpu${i}_temp"]}"
            local util_gpu="${GPU_DATA["gpu${i}_util_gpu"]}"
            local mem_percent="${GPU_DATA["gpu${i}_mem_percent"]}"
            local mem_used="${GPU_DATA["gpu${i}_mem_used"]}"
            local mem_total="${GPU_DATA["gpu${i}_mem_total"]}"
            
            # Color coding
            local status_color="$GREEN"
            [[ "$temp" -gt $((ALERT_TEMP_THRESHOLD - 10)) || "$mem_percent" -gt $((ALERT_MEM_THRESHOLD - 10)) ]] && status_color="$YELLOW"
            [[ "$temp" -gt "$ALERT_TEMP_THRESHOLD" || "$mem_percent" -gt "$ALERT_MEM_THRESHOLD" ]] && status_color="$RED"
            
            printf "${BOLD}GPU %d${NC} %-20s " "$i" "$name"
            printf "${status_color}%3d°C${NC} " "$temp"
            printf "GPU:%s %3d%% " "$(show_gpu_bar "$util_gpu" 100 10 "$BLUE")" "$util_gpu"
            printf "MEM:%s %3d%% " "$(show_gpu_bar "$mem_percent" 100 10 "$status_color")" "$mem_percent"
            printf "(%dMB/%dMB)\n" "$mem_used" "$mem_total"
        done
        
        log ""
        
        # Show processes
        if [[ "${GPU_DATA[process_count]}" -gt 0 ]]; then
            log "${BOLD}Active Processes:${NC}"
            for i in $(seq 0 $((${GPU_DATA[process_count]}-1))); do
                local pid="${GPU_DATA["process${i}_pid"]}"
                local name="${GPU_DATA["process${i}_name"]}"
                local memory="${GPU_DATA["process${i}_memory"]}"
                
                local name_color="$NC"
                [[ "$name" =~ vllm ]] && name_color="$GREEN"
                
                printf "  PID %-6s ${name_color}%-15s${NC} %6s MB\n" "$pid" "$name" "$memory"
            done
        else
            log "${YELLOW}No GPU processes${NC}"
        fi
        
        log ""
        
        # Show alerts
        if [[ "$alert_count" -gt 0 ]]; then
            log "${BOLD}${RED}ALERTS:${NC}"
            for alert_key in "${!ALERTS[@]}"; do
                log "  ${RED}⚠️  ${ALERTS[$alert_key]}${NC}"
            done
        else
            log "${GREEN}Status: All systems normal${NC}"
        fi
        
        log ""
        log "${CYAN}Next update in ${UPDATE_INTERVAL}s... (Ctrl+C to stop)${NC}"
        
        ((iteration++))
        sleep "$UPDATE_INTERVAL"
    done
}

display_history() {
    if [[ ! -f "$LOG_FILE" ]]; then
        log "${YELLOW}No historical data found. Log file: $LOG_FILE${NC}"
        log "${YELLOW}Run the monitor for a while to collect historical data.${NC}"
        return
    fi
    
    log "${BOLD}${MAGENTA}GPU Performance History${NC}"
    log "Reading from: $LOG_FILE"
    log ""
    
    # Read recent history
    local history_data=$(tail -n "$HISTORY_LINES" "$LOG_FILE" 2>/dev/null || echo "")
    
    if [[ -z "$history_data" ]]; then
        log "${YELLOW}No historical data available${NC}"
        return
    fi
    
    # Analyze patterns
    local timestamps=()
    local gpu_utils=()
    local gpu_temps=()
    local memory_usage=()
    
    while IFS='|' read -r timestamp data; do
        timestamps+=("$timestamp")
        
        # Extract GPU data (simplified parsing)
        local avg_util=0
        local avg_temp=0
        local avg_mem=0
        local gpu_count=0
        
        # Parse GPU data from log entry
        if [[ "$data" =~ GPU([0-9]+):([0-9]+)%:([0-9]+)%:([0-9]+)C ]]; then
            for gpu_entry in $(echo "$data" | grep -o "GPU[0-9]*:[0-9]*%:[0-9]*%:[0-9]*C"); do
                if [[ "$gpu_entry" =~ GPU[0-9]*:([0-9]+)%:([0-9]+)%:([0-9]+)C ]]; then
                    avg_util=$((avg_util + ${BASH_REMATCH[1]}))
                    avg_mem=$((avg_mem + ${BASH_REMATCH[2]}))
                    avg_temp=$((avg_temp + ${BASH_REMATCH[3]}))
                    ((gpu_count++))
                fi
            done
            
            if [[ "$gpu_count" -gt 0 ]]; then
                avg_util=$((avg_util / gpu_count))
                avg_mem=$((avg_mem / gpu_count))
                avg_temp=$((avg_temp / gpu_count))
            fi
        fi
        
        gpu_utils+=("$avg_util")
        gpu_temps+=("$avg_temp")
        memory_usage+=("$avg_mem")
        
    done <<< "$history_data"
    
    # Calculate statistics
    local total_util=0
    local max_util=0
    local min_util=100
    local total_temp=0
    local max_temp=0
    local total_mem=0
    local max_mem=0
    
    for i in "${!gpu_utils[@]}"; do
        local util=${gpu_utils[i]}
        local temp=${gpu_temps[i]}
        local mem=${memory_usage[i]}
        
        [[ "$util" -gt 0 ]] && {
            total_util=$((total_util + util))
            [[ "$util" -gt "$max_util" ]] && max_util="$util"
            [[ "$util" -lt "$min_util" ]] && min_util="$util"
        }
        
        [[ "$temp" -gt 0 ]] && {
            total_temp=$((total_temp + temp))
            [[ "$temp" -gt "$max_temp" ]] && max_temp="$temp"
        }
        
        [[ "$mem" -gt 0 ]] && {
            total_mem=$((total_mem + mem))
            [[ "$mem" -gt "$max_mem" ]] && max_mem="$mem"
        }
    done
    
    local data_points=${#gpu_utils[@]}
    if [[ "$data_points" -gt 0 ]]; then
        local avg_util=$((total_util / data_points))
        local avg_temp=$((total_temp / data_points))
        local avg_mem=$((total_mem / data_points))
        
        log "${BOLD}Performance Statistics (last $data_points data points):${NC}"
        log "  GPU Utilization:"
        log "    Average: ${avg_util}%"
        log "    Maximum: ${max_util}%"
        log "    Minimum: ${min_util}%"
        log ""
        log "  Temperature:"
        log "    Average: ${avg_temp}°C"
        log "    Maximum: ${max_temp}°C"
        log ""
        log "  Memory Usage:"
        log "    Average: ${avg_mem}%"
        log "    Maximum: ${max_mem}%"
        log ""
        
        # Show recent trend
        log "${BOLD}Recent Trend (last 10 entries):${NC}"
        log "Time     | Util | Temp | Memory"
        log "---------|------|------|-------"
        
        local start_idx=$((data_points - 10))
        [[ "$start_idx" -lt 0 ]] && start_idx=0
        
        for i in $(seq $start_idx $((data_points - 1))); do
            local time_part=$(echo "${timestamps[i]}" | cut -d' ' -f2 | cut -d':' -f1-2)
            printf "%-8s | %4s | %4s | %6s\n" "$time_part" "${gpu_utils[i]}%" "${gpu_temps[i]}°C" "${memory_usage[i]}%"
        done
    else
        log "${YELLOW}Insufficient data for analysis${NC}"
    fi
}

display_alerts() {
    collect_gpu_data
    check_alerts
    local alert_count=$?
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        local alert_json="{"
        local first=true
        for key in "${!ALERTS[@]}"; do
            [[ "$first" == "false" ]] && alert_json+=", "
            alert_json+="\"$key\": \"${ALERTS[$key]}\""
            first=false
        done
        alert_json+="}"
        
        echo "{"
        echo "  \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
        echo "  \"alert_count\": $alert_count,"
        echo "  \"alerts\": $alert_json"
        echo "}"
        return
    fi
    
    log "${BOLD}${YELLOW}GPU Alert Status${NC}"
    log "$(date '+%Y-%m-%d %H:%M:%S')"
    log ""
    
    if [[ "$alert_count" -eq 0 ]]; then
        log "${GREEN}✅ No alerts - All GPUs operating normally${NC}"
        log ""
        log "Current thresholds:"
        log "  Temperature: ${ALERT_TEMP_THRESHOLD}°C"
        log "  Memory usage: ${ALERT_MEM_THRESHOLD}%"
    else
        log "${RED}⚠️  $alert_count active alerts:${NC}"
        log ""
        
        for alert_key in "${!ALERTS[@]}"; do
            log "  ${RED}• ${ALERTS[$alert_key]}${NC}"
        done
        
        log ""
        log "${YELLOW}Recommended actions:${NC}"
        log "  • Check vLLM server logs for errors"
        log "  • Monitor GPU temperature and cooling"
        log "  • Consider reducing model parameters or batch size"
        log "  • Verify GPU memory allocation is optimal"
    fi
}

# JSON output
output_json() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    echo "{"
    echo "  \"timestamp\": \"$timestamp\","
    echo "  \"gpu_count\": ${GPU_DATA[gpu_count]:-0},"
    echo "  \"gpus\": ["
    
    local first_gpu=true
    for i in $(seq 0 $((${GPU_DATA[gpu_count]:-0}-1))); do
        [[ "$first_gpu" == "false" ]] && echo ","
        echo "    {"
        echo "      \"index\": $i,"
        echo "      \"name\": \"${GPU_DATA["gpu${i}_name"]}\","
        echo "      \"temperature\": ${GPU_DATA["gpu${i}_temp"]:-0},"
        echo "      \"utilization_gpu\": ${GPU_DATA["gpu${i}_util_gpu"]:-0},"
        echo "      \"utilization_memory\": ${GPU_DATA["gpu${i}_util_mem"]:-0},"
        echo "      \"memory_used\": ${GPU_DATA["gpu${i}_mem_used"]:-0},"
        echo "      \"memory_total\": ${GPU_DATA["gpu${i}_mem_total"]:-0},"
        echo "      \"memory_percent\": ${GPU_DATA["gpu${i}_mem_percent"]:-0},"
        echo "      \"power_draw\": ${GPU_DATA["gpu${i}_power_draw"]:-0},"
        echo "      \"power_limit\": ${GPU_DATA["gpu${i}_power_limit"]:-0}"
        echo -n "    }"
        first_gpu=false
    done
    
    echo ""
    echo "  ],"
    echo "  \"processes\": ["
    
    local first_proc=true
    for i in $(seq 0 $((${GPU_DATA[process_count]:-0}-1))); do
        [[ "$first_proc" == "false" ]] && echo ","
        echo "    {"
        echo "      \"pid\": ${GPU_DATA["process${i}_pid"]:-0},"
        echo "      \"name\": \"${GPU_DATA["process${i}_name"]}\","
        echo "      \"memory\": ${GPU_DATA["process${i}_memory"]:-0}"
        echo -n "    }"
        first_proc=false
    done
    
    echo ""
    echo "  ],"
    
    # Include alerts
    check_alerts
    local alert_json="{"
    local first_alert=true
    for key in "${!ALERTS[@]}"; do
        [[ "$first_alert" == "false" ]] && alert_json+=", "
        alert_json+="\"$key\": \"${ALERTS[$key]}\""
        first_alert=false
    done
    alert_json+="}"
    
    echo "  \"alerts\": $alert_json"
    echo "}"
}

# Main execution
main() {
    # Check prerequisites
    check_nvidia_tools
    
    # Default to summary if no specific mode chosen
    if [[ "$REALTIME" == "false" && "$HISTORY" == "false" && "$ALERTS_ONLY" == "false" ]]; then
        SUMMARY=true
    fi
    
    # Execute based on flags
    if [[ "$REALTIME" == "true" ]]; then
        display_realtime
    elif [[ "$HISTORY" == "true" ]]; then
        display_history
    elif [[ "$ALERTS_ONLY" == "true" ]]; then
        display_alerts
    elif [[ "$SUMMARY" == "true" ]]; then
        display_summary
    fi
}

# Cleanup function
cleanup() {
    # Restore cursor if in realtime mode
    tput cnorm 2>/dev/null || true
}
trap cleanup EXIT

# Run main function
main "$@"