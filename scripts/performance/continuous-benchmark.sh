#!/bin/bash

# Continuous Performance Benchmarking Automation
# Runs automated benchmarks at regular intervals with trend analysis
# Usage: ./continuous-benchmark.sh [CONFIG_FILE]

set -euo pipefail

# Default configuration
DEFAULT_CONFIG=$(cat << 'EOF'
{
    "api_key": "qwen3-secret-key",
    "base_url": "http://localhost:8000/v1",
    "benchmark_interval_minutes": 60,
    "retention_days": 30,
    "baseline_tps": 75.0,
    "regression_threshold": 0.15,
    "alerts": {
        "enabled": true,
        "webhook_url": "",
        "slack_webhook": "",
        "email_smtp": {
            "enabled": false,
            "server": "smtp.gmail.com",
            "port": 587,
            "username": "",
            "password": "",
            "to_addresses": []
        }
    },
    "benchmarks": {
        "quick_test": {
            "enabled": true,
            "frequency": "every_run",
            "description": "Quick 100-token test for basic health check"
        },
        "comprehensive_test": {
            "enabled": true,
            "frequency": "hourly",
            "description": "Full benchmark suite"
        },
        "load_test": {
            "enabled": true,
            "frequency": "daily",
            "description": "Realistic load test",
            "profile": "realistic"
        },
        "stress_test": {
            "enabled": false,
            "frequency": "weekly",
            "description": "High-load stress test",
            "profile": "stress"
        }
    }
}
EOF
)

# Configuration
CONFIG_FILE="${1:-continuous_benchmark_config.json}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/continuous_benchmark_data"
LOCK_FILE="${DATA_DIR}/continuous_benchmark.lock"
LOG_FILE="${DATA_DIR}/continuous_benchmark.log"
TRENDS_FILE="${DATA_DIR}/performance_trends.json"
PID_FILE="${DATA_DIR}/continuous_benchmark.pid"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Ensure data directory exists
mkdir -p "$DATA_DIR"

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Load configuration
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log "Configuration file not found. Creating default configuration: $CONFIG_FILE"
        echo "$DEFAULT_CONFIG" > "$CONFIG_FILE"
    fi
    
    if ! jq . "$CONFIG_FILE" > /dev/null 2>&1; then
        error "Invalid JSON in configuration file: $CONFIG_FILE"
        exit 1
    fi
    
    log "Configuration loaded from: $CONFIG_FILE"
}

# Lock mechanism to prevent multiple instances
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            error "Another instance is already running (PID: $lock_pid)"
            exit 1
        else
            warning "Stale lock file found, removing..."
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo $$ > "$LOCK_FILE"
    echo $$ > "$PID_FILE"
    log "Lock acquired (PID: $$)"
}

# Release lock
release_lock() {
    rm -f "$LOCK_FILE" "$PID_FILE"
    log "Lock released"
}

# Send alert notifications
send_alert() {
    local title="$1"
    local message="$2"
    local severity="${3:-warning}"
    
    local alerts_enabled=$(jq -r '.alerts.enabled' "$CONFIG_FILE")
    
    if [ "$alerts_enabled" = "true" ]; then
        local webhook_url=$(jq -r '.alerts.webhook_url' "$CONFIG_FILE")
        local slack_webhook=$(jq -r '.alerts.slack_webhook' "$CONFIG_FILE")
        
        # Generic webhook
        if [ -n "$webhook_url" ] && [ "$webhook_url" != "null" ]; then
            curl -s -X POST "$webhook_url" \
                -H "Content-Type: application/json" \
                -d "{\"title\":\"$title\",\"message\":\"$message\",\"severity\":\"$severity\",\"timestamp\":\"$(date -Iseconds)\",\"source\":\"continuous-benchmark\"}" &
        fi
        
        # Slack webhook
        if [ -n "$slack_webhook" ] && [ "$slack_webhook" != "null" ]; then
            local slack_emoji=""
            case "$severity" in
                "critical") slack_emoji="🚨" ;;
                "warning") slack_emoji="⚠️" ;;
                "info") slack_emoji="ℹ️" ;;
                *) slack_emoji="📊" ;;
            esac
            
            curl -s -X POST "$slack_webhook" \
                -H "Content-Type: application/json" \
                -d "{\"text\":\"${slack_emoji} *${title}*\n\`\`\`${message}\`\`\`\"}" &
        fi
        
        # Email (if configured)
        local email_enabled=$(jq -r '.alerts.email_smtp.enabled' "$CONFIG_FILE")
        if [ "$email_enabled" = "true" ]; then
            send_email_alert "$title" "$message" "$severity" &
        fi
    fi
}

