#!/bin/bash

# Production Load Testing Tool for vLLM
# Simulates real-world usage patterns based on 75 tokens/sec baseline
# Usage: ./load-tester.sh [API_KEY] [BASE_URL] [TEST_PROFILE]

set -euo pipefail

# Configuration
API_KEY="${1:-qwen3-secret-key}"
BASE_URL="${2:-http://localhost:8000/v1}"
TEST_PROFILE="${3:-realistic}"  # realistic, stress, burst, sustained
MODEL_NAME="qwen3"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULTS_DIR="load_test_${TEST_PROFILE}_${TIMESTAMP}"
LOG_FILE="${RESULTS_DIR}/load_test.log"
METRICS_FILE="${RESULTS_DIR}/load_metrics.json"

# Performance baselines from production
BASELINE_TPS=75.0
BASELINE_RESPONSE_TIME=0.87
BASELINE_CONTEXT_LENGTH=200000

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

mkdir -p "$RESULTS_DIR"

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

# Test profiles configuration
configure_test_profile() {
    case "$TEST_PROFILE" in
        "realistic")
            CONCURRENT_USERS=5
            REQUEST_RATE=2  # requests per second
            TEST_DURATION=300  # 5 minutes
            RAMP_UP_TIME=60
            TOKEN_DISTRIBUTION="mixed"
            log "Configured REALISTIC load test: 5 concurrent users, 2 req/s, 5 minutes"
            ;;
        "stress")
            CONCURRENT_USERS=20
            REQUEST_RATE=10
            TEST_DURATION=600  # 10 minutes
            RAMP_UP_TIME=120
            TOKEN_DISTRIBUTION="heavy"
            log "Configured STRESS load test: 20 concurrent users, 10 req/s, 10 minutes"
            ;;
        "burst")
            CONCURRENT_USERS=50
            REQUEST_RATE=25
            TEST_DURATION=180  # 3 minutes
            RAMP_UP_TIME=30
            TOKEN_DISTRIBUTION="mixed"
            log "Configured BURST load test: 50 concurrent users, 25 req/s, 3 minutes"
            ;;
        "sustained")
            CONCURRENT_USERS=10
            REQUEST_RATE=5
            TEST_DURATION=1800  # 30 minutes
            RAMP_UP_TIME=180
            TOKEN_DISTRIBUTION="light"
            log "Configured SUSTAINED load test: 10 concurrent users, 5 req/s, 30 minutes"
            ;;
        *)
            error "Unknown test profile: $TEST_PROFILE"
            error "Available profiles: realistic, stress, burst, sustained"
            exit 1
            ;;
    esac
}

# Generate realistic test prompts with varying token requirements
generate_test_prompts() {
    local distribution="$1"
    local prompts_file="${RESULTS_DIR}/test_prompts.json"
    
    cat > "$prompts_file" << 'EOF'
{
    "light": [
        {"prompt": "Hello, how are you today?", "max_tokens": 50, "expected_tokens": 20},
        {"prompt": "What is the weather like?", "max_tokens": 100, "expected_tokens": 40},
        {"prompt": "Explain quantum computing briefly.", "max_tokens": 200, "expected_tokens": 80},
        {"prompt": "List 5 benefits of renewable energy.", "max_tokens": 300, "expected_tokens": 120}
    ],
    "mixed": [
        {"prompt": "Write a brief summary of machine learning concepts.", "max_tokens": 400, "expected_tokens": 200},
        {"prompt": "Explain the differences between SQL and NoSQL databases with examples.", "max_tokens": 800, "expected_tokens": 400},
        {"prompt": "Create a comprehensive guide to RESTful API design principles.", "max_tokens": 1200, "expected_tokens": 600},
        {"prompt": "Write a detailed technical explanation of microservices architecture, including benefits, challenges, and implementation strategies.", "max_tokens": 2000, "expected_tokens": 1000},
        {"prompt": "Provide a thorough analysis of cloud computing models (IaaS, PaaS, SaaS) with real-world examples and use cases.", "max_tokens": 1500, "expected_tokens": 750}
    ],
    "heavy": [
        {"prompt": "Write an extremely comprehensive technical manual about distributed systems, covering CAP theorem, consensus algorithms, data consistency, fault tolerance, and scalability patterns. Include detailed examples and code snippets.", "max_tokens": 4000, "expected_tokens": 2000},
        {"prompt": "Create a complete guide to DevOps practices, including CI/CD pipelines, containerization with Docker and Kubernetes, infrastructure as code, monitoring, logging, and security best practices. Be as detailed as possible.", "max_tokens": 5000, "expected_tokens": 2500},
        {"prompt": "Develop a thorough explanation of artificial intelligence and machine learning, covering supervised and unsupervised learning, neural networks, deep learning, natural language processing, computer vision, and ethical considerations. Include mathematical concepts and implementation details.", "max_tokens": 6000, "expected_tokens": 3000},
        {"prompt": "Write a comprehensive software engineering handbook covering design patterns, SOLID principles, testing strategies, code review processes, version control, project management methodologies, and team collaboration tools. Include practical examples and best practices.", "max_tokens": 4500, "expected_tokens": 2250}
    ]
}
EOF
    echo "$prompts_file"
}

