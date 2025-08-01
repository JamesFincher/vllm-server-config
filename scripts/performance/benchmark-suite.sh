#!/bin/bash

# Qwen3-480B vLLM Production-Ready Performance Benchmark Suite
# Based on production metrics: ~0.87s response, ~75 tokens/sec, 200k context
# Features: Comprehensive monitoring, regression testing, metrics collection
# Usage: ./benchmark-suite.sh [API_KEY] [BASE_URL] [OPTIONS]

set -euo pipefail

# Production Configuration
SCRIPT_VERSION="2.0.0"
PERFORMANCE_BASELINE_TPS=75.0  # tokens/sec baseline from production
REGRESSION_THRESHOLD=0.15      # 15% performance degradation threshold
ENABLE_MONITORING=${ENABLE_MONITORING:-true}
ENABLE_ALERTS=${ENABLE_ALERTS:-false}
WEBHOOK_URL=${WEBHOOK_URL:-""}
SLACK_WEBHOOK=${SLACK_WEBHOOK:-""}

# Configuration
API_KEY="${1:-qwen3-secret-key}"
BASE_URL="${2:-http://localhost:8000/v1}"
MODEL_NAME="qwen3"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULTS_DIR="benchmark_results_${TIMESTAMP}"
LOG_FILE="${RESULTS_DIR}/benchmark.log"
METRICS_FILE="${RESULTS_DIR}/metrics.json"
HISTORY_DIR="benchmark_history"
REGRESSION_FILE="${HISTORY_DIR}/regression_analysis.json"

# Ensure history directory exists
mkdir -p "$HISTORY_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create results directory
mkdir -p "$RESULTS_DIR"

# Logging function
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

# Check dependencies
check_dependencies() {
    log "Checking dependencies..."
    
    if ! command -v curl &> /dev/null; then
        error "curl is required but not installed"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        error "jq is required but not installed. Install with: apt-get install jq"
        exit 1
    fi
    
    if ! command -v nvidia-smi &> /dev/null; then
        warning "nvidia-smi not found. GPU monitoring will be skipped"
    fi
    
    success "Dependencies check passed"
}

# Test server connectivity
test_connectivity() {
    log "Testing server connectivity..."
    
    if ! curl -s --max-time 10 "${BASE_URL}/models" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" > /dev/null; then
        error "Cannot connect to vLLM server at ${BASE_URL}"
        error "Please ensure the server is running and API_KEY is correct"
        exit 1
    fi
    
    success "Server connectivity confirmed"
}

# Get GPU memory usage
get_gpu_memory() {
    if command -v nvidia-smi &> /dev/null; then
        nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits | tr ',' ' '
    else
        echo "N/A N/A"
    fi
}

# Get comprehensive GPU metrics
get_gpu_metrics() {
    if command -v nvidia-smi &> /dev/null; then
        nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw,power.limit --format=csv,noheader,nounits
    else
        echo "N/A"
    fi
}

# Get system metrics
get_system_metrics() {
    local cpu_usage=$(top -bn1 | grep "^%Cpu" | sed 's/.*, *\([0-9.]*\)%* id.*/\1/' | awk '{print 100 - $1}' 2>/dev/null || echo "N/A")
    local mem_info=$(free -m 2>/dev/null | awk 'NR==2{printf "%.1f,%.1f,%.1f", $3*100/$2, $3, $2}' || echo "N/A,N/A,N/A")
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^ *//' || echo "N/A")
    
    echo "${cpu_usage},${mem_info},${load_avg}"
}

# Send alert webhook
send_alert() {
    local title="$1"
    local message="$2"
    local severity="${3:-warning}"
    
    if [ "$ENABLE_ALERTS" = "true" ]; then
        if [ -n "$WEBHOOK_URL" ]; then
            curl -s -X POST "$WEBHOOK_URL" \
                -H "Content-Type: application/json" \
                -d "{\"title\":\"$title\",\"message\":\"$message\",\"severity\":\"$severity\",\"timestamp\":\"$(date -Iseconds)\"}" &
        fi
        
        if [ -n "$SLACK_WEBHOOK" ]; then
            curl -s -X POST "$SLACK_WEBHOOK" \
                -H "Content-Type: application/json" \
                -d "{\"text\":\"🚨 *$title*\n\`\`\`$message\`\`\`\"}" &
        fi
    fi
}