# Send email alert (requires ssmtp or similar)
send_email_alert() {
    local title="$1"
    local message="$2"
    local severity="$3"
    
    local smtp_server=$(jq -r '.alerts.email_smtp.server' "$CONFIG_FILE")
    local smtp_port=$(jq -r '.alerts.email_smtp.port' "$CONFIG_FILE")
    local smtp_username=$(jq -r '.alerts.email_smtp.username' "$CONFIG_FILE")
    local smtp_password=$(jq -r '.alerts.email_smtp.password' "$CONFIG_FILE")
    local to_addresses=$(jq -r '.alerts.email_smtp.to_addresses[]' "$CONFIG_FILE")
    
    # This is a simplified email implementation
    # In production, you'd want to use a proper SMTP client
    if command -v mail &> /dev/null && [ -n "$to_addresses" ]; then
        for address in $to_addresses; do
            echo -e "Subject: [vLLM Performance] $title\n\n$message\n\nTimestamp: $(date)\nSeverity: $severity" | mail "$address" 2>/dev/null || true
        done
    fi
}

# Run quick health check
run_quick_test() {
    local api_key=$(jq -r '.api_key' "$CONFIG_FILE")
    local base_url=$(jq -r '.base_url' "$CONFIG_FILE")
    
    log "Running quick health check..."
    
    # Simple 100-token test
    local payload='{
        "model": "qwen3",
        "messages": [{"role": "user", "content": "Write a brief explanation of REST APIs in about 50 words."}],
        "max_tokens": 100,
        "temperature": 0.3
    }'
    
    local start_time=$(date +%s.%3N)
    local response=$(curl -s --max-time 30 "${base_url}/chat/completions" \
        -H "Authorization: Bearer ${api_key}" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null)
    local end_time=$(date +%s.%3N)
    
    if echo "$response" | jq -e '.choices[0].message.content' &> /dev/null; then
        local duration=$(echo "$end_time - $start_time" | bc -l)
        local tokens_generated=$(echo "$response" | jq -r '.usage.completion_tokens // 0')
        local tokens_per_second=0
        
        if (( $(echo "$duration > 0" | bc -l) )) && (( tokens_generated > 0 )); then
            tokens_per_second=$(echo "scale=2; $tokens_generated / $duration" | bc -l)
        fi
        
        success "Quick test passed: ${duration}s, ${tokens_generated} tokens, ${tokens_per_second} tok/s"
        
        # Record result
        local result=$(cat << EOF
{
    "timestamp": "$(date -Iseconds)",
    "test_type": "quick_test",
    "duration_seconds": $duration,
    "tokens_generated": $tokens_generated,
    "tokens_per_second": $tokens_per_second,
    "success": true
}
EOF
)
        record_benchmark_result "$result"
        return 0
    else
        error "Quick test failed: $(echo "$response" | jq -r '.error.message // "Unknown error"')"
        
        local result=$(cat << EOF
{
    "timestamp": "$(date -Iseconds)",
    "test_type": "quick_test",
    "success": false,
    "error": "$(echo "$response" | jq -r '.error.message // "Unknown error"')"
}
EOF
)
        record_benchmark_result "$result"
        
        send_alert "vLLM Health Check Failed" "Quick test failed: $(echo "$response" | jq -r '.error.message // "Unknown error"')" "critical"
        return 1
    fi
}