# Single request with timing
make_request() {
    local prompt="$1"
    local max_tokens="$2"
    local request_id="$3"
    local start_timestamp=$(date +%s.%3N)
    
    local payload=$(cat << EOF
{
    "model": "$MODEL_NAME",
    "messages": [{"role": "user", "content": "$prompt"}],
    "max_tokens": $max_tokens,
    "temperature": 0.7,
    "stream": false
}
EOF
)
    
    local response=$(curl -s --max-time 180 "${BASE_URL}/chat/completions" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null)
    
    local end_timestamp=$(date +%s.%3N)
    local duration=$(echo "$end_timestamp - $start_timestamp" | bc -l)
    
    # Parse response
    local tokens_generated=0
    local success_status="false"
    local error_message=""
    
    if echo "$response" | jq -e '.choices[0].message.content' &> /dev/null; then
        tokens_generated=$(echo "$response" | jq -r '.usage.completion_tokens // 0')
        success_status="true"
    else
        error_message=$(echo "$response" | jq -r '.error.message // "Unknown error"' 2>/dev/null || echo "Parse error")
    fi
    
    # Calculate tokens per second
    local tokens_per_second=0
    if (( $(echo "$duration > 0" | bc -l) )) && (( tokens_generated > 0 )); then
        tokens_per_second=$(echo "scale=2; $tokens_generated / $duration" | bc -l)
    fi
    
    # Output result in JSON format for aggregation
    cat << EOF
{
    "request_id": "$request_id",
    "timestamp": "$(date -Iseconds)",
    "duration_seconds": $duration,
    "tokens_generated": $tokens_generated,
    "tokens_per_second": $tokens_per_second,
    "success": $success_status,
    "error_message": "$error_message",
    "max_tokens_requested": $max_tokens
}
EOF
}

