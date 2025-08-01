#!/bin/bash

# GPU Performance Monitoring Tool for vLLM Workloads
# Real-time monitoring of GPU utilization, memory, temperature, and power
# Usage: ./gpu-monitor.sh [INTERVAL] [DURATION] [OUTPUT_FILE]

set -euo pipefail

# Configuration
MONITOR_INTERVAL="${1:-2}"      # seconds between samples
MONITOR_DURATION="${2:-300}"    # total monitoring duration in seconds
OUTPUT_FILE="${3:-gpu_monitor_$(date +%Y%m%d_%H%M%S).log}"
ALERT_THRESHOLD_TEMP=85         # Celsius
ALERT_THRESHOLD_MEMORY=90       # Percentage
ENABLE_ALERTS=${ENABLE_ALERTS:-false}
WEBHOOK_URL=${WEBHOOK_URL:-""}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check if nvidia-smi is available
if ! command -v nvidia-smi &> /dev/null; then
    echo -e "${RED}Error: nvidia-smi not found. This tool requires NVIDIA GPUs.${NC}"
    exit 1
fi

# Initialize output file with header
echo "timestamp,gpu_id,gpu_name,temp_c,util_gpu_pct,util_mem_pct,mem_used_mb,mem_total_mb,mem_util_pct,power_draw_w,power_limit_w,power_util_pct" > "$OUTPUT_FILE"

# Alert function
send_alert() {
    local title="$1"
    local message="$2"
    local severity="${3:-warning}"
    
    if [ "$ENABLE_ALERTS" = "true" ] && [ -n "$WEBHOOK_URL" ]; then
        curl -s -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"title\":\"GPU Alert: $title\",\"message\":\"$message\",\"severity\":\"$severity\",\"timestamp\":\"$(date -Iseconds)\"}" &
    fi
}

# Get GPU count
GPU_COUNT=$(nvidia-smi --list-gpus | wc -l)

echo -e "${BLUE}GPU Performance Monitor${NC}"
echo -e "Monitoring ${GREEN}${GPU_COUNT}${NC} GPU(s) for ${GREEN}${MONITOR_DURATION}${NC} seconds"
echo -e "Sample interval: ${GREEN}${MONITOR_INTERVAL}${NC} seconds"
echo -e "Output file: ${GREEN}${OUTPUT_FILE}${NC}"
echo -e "Alert thresholds: Temp > ${YELLOW}${ALERT_THRESHOLD_TEMP}°C${NC}, Memory > ${YELLOW}${ALERT_THRESHOLD_MEMORY}%${NC}"
echo ""

# Initialize variables for statistics
declare -A gpu_temp_max gpu_util_max gpu_mem_max gpu_power_max
declare -A gpu_temp_sum gpu_util_sum gpu_mem_sum gpu_power_sum
declare -A gpu_names
sample_count=0

# Main monitoring loop
start_time=$(date +%s)
end_time=$((start_time + MONITOR_DURATION))

echo -e "${CYAN}Starting monitoring...${NC}"
echo ""