# Performance regression detection
detect_regression() {
    local current_tps="$1"
    local test_name="$2"
    
    # Check against baseline
    local deviation=$(echo "scale=3; ($PERFORMANCE_BASELINE_TPS - $current_tps) / $PERFORMANCE_BASELINE_TPS" | bc -l 2>/dev/null || echo "0")
    
    if (( $(echo "$deviation > $REGRESSION_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
        local regression_pct=$(echo "scale=1; $deviation * 100" | bc -l)
        warning "PERFORMANCE REGRESSION DETECTED: ${test_name}"
        warning "Current: ${current_tps} tok/s, Baseline: ${PERFORMANCE_BASELINE_TPS} tok/s"
        warning "Regression: ${regression_pct}% below baseline"
        
        send_alert "Performance Regression" "Test: ${test_name}\nCurrent: ${current_tps} tok/s\nBaseline: ${PERFORMANCE_BASELINE_TPS} tok/s\nRegression: ${regression_pct}%" "critical"
        
        # Log regression
        echo "{\"timestamp\":\"$(date -Iseconds)\",\"test\":\"$test_name\",\"current_tps\":$current_tps,\"baseline_tps\":$PERFORMANCE_BASELINE_TPS,\"regression_pct\":$regression_pct}" >> "$REGRESSION_FILE"
    fi
}

# Initialize metrics collection
init_metrics() {
    cat > "$METRICS_FILE" << EOF
{
    "benchmark_info": {
        "version": "$SCRIPT_VERSION",
        "timestamp": "$(date -Iseconds)",
        "base_url": "$BASE_URL",
        "model": "$MODEL_NAME",
        "baseline_tps": $PERFORMANCE_BASELINE_TPS
    },
    "system_info": {
        "hostname": "$(hostname)",
        "kernel": "$(uname -r)",
        "gpu_info": "$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo 'N/A')",
        "gpu_count": "$(nvidia-smi --list-gpus 2>/dev/null | wc -l || echo '0')"
    },
    "tests": []
}
EOF
}

# Add test result to metrics
add_test_metrics() {
    local test_data="$1"
    
    # Add system metrics to test data
    local system_metrics=$(get_system_metrics)
    local gpu_metrics=$(get_gpu_metrics)
    
    # Create enhanced test record
    local enhanced_data=$(echo "$test_data" | jq --arg sys "$system_metrics" --arg gpu "$gpu_metrics" '. + {"system_metrics": $sys, "gpu_metrics": $gpu}')
    
    # Add to metrics file
    local temp_file=$(mktemp)
    jq ".tests += [$enhanced_data]" "$METRICS_FILE" > "$temp_file" && mv "$temp_file" "$METRICS_FILE"
}

# Benchmark function with timing
benchmark_request() {
    local test_name="$1"
    local payload="$2"
    local stream_mode="$3"
    local output_file="$4"
    
    log "Running test: ${test_name}"
    
    # Record GPU memory before
    local gpu_before=$(get_gpu_memory)
    
    # Make request with timing
    local start_time=$(date +%s.%3N)
    
    if [ "$stream_mode" = "true" ]; then
        local response=$(curl -s --max-time 120 "${BASE_URL}/chat/completions" \
            -H "Authorization: Bearer ${API_KEY}" \
            -H "Content-Type: application/json" \
            -d "$payload" --no-buffer)
    else
        local response=$(curl -s --max-time 120 "${BASE_URL}/chat/completions" \
            -H "Authorization: Bearer ${API_KEY}" \
            -H "Content-Type: application/json" \
            -d "$payload")
    fi
    
    local end_time=$(date +%s.%3N)
    local duration=$(echo "$end_time - $start_time" | bc -l)
    
    # Record GPU memory after
    local gpu_after=$(get_gpu_memory)
    
    # Parse response
    local tokens_generated=0
    local finish_reason=""
    
    if echo "$response" | jq -e '.choices[0].message.content' &> /dev/null; then
        tokens_generated=$(echo "$response" | jq -r '.usage.completion_tokens // 0')
        finish_reason=$(echo "$response" | jq -r '.choices[0].finish_reason // "unknown"')
    else
        error "Invalid response from server for test: ${test_name}"
        echo "$response" > "${RESULTS_DIR}/error_${test_name// /_}.json"
        return 1
    fi
    
    # Calculate tokens per second
    local tokens_per_second=0
    if (( $(echo "$duration > 0" | bc -l) )) && (( tokens_generated > 0 )); then
        tokens_per_second=$(echo "scale=2; $tokens_generated / $duration" | bc -l)
    fi
    
    # Save detailed results
    cat > "$output_file" << EOF
{
    "test_name": "$test_name",
    "timestamp": "$(date -Iseconds)",
    "duration_seconds": $duration,
    "tokens_generated": $tokens_generated,
    "tokens_per_second": $tokens_per_second,
    "finish_reason": "$finish_reason",
    "stream_mode": $stream_mode,
    "gpu_memory_before": "$gpu_before",
    "gpu_memory_after": "$gpu_after",
    "response_sample": $(echo "$response" | jq -r '.choices[0].message.content // "error"' | head -c 100 | jq -R .)
}
EOF
    
    # Add to metrics collection
    if [ "$ENABLE_MONITORING" = "true" ]; then
        add_test_metrics "$(cat "$output_file")"
    fi
    
    # Check for performance regression
    if (( $(echo "$tokens_per_second > 0" | bc -l 2>/dev/null || echo "0") )); then
        detect_regression "$tokens_per_second" "$test_name"
    fi
    
    success "${test_name}: ${duration}s, ${tokens_generated} tokens, ${tokens_per_second} tok/s"
    return 0
}

# Test different token lengths
test_token_lengths() {
    log "Testing different token length responses..."
    
    # 10 tokens test
    local payload_10='{
        "model": "'$MODEL_NAME'",
        "messages": [{"role": "user", "content": "Say hello in exactly 5 words."}],
        "max_tokens": 10,
        "temperature": 0.1
    }'
    benchmark_request "10 Token Response" "$payload_10" "false" "${RESULTS_DIR}/test_10_tokens.json"
    
    # 100 tokens test
    local payload_100='{
        "model": "'$MODEL_NAME'",
        "messages": [{"role": "user", "content": "Write a brief explanation of quantum computing in about 50 words."}],
        "max_tokens": 100,
        "temperature": 0.3
    }'
    benchmark_request "100 Token Response" "$payload_100" "false" "${RESULTS_DIR}/test_100_tokens.json"
    
    # 1000 tokens test
    local payload_1000='{
        "model": "'$MODEL_NAME'",
        "messages": [{"role": "user", "content": "Write a detailed technical explanation of REST APIs, including HTTP methods, status codes, and best practices. Be comprehensive."}],
        "max_tokens": 1000,
        "temperature": 0.5
    }'
    benchmark_request "1000 Token Response" "$payload_1000" "false" "${RESULTS_DIR}/test_1000_tokens.json"
    
    # 4000 tokens test
    local payload_4000='{
        "model": "'$MODEL_NAME'",
        "messages": [{"role": "user", "content": "Write an extremely detailed technical article about microservices architecture, covering service discovery, API gateways, data consistency, monitoring, deployment strategies, and real-world examples. Include code snippets and implementation details."}],
        "max_tokens": 4000,
        "temperature": 0.7
    }'
    benchmark_request "4000 Token Response" "$payload_4000" "false" "${RESULTS_DIR}/test_4000_tokens.json"
}