# Run concurrent load test
run_load_test() {
    local prompts_file=$(generate_test_prompts "$TOKEN_DISTRIBUTION")
    local results_file="${RESULTS_DIR}/individual_results.json"
    local active_requests=0
    local total_requests=0
    local successful_requests=0
    local failed_requests=0
    
    # Initialize results file
    echo "[]" > "$results_file"
    
    log "Starting load test with profile: $TEST_PROFILE"
    log "Concurrent users: $CONCURRENT_USERS"
    log "Request rate: $REQUEST_RATE req/s"
    log "Duration: $TEST_DURATION seconds"
    log "Ramp-up time: $RAMP_UP_TIME seconds"
    
    local start_time=$(date +%s)
    local end_time=$((start_time + TEST_DURATION))
    local ramp_end_time=$((start_time + RAMP_UP_TIME))
    
    # Start background monitoring
    if command -v nvidia-smi &> /dev/null; then
        log "Starting GPU monitoring..."
        ./gpu-monitor.sh 5 $TEST_DURATION "${RESULTS_DIR}/gpu_load_monitor.log" &
        local gpu_monitor_pid=$!
    fi
    
    # Main load generation loop
    while [ $(date +%s) -lt $end_time ]; do
        current_time=$(date +%s)
        
        # Calculate current target concurrent users (ramp-up)
        local target_concurrent
        if [ $current_time -lt $ramp_end_time ]; then
            local ramp_progress=$(echo "scale=2; ($current_time - $start_time) / $RAMP_UP_TIME" | bc -l)
            target_concurrent=$(echo "scale=0; $CONCURRENT_USERS * $ramp_progress / 1" | bc)
            target_concurrent=${target_concurrent%.*}  # Remove decimal
            target_concurrent=$((target_concurrent > 0 ? target_concurrent : 1))
        else
            target_concurrent=$CONCURRENT_USERS
        fi
        
        # Maintain target concurrency level
        while [ $active_requests -lt $target_concurrent ] && [ $(date +%s) -lt $end_time ]; do
            # Select random prompt based on distribution
            local prompt_data=$(jq -r ".${TOKEN_DISTRIBUTION}[$(shuf -i 0-$(($(jq ".${TOKEN_DISTRIBUTION} | length" "$prompts_file") - 1)) -n 1)]" "$prompts_file")
            local prompt=$(echo "$prompt_data" | jq -r '.prompt')
            local max_tokens=$(echo "$prompt_data" | jq -r '.max_tokens')
            
            total_requests=$((total_requests + 1))
            
            # Start request in background
            {
                local result=$(make_request "$prompt" "$max_tokens" "req_${total_requests}")
                
                # Append result to file atomically
                local temp_file=$(mktemp)
                jq ". += [$result]" "$results_file" <<< "$result" > "$temp_file" && mv "$temp_file" "$results_file"
                
                # Update counters
                if echo "$result" | jq -e '.success == true' &> /dev/null; then
                    ((successful_requests++)) || true
                else
                    ((failed_requests++)) || true
                fi
                
                ((active_requests--)) || true
            } &
            
            ((active_requests++)) || true
            
            # Rate limiting
            sleep $(echo "scale=3; 1 / $REQUEST_RATE" | bc -l)
        done
        
        # Brief pause to prevent tight loop
        sleep 0.1
        
        # Progress update every 30 seconds
        if [ $((current_time % 30)) -eq 0 ]; then
            local elapsed=$((current_time - start_time))
            local remaining=$((end_time - current_time))
            log "Progress: ${elapsed}s elapsed, ${remaining}s remaining. Requests: ${total_requests} total, ${successful_requests} success, ${failed_requests} failed"
        fi
    done
    
    # Wait for all active requests to complete
    log "Waiting for remaining requests to complete..."
    wait
    
    # Stop GPU monitoring
    if [ -n "${gpu_monitor_pid:-}" ]; then
        kill $gpu_monitor_pid 2>/dev/null || true
        wait $gpu_monitor_pid 2>/dev/null || true
    fi
    
    log "Load test completed!"
    log "Total requests: $total_requests"
    log "Successful requests: $successful_requests"
    log "Failed requests: $failed_requests"
    
    # Generate comprehensive metrics
    generate_load_test_metrics "$results_file"
}