while [ $(date +%s) -lt $end_time ]; do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    sample_count=$((sample_count + 1))
    
    # Clear previous lines for real-time display
    if [ $sample_count -gt 1 ]; then
        for ((i=0; i<GPU_COUNT+3; i++)); do
            echo -ne "\033[A\033[K"
        done
    fi
    
    echo -e "${BLUE}Sample ${sample_count} - ${timestamp}${NC}"
    echo "GPU | Name           | Temp  | GPU%  | MEM%  | Memory Usage    | Power Usage"
    echo "----+----------------+-------+-------+-------+-----------------+------------"
    
    # Query all GPUs at once for efficiency
    gpu_data=$(nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw,power.limit --format=csv,noheader,nounits)
    
    while IFS=',' read -r gpu_id name temp util_gpu util_mem mem_used mem_total power_draw power_limit; do
        # Clean up values (remove spaces)
        gpu_id=$(echo "$gpu_id" | tr -d ' ')
        name=$(echo "$name" | tr -d ' ' | cut -c1-14)
        temp=$(echo "$temp" | tr -d ' ')
        util_gpu=$(echo "$util_gpu" | tr -d ' ')
        util_mem=$(echo "$util_mem" | tr -d ' ')
        mem_used=$(echo "$mem_used" | tr -d ' ')
        mem_total=$(echo "$mem_total" | tr -d ' ')
        power_draw=$(echo "$power_draw" | tr -d ' ')
        power_limit=$(echo "$power_limit" | tr -d ' ')
        
        # Calculate percentages
        if [ "$mem_total" != "N/A" ] && [ "$mem_total" -gt 0 ]; then
            mem_util_pct=$(echo "scale=1; $mem_used * 100 / $mem_total" | bc -l)
        else
            mem_util_pct="N/A"
        fi
        
        if [ "$power_limit" != "N/A" ] && [ "$power_limit" != "0" ]; then
            power_util_pct=$(echo "scale=1; $power_draw * 100 / $power_limit" | bc -l)
        else
            power_util_pct="N/A"
        fi
        
        # Store for statistics
        gpu_names[$gpu_id]="$name"
        if [ "$temp" != "N/A" ]; then
            gpu_temp_max[$gpu_id]=$(echo "${gpu_temp_max[$gpu_id]:-0} $temp" | awk '{print ($1>$2)?$1:$2}')
            gpu_temp_sum[$gpu_id]=$(echo "${gpu_temp_sum[$gpu_id]:-0} + $temp" | bc -l)
        fi
        if [ "$util_gpu" != "N/A" ]; then
            gpu_util_max[$gpu_id]=$(echo "${gpu_util_max[$gpu_id]:-0} $util_gpu" | awk '{print ($1>$2)?$1:$2}')
            gpu_util_sum[$gpu_id]=$(echo "${gpu_util_sum[$gpu_id]:-0} + $util_gpu" | bc -l)
        fi
        if [ "$mem_util_pct" != "N/A" ]; then
            gpu_mem_max[$gpu_id]=$(echo "${gpu_mem_max[$gpu_id]:-0} $mem_util_pct" | bc -l | awk '{print ($1>$2)?$1:$2}' <<< "${gpu_mem_max[$gpu_id]:-0} $mem_util_pct")
            gpu_mem_sum[$gpu_id]=$(echo "${gpu_mem_sum[$gpu_id]:-0} + $mem_util_pct" | bc -l)
        fi
        if [ "$power_draw" != "N/A" ]; then
            gpu_power_max[$gpu_id]=$(echo "${gpu_power_max[$gpu_id]:-0} $power_draw" | awk '{print ($1>$2)?$1:$2}')
            gpu_power_sum[$gpu_id]=$(echo "${gpu_power_sum[$gpu_id]:-0} + $power_draw" | bc -l)
        fi
        
        # Color-code based on utilization and temperature
        temp_color="$GREEN"
        mem_color="$GREEN"
        
        if [ "$temp" != "N/A" ] && [ "$temp" -gt $ALERT_THRESHOLD_TEMP ]; then
            temp_color="$RED"
            send_alert "High Temperature" "GPU $gpu_id temperature: ${temp}°C (threshold: ${ALERT_THRESHOLD_TEMP}°C)" "critical"
        elif [ "$temp" != "N/A" ] && [ "$temp" -gt 75 ]; then
            temp_color="$YELLOW"
        fi
        
        if [ "$mem_util_pct" != "N/A" ] && (( $(echo "$mem_util_pct > $ALERT_THRESHOLD_MEMORY" | bc -l) )); then
            mem_color="$RED"
            send_alert "High Memory Usage" "GPU $gpu_id memory: ${mem_util_pct}% (threshold: ${ALERT_THRESHOLD_MEMORY}%)" "warning"
        elif [ "$mem_util_pct" != "N/A" ] && (( $(echo "$mem_util_pct > 80" | bc -l) )); then
            mem_color="$YELLOW"
        fi
        
        # Display current GPU status
        printf "%s%2s%s | %-14s | %s%5s°C%s | %5s%% | %s%5s%%%s | %6sMB/%6sMB | %6sW/%6sW\n" \
            "$CYAN" "$gpu_id" "$NC" "$name" \
            "$temp_color" "$temp" "$NC" "$util_gpu" \
            "$mem_color" "${mem_util_pct%.*}" "$NC" "$mem_used" "$mem_total" "$power_draw" "$power_limit"
        
        # Log to file
        echo "${timestamp},${gpu_id},${name},${temp},${util_gpu},${util_mem},${mem_used},${mem_total},${mem_util_pct},${power_draw},${power_limit},${power_util_pct}" >> "$OUTPUT_FILE"
        
    done <<< "$gpu_data"
    
    echo ""
    
    # Sleep for the specified interval
    sleep "$MONITOR_INTERVAL"