# Test streaming vs non-streaming
test_streaming_performance() {
    log "Testing streaming vs non-streaming performance..."
    
    local test_prompt="Write a comprehensive guide to Docker containerization, including Dockerfile best practices, multi-stage builds, and orchestration with Kubernetes."
    
    # Non-streaming test
    local payload_regular='{
        "model": "'$MODEL_NAME'",
        "messages": [{"role": "user", "content": "'$test_prompt'"}],
        "max_tokens": 1500,
        "temperature": 0.5,
        "stream": false
    }'
    benchmark_request "Non-Streaming 1500 Tokens" "$payload_regular" "false" "${RESULTS_DIR}/test_nonstream.json"
    
    # Streaming test
    local payload_stream='{
        "model": "'$MODEL_NAME'",
        "messages": [{"role": "user", "content": "'$test_prompt'"}],
        "max_tokens": 1500,
        "temperature": 0.5,
        "stream": true
    }'
    benchmark_request "Streaming 1500 Tokens" "$payload_stream" "true" "${RESULTS_DIR}/test_stream.json"
}

# Test concurrent requests
test_concurrent_requests() {
    log "Testing concurrent request handling..."
    
    local concurrent_payload='{
        "model": "'$MODEL_NAME'",
        "messages": [{"role": "user", "content": "Explain the differences between SQL and NoSQL databases with examples."}],
        "max_tokens": 800,
        "temperature": 0.4
    }'
    
    # Test 1, 3, and 5 concurrent requests
    for concurrent in 1 3 5; do
        log "Testing ${concurrent} concurrent requests..."
        
        local pids=()
        local start_time=$(date +%s.%3N)
        
        for i in $(seq 1 $concurrent); do
            {
                benchmark_request "Concurrent ${concurrent}x Request ${i}" "$concurrent_payload" "false" "${RESULTS_DIR}/concurrent_${concurrent}x_${i}.json"
            } &
            pids+=($!)
        done
        
        # Wait for all requests to complete
        for pid in "${pids[@]}"; do
            wait $pid
        done
        
        local end_time=$(date +%s.%3N)
        local total_duration=$(echo "$end_time - $start_time" | bc -l)
        
        success "${concurrent} concurrent requests completed in ${total_duration}s"
        
        # Record concurrent test summary
        cat > "${RESULTS_DIR}/concurrent_${concurrent}x_summary.json" << EOF
{
    "concurrent_requests": $concurrent,
    "total_duration_seconds": $total_duration,
    "average_duration_per_request": $(echo "scale=3; $total_duration / $concurrent" | bc -l),
    "timestamp": "$(date -Iseconds)"
}
EOF
    done
}