# Generate comprehensive metrics and analysis
generate_load_test_metrics() {
    local results_file="$1"
    
    log "Generating load test metrics..."
    
    # Calculate aggregate statistics using jq
    local stats=$(jq -r '
        map(select(.success == true)) |
        {
            total_requests: length,
            total_duration: (map(.duration_seconds) | add),
            total_tokens: (map(.tokens_generated) | add),
            avg_response_time: (map(.duration_seconds) | add / length),
            min_response_time: (map(.duration_seconds) | min),
            max_response_time: (map(.duration_seconds) | max),
            avg_tokens_per_sec: (map(.tokens_per_second) | add / length),
            min_tokens_per_sec: (map(.tokens_per_second) | min),
            max_tokens_per_sec: (map(.tokens_per_second) | max),
            p95_response_time: (map(.duration_seconds) | sort | .[((length * 0.95) | floor)]),
            p99_response_time: (map(.duration_seconds) | sort | .[((length * 0.99) | floor)])
        }
    ' "$results_file")
    
    local failed_count=$(jq '[.[] | select(.success == false)] | length' "$results_file")
    
    # Create comprehensive metrics file
    cat > "$METRICS_FILE" << EOF
{
    "load_test_summary": {
        "timestamp": "$(date -Iseconds)",
        "test_profile": "$TEST_PROFILE",
        "configuration": {
            "concurrent_users": $CONCURRENT_USERS,
            "request_rate": $REQUEST_RATE,
            "test_duration": $TEST_DURATION,
            "ramp_up_time": $RAMP_UP_TIME,
            "token_distribution": "$TOKEN_DISTRIBUTION"
        },
        "baseline_comparison": {
            "baseline_tps": $BASELINE_TPS,
            "baseline_response_time": $BASELINE_RESPONSE_TIME
        }
    },
    "performance_metrics": $stats,
    "error_analysis": {
        "failed_requests": $failed_count,
        "error_rate_pct": $(echo "scale=2; $failed_count * 100 / ($failed_count + $(echo "$stats" | jq '.total_requests'))" | bc -l)
    }
}
EOF
    
    # Performance analysis
    local avg_tps=$(echo "$stats" | jq -r '.avg_tokens_per_sec')
    local avg_response_time=$(echo "$stats" | jq -r '.avg_response_time')
    local total_requests=$(echo "$stats" | jq -r '.total_requests')
    
    echo ""
    echo -e "${BLUE}=== LOAD TEST RESULTS ===${NC}"
    echo -e "${CYAN}Test Profile:${NC} $TEST_PROFILE"
    echo -e "${CYAN}Total Requests:${NC} $total_requests"
    echo -e "${CYAN}Failed Requests:${NC} $failed_count"
    echo ""
    echo -e "${BLUE}Performance Metrics:${NC}"
    echo -e "${CYAN}Average Response Time:${NC} ${avg_response_time}s (baseline: ${BASELINE_RESPONSE_TIME}s)"
    echo -e "${CYAN}Average Tokens/Sec:${NC} ${avg_tps} (baseline: ${BASELINE_TPS})"
    echo -e "${CYAN}95th Percentile Response:${NC} $(echo "$stats" | jq -r '.p95_response_time')s"
    echo -e "${CYAN}99th Percentile Response:${NC} $(echo "$stats" | jq -r '.p99_response_time')s"
    echo ""
    
    # Performance comparison
    local tps_ratio=$(echo "scale=2; $avg_tps / $BASELINE_TPS" | bc -l)
    local response_ratio=$(echo "scale=2; $avg_response_time / $BASELINE_RESPONSE_TIME" | bc -l)
    
    if (( $(echo "$tps_ratio < 0.8" | bc -l) )); then
        warning "Performance below baseline: ${avg_tps} tok/s vs ${BASELINE_TPS} baseline"
    elif (( $(echo "$tps_ratio > 1.2" | bc -l) )); then
        success "Performance above baseline: ${avg_tps} tok/s vs ${BASELINE_TPS} baseline"
    else
        success "Performance within acceptable range: ${avg_tps} tok/s"
    fi
    
    echo -e "${CYAN}Results saved to:${NC} $RESULTS_DIR"
    echo -e "${CYAN}Detailed metrics:${NC} $METRICS_FILE"
}

# Main execution
main() {
    log "Starting vLLM Load Testing Tool"
    log "Base URL: $BASE_URL"
    log "Test Profile: $TEST_PROFILE"
    
    # Check dependencies
    if ! command -v jq &> /dev/null; then
        error "jq is required but not installed. Install with: apt-get install jq"
        exit 1
    fi
    
    if ! command -v bc &> /dev/null; then
        error "bc is required but not installed. Install with: apt-get install bc"
        exit 1
    fi
    
    # Test connectivity
    if ! curl -s --max-time 10 "${BASE_URL}/models" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" > /dev/null; then
        error "Cannot connect to vLLM server at ${BASE_URL}"
        exit 1
    fi
    
    configure_test_profile
    run_load_test
    
    success "Load test completed successfully!"
}

# Handle cleanup on script termination
cleanup() {
    log "Cleaning up background processes..."
    # Kill any remaining background jobs
    jobs -p | xargs -r kill 2>/dev/null || true
    wait 2>/dev/null || true
}

trap cleanup EXIT INT TERM

# Run main function
main "$@"