# Run comprehensive benchmark
run_comprehensive_test() {
    local api_key=$(jq -r '.api_key' "$CONFIG_FILE")
    local base_url=$(jq -r '.base_url' "$CONFIG_FILE")
    
    log "Running comprehensive benchmark test..."
    
    # Run the enhanced benchmark suite
    if [ -f "${SCRIPT_DIR}/benchmark-suite.sh" ]; then
        local output_dir="${DATA_DIR}/benchmark_$(date +%Y%m%d_%H%M%S)"
        
        if bash "${SCRIPT_DIR}/benchmark-suite.sh" "$api_key" "$base_url"; then
            success "Comprehensive benchmark completed successfully"
            
            # Extract key metrics from the benchmark results
            local latest_result_dir=$(find "${SCRIPT_DIR}" -name "benchmark_results_*" -type d | sort | tail -1)
            if [ -n "$latest_result_dir" ] && [ -d "$latest_result_dir" ]; then
                extract_benchmark_metrics "$latest_result_dir"
                
                # Move results to data directory
                mv "$latest_result_dir" "$output_dir"
                log "Benchmark results moved to: $output_dir"
            fi
            
            return 0
        else
            error "Comprehensive benchmark failed"
            send_alert "Comprehensive Benchmark Failed" "The full benchmark suite failed to complete successfully" "warning"
            return 1
        fi
    else
        error "Benchmark suite not found: ${SCRIPT_DIR}/benchmark-suite.sh"
        return 1
    fi
}

# Run load test
run_load_test() {
    local profile="$1"
    local api_key=$(jq -r '.api_key' "$CONFIG_FILE")
    local base_url=$(jq -r '.base_url' "$CONFIG_FILE")
    
    log "Running load test with profile: $profile"
    
    if [ -f "${SCRIPT_DIR}/load-tester.sh" ]; then
        if bash "${SCRIPT_DIR}/load-tester.sh" "$api_key" "$base_url" "$profile"; then
            success "Load test ($profile) completed successfully"
            
            # Extract metrics from load test results
            local latest_result_dir=$(find "${SCRIPT_DIR}" -name "load_test_${profile}_*" -type d | sort | tail -1)
            if [ -n "$latest_result_dir" ] && [ -d "$latest_result_dir" ]; then
                extract_load_test_metrics "$latest_result_dir"
                
                # Move results to data directory
                local target_dir="${DATA_DIR}/load_test_${profile}_$(date +%Y%m%d_%H%M%S)"
                mv "$latest_result_dir" "$target_dir"
                log "Load test results moved to: $target_dir"
            fi
            
            return 0
        else
            error "Load test ($profile) failed"
            send_alert "Load Test Failed" "Load test with profile '$profile' failed to complete successfully" "warning"
            return 1
        fi
    else
        error "Load tester not found: ${SCRIPT_DIR}/load-tester.sh"
        return 1
    fi
}

# Extract metrics from benchmark results
extract_benchmark_metrics() {
    local result_dir="$1"
    
    # Look for individual test results
    for test_file in "$result_dir"/test_*.json; do
        if [ -f "$test_file" ]; then
            local result=$(jq '. + {"test_type": "comprehensive_test", "source_file": "'$(basename "$test_file")'"}' "$test_file")
            record_benchmark_result "$result"
        fi
    done
}

# Extract metrics from load test results
extract_load_test_metrics() {
    local result_dir="$1"
    local metrics_file="$result_dir/load_metrics.json"
    
    if [ -f "$metrics_file" ]; then
        local result=$(jq '.performance_metrics + {"test_type": "load_test", "timestamp": "'$(date -Iseconds)'"}' "$metrics_file")
        record_benchmark_result "$result"
    fi
}