# Stress test maximum token generation
test_maximum_tokens() {
    log "Testing maximum token generation (stress test)..."
    
    # 8192 tokens test (double the typical max)
    local payload_8k='{
        "model": "'$MODEL_NAME'",
        "messages": [{"role": "user", "content": "Write an extremely comprehensive, detailed technical manual about building a distributed system from scratch. Cover everything: architecture patterns, consistency models, consensus algorithms (Raft, Paxos), load balancing, caching strategies, database sharding, monitoring, logging, security, deployment, CI/CD, testing strategies, performance optimization, disaster recovery, and scaling patterns. Include detailed code examples in multiple languages, configuration files, and real-world case studies from major tech companies. Be as thorough and detailed as humanly possible."}],
        "max_tokens": 8192,
        "temperature": 0.6
    }'
    benchmark_request "Maximum 8192 Token Generation" "$payload_8k" "false" "${RESULTS_DIR}/test_max_8192_tokens.json"
    
    # Test context window boundaries
    log "Testing large context input handling..."
    local large_context="Context: "
    for i in {1..1000}; do
        large_context+="This is context line $i with important information about distributed systems, microservices, and cloud architecture patterns. "
    done
    
    local payload_large_context='{
        "model": "'$MODEL_NAME'",
        "messages": [{"role": "user", "content": "'$large_context' Question: Based on all this context, write a summary of the key distributed systems concepts."}],
        "max_tokens": 2000,
        "temperature": 0.5
    }'
    benchmark_request "Large Context Processing" "$payload_large_context" "false" "${RESULTS_DIR}/test_large_context.json"
}