done

echo -e "${GREEN}Monitoring complete!${NC}"
echo ""

# Generate summary statistics
echo -e "${BLUE}=== MONITORING SUMMARY ===${NC}"
echo -e "Total samples: ${GREEN}${sample_count}${NC}"
echo -e "Duration: ${GREEN}${MONITOR_DURATION}${NC} seconds"
echo ""

for gpu_id in $(seq 0 $((GPU_COUNT-1))); do
    if [ -n "${gpu_names[$gpu_id]:-}" ]; then
        echo -e "${CYAN}GPU ${gpu_id} (${gpu_names[$gpu_id]}):${NC}"
        
        # Calculate averages
        temp_avg=$(echo "scale=1; ${gpu_temp_sum[$gpu_id]:-0} / $sample_count" | bc -l 2>/dev/null || echo "N/A")
        util_avg=$(echo "scale=1; ${gpu_util_sum[$gpu_id]:-0} / $sample_count" | bc -l 2>/dev/null || echo "N/A")
        mem_avg=$(echo "scale=1; ${gpu_mem_sum[$gpu_id]:-0} / $sample_count" | bc -l 2>/dev/null || echo "N/A")
        power_avg=$(echo "scale=1; ${gpu_power_sum[$gpu_id]:-0} / $sample_count" | bc -l 2>/dev/null || echo "N/A")
        
        echo "  Temperature:    Avg: ${temp_avg}°C,    Max: ${gpu_temp_max[$gpu_id]:-N/A}°C"
        echo "  GPU Util:       Avg: ${util_avg}%,     Max: ${gpu_util_max[$gpu_id]:-N/A}%"
        echo "  Memory Util:    Avg: ${mem_avg}%,      Max: ${gpu_mem_max[$gpu_id]:-N/A}%"
        echo "  Power Draw:     Avg: ${power_avg}W,     Max: ${gpu_power_max[$gpu_id]:-N/A}W"
        echo ""
    fi
done

echo -e "Detailed log saved to: ${GREEN}${OUTPUT_FILE}${NC}"

# Generate JSON summary
summary_file="${OUTPUT_FILE%.log}_summary.json"
cat > "$summary_file" << EOF
{
    "monitoring_summary": {
        "timestamp": "$(date -Iseconds)",
        "duration_seconds": $MONITOR_DURATION,
        "sample_interval_seconds": $MONITOR_INTERVAL,
        "total_samples": $sample_count,
        "gpu_count": $GPU_COUNT,
        "output_file": "$OUTPUT_FILE"
    },
    "gpu_statistics": [
EOF

# Add GPU statistics to JSON
for gpu_id in $(seq 0 $((GPU_COUNT-1))); do
    if [ -n "${gpu_names[$gpu_id]:-}" ]; then
        temp_avg=$(echo "scale=1; ${gpu_temp_sum[$gpu_id]:-0} / $sample_count" | bc -l 2>/dev/null || echo "0")
        util_avg=$(echo "scale=1; ${gpu_util_sum[$gpu_id]:-0} / $sample_count" | bc -l 2>/dev/null || echo "0")
        mem_avg=$(echo "scale=1; ${gpu_mem_sum[$gpu_id]:-0} / $sample_count" | bc -l 2>/dev/null || echo "0")
        power_avg=$(echo "scale=1; ${gpu_power_sum[$gpu_id]:-0} / $sample_count" | bc -l 2>/dev/null || echo "0")
        
        cat >> "$summary_file" << EOF
        {
            "gpu_id": $gpu_id,
            "name": "${gpu_names[$gpu_id]}",
            "temperature": {
                "average": $temp_avg,
                "maximum": ${gpu_temp_max[$gpu_id]:-0}
            },
            "utilization_gpu": {
                "average": $util_avg,
                "maximum": ${gpu_util_max[$gpu_id]:-0}
            },
            "utilization_memory": {
                "average": $mem_avg,
                "maximum": ${gpu_mem_max[$gpu_id]:-0}
            },
            "power_draw": {
                "average": $power_avg,
                "maximum": ${gpu_power_max[$gpu_id]:-0}
            }
        }
EOF
        if [ $gpu_id -lt $((GPU_COUNT-1)) ]; then
            echo "," >> "$summary_file"
        fi
    fi
done

cat >> "$summary_file" << EOF
    ]
}
EOF

echo -e "JSON summary saved to: ${GREEN}${summary_file}${NC}"