# Record benchmark result to trends
record_benchmark_result() {
    local result="$1"
    
    # Initialize trends file if it doesn't exist
    if [ ! -f "$TRENDS_FILE" ]; then
        echo '{"results": []}' > "$TRENDS_FILE"
    fi
    
    # Append result
    local temp_file=$(mktemp)
    jq ".results += [$result]" "$TRENDS_FILE" > "$temp_file" && mv "$temp_file" "$TRENDS_FILE"
    
    # Check for performance regression
    local tokens_per_second=$(echo "$result" | jq -r '.tokens_per_second // 0')
    if (( $(echo "$tokens_per_second > 0" | bc -l 2>/dev/null || echo "0") )); then
        check_performance_trend "$tokens_per_second" "$(echo "$result" | jq -r '.test_type')"
    fi
}

# Analyze performance trends and detect regressions
check_performance_trend() {
    local current_tps="$1"
    local test_type="$2"
    local baseline_tps=$(jq -r '.baseline_tps' "$CONFIG_FILE")
    local regression_threshold=$(jq -r '.regression_threshold' "$CONFIG_FILE")
    
    # Check against baseline
    local deviation=$(echo "scale=3; ($baseline_tps - $current_tps) / $baseline_tps" | bc -l 2>/dev/null || echo "0")
    
    if (( $(echo "$deviation > $regression_threshold" | bc -l 2>/dev/null || echo "0") )); then
        local regression_pct=$(echo "scale=1; $deviation * 100" | bc -l)
        warning "Performance regression detected in $test_type"
        warning "Current: ${current_tps} tok/s, Baseline: ${baseline_tps} tok/s, Regression: ${regression_pct}%"
        
        send_alert "Performance Regression Detected" "Test: ${test_type}\nCurrent: ${current_tps} tok/s\nBaseline: ${baseline_tps} tok/s\nRegression: ${regression_pct}%" "critical"
    fi
    
    # Trend analysis (check last 5 results of same type)
    local recent_results=$(jq -r --arg test_type "$test_type" '
        .results[] | 
        select(.test_type == $test_type and .tokens_per_second != null and (.tokens_per_second | type) == "number") | 
        .tokens_per_second
    ' "$TRENDS_FILE" | tail -5)
    
    if [ $(echo "$recent_results" | wc -l) -ge 3 ]; then
        # Calculate trend (simple linear regression would be better, but this is simpler)
        local first=$(echo "$recent_results" | head -1)
        local last=$(echo "$recent_results" | tail -1)
        
        if (( $(echo "$first > 0" | bc -l) )) && (( $(echo "$last < $first * 0.9" | bc -l) )); then
            warning "Declining performance trend detected in $test_type"
            send_alert "Performance Trend Alert" "Declining performance trend in ${test_type}: ${first} -> ${last} tok/s" "warning"
        fi
    fi
}

# Cleanup old data
cleanup_old_data() {
    local retention_days=$(jq -r '.retention_days' "$CONFIG_FILE")
    
    log "Cleaning up data older than $retention_days days..."
    
    # Clean up old benchmark results
    find "$DATA_DIR" -type d -name "benchmark_*" -mtime +$retention_days -exec rm -rf {} \; 2>/dev/null || true
    find "$DATA_DIR" -type d -name "load_test_*" -mtime +$retention_days -exec rm -rf {} \; 2>/dev/null || true
    
    # Trim trends file to keep only recent data
    local cutoff_date=$(date -d "$retention_days days ago" -Iseconds)
    local temp_file=$(mktemp)
    
    jq --arg cutoff "$cutoff_date" '.results = (.results | map(select(.timestamp >= $cutoff)))' "$TRENDS_FILE" > "$temp_file" && mv "$temp_file" "$TRENDS_FILE"
    
    log "Data cleanup completed"
}

# Main continuous loop
run_continuous_benchmark() {
    local interval_minutes=$(jq -r '.benchmark_interval_minutes' "$CONFIG_FILE")
    local last_comprehensive=$(date +%s)
    local last_daily=$(date +%s)
    local last_weekly=$(date +%s)
    local last_cleanup=$(date +%s)
    
    log "Starting continuous benchmarking loop (interval: ${interval_minutes} minutes)"
    
    while true; do
        local current_time=$(date +%s)
        local hour=$(date +%H)
        local day_of_week=$(date +%u)  # 1=Monday, 7=Sunday
        
        # Quick test every run
        if jq -e '.benchmarks.quick_test.enabled' "$CONFIG_FILE" > /dev/null; then
            run_quick_test || true
        fi
        
        # Comprehensive test (hourly)
        if jq -e '.benchmarks.comprehensive_test.enabled' "$CONFIG_FILE" > /dev/null; then
            local comprehensive_freq=$(jq -r '.benchmarks.comprehensive_test.frequency' "$CONFIG_FILE")
            if [ "$comprehensive_freq" = "hourly" ] || [ "$comprehensive_freq" = "every_run" ]; then
                if [ $((current_time - last_comprehensive)) -ge 3600 ] || [ "$comprehensive_freq" = "every_run" ]; then
                    run_comprehensive_test || true
                    last_comprehensive=$current_time
                fi
            fi
        fi
        
        # Daily load test (run at 2 AM)
        if jq -e '.benchmarks.load_test.enabled' "$CONFIG_FILE" > /dev/null; then
            local load_freq=$(jq -r '.benchmarks.load_test.frequency' "$CONFIG_FILE")
            if [ "$load_freq" = "daily" ] && [ "$hour" = "02" ] && [ $((current_time - last_daily)) -ge 86400 ]; then
                local load_profile=$(jq -r '.benchmarks.load_test.profile // "realistic"' "$CONFIG_FILE")
                run_load_test "$load_profile" || true
                last_daily=$current_time
            fi
        fi
        
        # Weekly stress test (run on Sunday at 3 AM)
        if jq -e '.benchmarks.stress_test.enabled' "$CONFIG_FILE" > /dev/null; then
            local stress_freq=$(jq -r '.benchmarks.stress_test.frequency' "$CONFIG_FILE")
            if [ "$stress_freq" = "weekly" ] && [ "$day_of_week" = "7" ] && [ "$hour" = "03" ] && [ $((current_time - last_weekly)) -ge 604800 ]; then
                local stress_profile=$(jq -r '.benchmarks.stress_test.profile // "stress"' "$CONFIG_FILE")
                run_load_test "$stress_profile" || true
                last_weekly=$current_time
            fi
        fi
        
        # Daily cleanup (run at 4 AM)
        if [ "$hour" = "04" ] && [ $((current_time - last_cleanup)) -ge 86400 ]; then
            cleanup_old_data
            last_cleanup=$current_time
        fi
        
        # Sleep for the configured interval
        log "Sleeping for ${interval_minutes} minutes..."
        sleep $((interval_minutes * 60))
    done
}

# Generate performance report
generate_performance_report() {
    local report_file="${DATA_DIR}/performance_report_$(date +%Y%m%d_%H%M%S).html"
    
    log "Generating performance report: $report_file"
    
    # Create HTML report with charts and analysis
    cat > "$report_file" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>vLLM Continuous Performance Report</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .metric { display: inline-block; margin: 10px; padding: 15px; background: #e8f4f8; border-radius: 5px; }
        .chart-container { width: 100%; height: 400px; margin: 20px 0; }
        .alert { padding: 10px; margin: 10px 0; border-radius: 5px; }
        .alert-warning { background: #fff3cd; border: 1px solid #ffeaa7; }
        .alert-success { background: #d4edda; border: 1px solid #c3e6cb; }
    </style>
</head>
<body>
    <div class="header">
        <h1>vLLM Continuous Performance Report</h1>
        <p>Generated: TIMESTAMP_PLACEHOLDER</p>
    </div>
    
    <div id="summary">
        <h2>Performance Summary</h2>
        <!-- Summary will be inserted here -->
    </div>
    
    <div class="chart-container">
        <canvas id="tpsChart"></canvas>
    </div>
    
    <div class="chart-container">
        <canvas id="responseTimeChart"></canvas>
    </div>
    
    <script>
        // Chart data will be inserted here
        const trendData = TREND_DATA_PLACEHOLDER;
        
        // Tokens per second chart
        const tpsCtx = document.getElementById('tpsChart').getContext('2d');
        new Chart(tpsCtx, {
            type: 'line',
            data: {
                labels: trendData.map(d => new Date(d.timestamp).toLocaleDateString()),
                datasets: [{
                    label: 'Tokens per Second',
                    data: trendData.map(d => d.tokens_per_second),
                    borderColor: 'rgb(75, 192, 192)',
                    tension: 0.1
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    title: {
                        display: true,
                        text: 'Performance Trend - Tokens per Second'
                    }
                }
            }
        });
        
        // Response time chart
        const responseCtx = document.getElementById('responseTimeChart').getContext('2d');
        new Chart(responseCtx, {
            type: 'line',
            data: {
                labels: trendData.map(d => new Date(d.timestamp).toLocaleDateString()),
                datasets: [{
                    label: 'Response Time (seconds)',
                    data: trendData.map(d => d.duration_seconds),
                    borderColor: 'rgb(255, 99, 132)',
                    tension: 0.1
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    title: {
                        display: true,
                        text: 'Performance Trend - Response Time'
                    }
                }
            }
        });
    </script>
</body>
</html>
EOF
    
    # Replace placeholders with actual data
    local trend_data=$(jq -c '.results | map(select(.tokens_per_second != null))' "$TRENDS_FILE" 2>/dev/null || echo '[]')
    sed -i.bak "s/TIMESTAMP_PLACEHOLDER/$(date)/g" "$report_file"
    sed -i.bak "s/TREND_DATA_PLACEHOLDER/$trend_data/g" "$report_file"
    rm -f "${report_file}.bak"
    
    success "Performance report generated: $report_file"
    echo "$report_file"
}

# Signal handlers
cleanup_on_exit() {
    log "Shutting down continuous benchmarking..."
    release_lock
    exit 0
}

trap cleanup_on_exit INT TERM EXIT

# Main execution
main() {
    case "${1:-start}" in
        "start")
            log "Starting continuous benchmarking service..."
            load_config
            acquire_lock
            run_continuous_benchmark
            ;;
        "stop")
            if [ -f "$PID_FILE" ]; then
                local pid=$(cat "$PID_FILE")
                if kill -0 "$pid" 2>/dev/null; then
                    log "Stopping continuous benchmarking (PID: $pid)..."
                    kill "$pid"
                    success "Continuous benchmarking stopped"
                else
                    warning "Process not running (stale PID file)"
                    rm -f "$PID_FILE" "$LOCK_FILE"
                fi
            else
                warning "No PID file found - process may not be running"
            fi
            ;;
        "status")
            if [ -f "$PID_FILE" ]; then
                local pid=$(cat "$PID_FILE")
                if kill -0 "$pid" 2>/dev/null; then
                    success "Continuous benchmarking is running (PID: $pid)"
                    if [ -f "$TRENDS_FILE" ]; then
                        local result_count=$(jq '.results | length' "$TRENDS_FILE")
                        log "Total benchmark results: $result_count"
                    fi
                else
                    warning "Process not running (stale PID file)"
                fi
            else
                log "Continuous benchmarking is not running"
            fi
            ;;
        "report")
            load_config
            generate_performance_report
            ;;
        "test")
            load_config
            run_quick_test
            ;;
        *)
            echo "Usage: $0 {start|stop|status|report|test} [config_file]"
            echo ""
            echo "Commands:"
            echo "  start   - Start continuous benchmarking service"
            echo "  stop    - Stop continuous benchmarking service"
            echo "  status  - Check service status"
            echo "  report  - Generate performance report"
            echo "  test    - Run a quick test"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"