# Generate performance report
generate_report() {
    log "Generating performance report..."
    
    local report_file="${RESULTS_DIR}/performance_report.md"
    
    cat > "$report_file" << 'EOF'
# Qwen3-480B vLLM Performance Benchmark Report

## Test Configuration
- **Model**: qwen3
- **Base URL**: BASE_URL_PLACEHOLDER
- **Test Timestamp**: TIMESTAMP_PLACEHOLDER
- **Test Duration**: DURATION_PLACEHOLDER

## Executive Summary
This report contains comprehensive performance metrics for the Qwen3-480B model running on vLLM.

## Test Results Summary

### Token Length Performance
EOF
    
    # Add token length results
    for tokens in 10 100 1000 4000; do
        if [ -f "${RESULTS_DIR}/test_${tokens}_tokens.json" ]; then
            local duration=$(jq -r '.duration_seconds' "${RESULTS_DIR}/test_${tokens}_tokens.json")
            local tok_per_sec=$(jq -r '.tokens_per_second' "${RESULTS_DIR}/test_${tokens}_tokens.json")
            local actual_tokens=$(jq -r '.tokens_generated' "${RESULTS_DIR}/test_${tokens}_tokens.json")
            
            cat >> "$report_file" << EOF
- **${tokens} Token Test**: ${duration}s, ${actual_tokens} tokens generated, ${tok_per_sec} tok/sec
EOF
        fi
    done
    
    cat >> "$report_file" << 'EOF'

### Streaming vs Non-Streaming
EOF
    
    # Add streaming comparison
    if [ -f "${RESULTS_DIR}/test_stream.json" ] && [ -f "${RESULTS_DIR}/test_nonstream.json" ]; then
        local stream_duration=$(jq -r '.duration_seconds' "${RESULTS_DIR}/test_stream.json")
        local nonstream_duration=$(jq -r '.duration_seconds' "${RESULTS_DIR}/test_nonstream.json")
        local stream_tps=$(jq -r '.tokens_per_second' "${RESULTS_DIR}/test_stream.json")
        local nonstream_tps=$(jq -r '.tokens_per_second' "${RESULTS_DIR}/test_nonstream.json")
        
        cat >> "$report_file" << EOF
- **Streaming**: ${stream_duration}s, ${stream_tps} tok/sec
- **Non-Streaming**: ${nonstream_duration}s, ${nonstream_tps} tok/sec
EOF
    fi
    
    cat >> "$report_file" << 'EOF'

### Concurrent Request Performance
EOF
    
    # Add concurrent results
    for concurrent in 1 3 5; do
        if [ -f "${RESULTS_DIR}/concurrent_${concurrent}x_summary.json" ]; then
            local total_duration=$(jq -r '.total_duration_seconds' "${RESULTS_DIR}/concurrent_${concurrent}x_summary.json")
            local avg_duration=$(jq -r '.average_duration_per_request' "${RESULTS_DIR}/concurrent_${concurrent}x_summary.json")
            
            cat >> "$report_file" << EOF
- **${concurrent} Concurrent Requests**: Total ${total_duration}s, Average ${avg_duration}s per request
EOF
        fi
    done
    
    cat >> "$report_file" << 'EOF'

### Maximum Performance Tests
EOF
    
    # Add max token results
    if [ -f "${RESULTS_DIR}/test_max_8192_tokens.json" ]; then
        local max_duration=$(jq -r '.duration_seconds' "${RESULTS_DIR}/test_max_8192_tokens.json")
        local max_tokens=$(jq -r '.tokens_generated' "${RESULTS_DIR}/test_max_8192_tokens.json")
        local max_tps=$(jq -r '.tokens_per_second' "${RESULTS_DIR}/test_max_8192_tokens.json")
        
        cat >> "$report_file" << EOF
- **Maximum Token Generation**: ${max_duration}s, ${max_tokens} tokens, ${max_tps} tok/sec
EOF
    fi
    
    # Replace placeholders
    sed -i.bak "s/BASE_URL_PLACEHOLDER/${BASE_URL//\//\\/}/g" "$report_file"
    sed -i.bak "s/TIMESTAMP_PLACEHOLDER/$TIMESTAMP/g" "$report_file"
    rm -f "${report_file}.bak"
    
    success "Performance report generated: $report_file"
}

# Main execution
main() {
    log "Starting Qwen3-480B Production Performance Benchmark Suite v${SCRIPT_VERSION}"
    log "Results will be saved to: $RESULTS_DIR"
    log "Monitoring enabled: $ENABLE_MONITORING"
    log "Alerts enabled: $ENABLE_ALERTS"
    log "Performance baseline: ${PERFORMANCE_BASELINE_TPS} tokens/sec"
    
    check_dependencies
    test_connectivity
    
    # Initialize metrics collection
    if [ "$ENABLE_MONITORING" = "true" ]; then
        init_metrics
        log "Metrics collection initialized"
    fi
    
    local start_time=$(date +%s)
    
    # Run all tests
    test_token_lengths
    test_streaming_performance
    test_concurrent_requests
    test_maximum_tokens
    
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    generate_report
    
    success "Benchmark suite completed in ${total_duration} seconds"
    success "Results available in: $RESULTS_DIR"
    
    # Show quick summary
    echo -e "\n${BLUE}=== QUICK SUMMARY ===${NC}"
    if [ -f "${RESULTS_DIR}/test_100_tokens.json" ]; then
        local sample_duration=$(jq -r '.duration_seconds' "${RESULTS_DIR}/test_100_tokens.json")
        local sample_tps=$(jq -r '.tokens_per_second' "${RESULTS_DIR}/test_100_tokens.json")
        echo -e "Sample Performance: ${sample_duration}s response, ${sample_tps} tokens/sec"
    fi
    echo -e "Full report: ${RESULTS_DIR}/performance_report.md"
    echo -e "Log file: $LOG_FILE"
}

# Run main function
main "$@"