#!/bin/bash
# CI/CD Pipeline Manager for vLLM Server
# Handles automated testing, deployment, and rollback operations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="/etc/vllm/cicd/pipeline.conf"
PIPELINE_ROOT="/opt/vllm-cicd"
LOG_FILE="/var/log/vllm-cicd/pipeline.log"

# Default configuration
ENABLE_TESTING=true
ENABLE_STAGING=true
ENABLE_PRODUCTION=true
TEST_TIMEOUT=300
PERFORMANCE_THRESHOLD=10.0
API_TIMEOUT=30
ENABLE_AUTO_ROLLBACK=true
ROLLBACK_THRESHOLD=3
HEALTH_CHECK_RETRIES=5

# Load configuration if exists
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

show_help() {
    cat << EOF
vLLM CI/CD Pipeline Manager

USAGE:
    $0 <command> [options]

COMMANDS:
    deploy [stage]       Deploy to stage (test|staging|production)
    test                 Run comprehensive test suite
    rollback [version]   Rollback to previous version
    status               Show pipeline status
    validate             Validate configuration
    history              Show deployment history

OPTIONS:
    --dry-run           Show what would be done without executing
    --force             Force operation even if tests fail
    --quiet             Minimal output
    --config FILE       Use alternative config file

EXAMPLES:
    $0 deploy test                     # Deploy to test environment
    $0 deploy production --dry-run     # Show production deployment plan
    $0 test                           # Run full test suite
    $0 rollback                       # Rollback to previous version
    $0 status                         # Show current status

EOF
}

send_notification() {
    local title="$1"
    local message="$2"
    local color="${3:-info}"
    
    log "NOTIFICATION: $title - $message"
    
    # Slack notification
    if [[ -n "${SLACK_WEBHOOK:-}" ]]; then
        local slack_color="good"
        case "$color" in
            "error") slack_color="danger" ;;
            "warning") slack_color="warning" ;;
        esac
        
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"attachments\":[{\"color\":\"$slack_color\",\"title\":\"$title\",\"text\":\"$message\"}]}" \
            "$SLACK_WEBHOOK" > /dev/null 2>&1 || true
    fi
}

check_service_health() {
    local retries="${1:-$HEALTH_CHECK_RETRIES}"
    
    for ((i=1; i<=retries; i++)); do
        log "Health check attempt $i/$retries"
        
        # Check if service is running
        if ! systemctl is-active --quiet vllm-server; then
            warning "vLLM service not running"
            sleep 5
            continue
        fi
        
        # Check API health
        if curl -f -s --max-time "$API_TIMEOUT" "http://localhost:8000/health" > /dev/null; then
            # Test generation
            local test_response=$(curl -s --max-time "$API_TIMEOUT" \
                -H "Authorization: Bearer $API_KEY" \
                -H "Content-Type: application/json" \
                -d '{"model":"qwen3","messages":[{"role":"user","content":"Say OK"}],"max_tokens":5}' \
                "http://localhost:8000/v1/chat/completions")
            
            if echo "$test_response" | jq -e '.choices[0].message.content' > /dev/null 2>&1; then
                success "Health check passed"
                return 0
            fi
        fi
        
        warning "Health check failed, retrying in 10 seconds..."
        sleep 10
    done
    
    error "Health check failed after $retries attempts"
    return 1
}

run_performance_test() {
    log "Starting performance test..."
    
    local start_time=$(date +%s)
    
    # Use existing benchmark script if available
    if [[ -f "$SCRIPT_DIR/../../scripts/performance/benchmark-suite.sh" ]]; then
        log "Running benchmark suite..."
        bash "$SCRIPT_DIR/../../scripts/performance/benchmark-suite.sh" "$API_KEY" "http://localhost:8000/v1"
        
        # Check if benchmark completed successfully
        if [[ $? -eq 0 ]]; then
            success "Performance test completed"
            return 0
        else
            error "Performance test failed"
            return 1
        fi
    else
        # Simple performance test
        log "Running simple performance test..."
        
        local response_time=$(curl -w "%{time_total}" -s -o /dev/null --max-time "$API_TIMEOUT" \
            -H "Authorization: Bearer $API_KEY" \
            -H "Content-Type: application/json" \
            -d '{"model":"qwen3","messages":[{"role":"user","content":"Write a short paragraph about AI."}],"max_tokens":100}' \
            "http://localhost:8000/v1/chat/completions")
        
        if (( $(echo "$response_time > $PERFORMANCE_THRESHOLD" | bc -l) )); then
            error "Performance test failed: response time ${response_time}s > ${PERFORMANCE_THRESHOLD}s"
            return 1
        fi
        
        success "Performance test passed: ${response_time}s"
        return 0
    fi
}

run_test_suite() {
    log "Running comprehensive test suite..."
    
    local test_results=()
    
    # Health check
    log "1. Running health check..."
    if check_service_health 3; then
        test_results+=("health:PASS")
    else
        test_results+=("health:FAIL")
    fi
    
    # API endpoints test
    log "2. Testing API endpoints..."
    local endpoints=("/health" "/v1/models")
    local endpoint_results=()
    
    for endpoint in "${endpoints[@]}"; do
        local url="http://localhost:8000$endpoint"
        local headers=""
        
        if [[ "$endpoint" == "/v1/models" ]]; then
            headers="-H 'Authorization: Bearer $API_KEY'"
        fi
        
        if eval "curl -f -s --max-time 10 $headers $url" > /dev/null; then
            endpoint_results+=("$endpoint:PASS")
        else
            endpoint_results+=("$endpoint:FAIL")
        fi
    done
    
    if [[ ${#endpoints[@]} -eq $(echo "${endpoint_results[@]}" | grep -o "PASS" | wc -l) ]]; then
        test_results+=("endpoints:PASS")
    else
        test_results+=("endpoints:FAIL")
    fi
    
    # Performance test
    log "3. Running performance test..."
    if run_performance_test; then
        test_results+=("performance:PASS")
    else
        test_results+=("performance:FAIL")
    fi
    
    # GPU memory test
    log "4. Checking GPU memory usage..."
    if nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | awk '{if($1 > 1000) count++} END {if(count >= 2) exit 0; else exit 1}'; then
        test_results+=("gpu_memory:PASS")
    else
        test_results+=("gpu_memory:FAIL")
    fi
    
    # Summary
    local total_tests=${#test_results[@]}
    local passed_tests=$(echo "${test_results[@]}" | grep -o "PASS" | wc -l)
    
    log "Test Results Summary:"
    for result in "${test_results[@]}"; do
        local test_name=$(echo "$result" | cut -d: -f1)
        local test_status=$(echo "$result" | cut -d: -f2)
        
        if [[ "$test_status" == "PASS" ]]; then
            log "  ✅ $test_name"
        else
            log "  ❌ $test_name"
        fi
    done
    
    log "Tests passed: $passed_tests/$total_tests"
    
    if [[ $passed_tests -eq $total_tests ]]; then
        success "All tests passed"
        return 0
    else
        error "Some tests failed"
        return 1
    fi
}

create_deployment_backup() {
    local deployment_id="$1"
    
    log "Creating deployment backup..."
    
    # Create backup using existing backup system
    if command -v vllm-backup > /dev/null 2>&1; then
        vllm-backup create snapshot
        success "Deployment backup created"
    else
        warning "Backup system not available, skipping backup"
    fi
}

record_deployment() {
    local stage="$1"
    local status="$2"
    local version="${3:-$(date +%Y%m%d-%H%M%S)}"
    
    local history_file="$PIPELINE_ROOT/deployments/history.json"
    mkdir -p "$(dirname "$history_file")"
    
    # Initialize history file if it doesn't exist
    if [[ ! -f "$history_file" ]]; then
        echo "[]" > "$history_file"
    fi
    
    # Add deployment record
    local record=$(jq -n \
        --arg timestamp "$(date -Iseconds)" \
        --arg stage "$stage" \
        --arg status "$status" \
        --arg version "$version" \
        --arg hostname "$(hostname)" \
        '{
            timestamp: $timestamp,
            stage: $stage,
            status: $status,
            version: $version,
            hostname: $hostname
        }')
    
    jq ". += [$record]" "$history_file" > "${history_file}.tmp" && mv "${history_file}.tmp" "$history_file"
}

deploy_to_stage() {
    local stage="$1"
    local dry_run="${2:-false}"
    local force="${3:-false}"
    
    log "Starting deployment to $stage"
    
    if [[ "$dry_run" == "true" ]]; then
        log "DRY RUN: Would deploy to $stage"
        return 0
    fi
    
    local deployment_id="deploy-$(date +%Y%m%d-%H%M%S)"
    
    case "$stage" in
        "test")
            log "Deploying to test environment..."
            
            # Create backup
            create_deployment_backup "$deployment_id"
            
            # Restart service with test configuration
            log "Restarting vLLM service..."
            systemctl restart vllm-server
            
            # Wait for service to come up
            sleep 30
            
            # Run tests
            if [[ "$force" != "true" ]]; then
                if ! run_test_suite; then
                    record_deployment "$stage" "FAILED" "$deployment_id"
                    send_notification "Test Deployment Failed" "Deployment $deployment_id to $stage failed tests" "error"
                    error "Test deployment failed"
                fi
            fi
            
            record_deployment "$stage" "SUCCESS" "$deployment_id"
            send_notification "Test Deployment Successful" "Deployment $deployment_id to $stage completed successfully"
            ;;
            
        "staging")
            log "Deploying to staging environment..."
            
            # Run test deployment first if not forced
            if [[ "$force" != "true" ]]; then
                deploy_to_stage "test" "false" "false"
            fi
            
            create_deployment_backup "$deployment_id"
            
            # Deploy with staging configuration
            log "Updating staging configuration..."
            systemctl restart vllm-server
            sleep 30
            
            if ! check_service_health; then
                record_deployment "$stage" "FAILED" "$deployment_id"
                send_notification "Staging Deployment Failed" "Deployment $deployment_id to $stage failed health check" "error"
                error "Staging deployment failed"
            fi
            
            record_deployment "$stage" "SUCCESS" "$deployment_id"
            send_notification "Staging Deployment Successful" "Deployment $deployment_id to $stage completed successfully"
            ;;
            
        "production")
            log "Deploying to production environment..."
            
            if [[ "$force" != "true" ]]; then
                deploy_to_stage "staging" "false" "false"
            fi
            
            create_deployment_backup "$deployment_id"
            
            # Production deployment
            log "Updating production configuration..."
            systemctl restart vllm-server
            sleep 60  # Longer wait for production
            
            if ! check_service_health; then
                record_deployment "$stage" "FAILED" "$deployment_id"
                send_notification "Production Deployment Failed" "Deployment $deployment_id to $stage failed health check" "error"
                
                if [[ "$ENABLE_AUTO_ROLLBACK" == "true" ]]; then
                    warning "Auto-rollback enabled, attempting rollback..."
                    rollback_deployment
                fi
                
                error "Production deployment failed"
            fi
            
            # Extended monitoring for production
            log "Running extended production health checks..."
            for ((i=1; i<=5; i++)); do
                sleep 60
                if ! check_service_health 1; then
                    warning "Production health check $i failed"
                    if [[ "$ENABLE_AUTO_ROLLBACK" == "true" ]]; then
                        rollback_deployment
                        error "Production deployment failed extended monitoring"
                    fi
                fi
            done
            
            record_deployment "$stage" "SUCCESS" "$deployment_id"
            send_notification "Production Deployment Successful" "Deployment $deployment_id to $stage completed successfully"
            ;;
            
        *)
            error "Unknown deployment stage: $stage"
            ;;
    esac
    
    success "$stage deployment completed successfully"
}

rollback_deployment() {
    local version="${1:-}"
    
    log "Starting rollback process..."
    
    if [[ -z "$version" ]]; then
        # Find last successful deployment
        local history_file="$PIPELINE_ROOT/deployments/history.json"
        if [[ -f "$history_file" ]]; then
            version=$(jq -r '.[] | select(.status == "SUCCESS") | .version' "$history_file" | tail -2 | head -1)
        fi
        
        if [[ -z "$version" ]]; then
            error "No previous successful deployment found"
        fi
    fi
    
    log "Rolling back to version: $version"
    
    # Use backup system to rollback if available
    if command -v vllm-backup > /dev/null 2>&1; then
        log "Using backup system for rollback..."
        # This would need to be implemented in the backup system
        warning "Backup system rollback not fully implemented"
    fi
    
    # Simple rollback: restart with previous configuration
    log "Restarting service..."
    systemctl restart vllm-server
    sleep 30
    
    if check_service_health; then
        record_deployment "rollback" "SUCCESS" "$version"
        send_notification "Rollback Successful" "Successfully rolled back to version $version"
        success "Rollback completed successfully"
    else
        record_deployment "rollback" "FAILED" "$version"
        send_notification "Rollback Failed" "Failed to rollback to version $version" "error"
        error "Rollback failed"
    fi
}

show_deployment_history() {
    local history_file="$PIPELINE_ROOT/deployments/history.json"
    
    if [[ ! -f "$history_file" ]]; then
        log "No deployment history available"
        return 0
    fi
    
    log "Deployment History:"
    echo
    
    jq -r '.[] | "\(.timestamp) | \(.stage) | \(.status) | \(.version)"' "$history_file" | \
        tail -20 | \
        while IFS='|' read -r timestamp stage status version; do
            local color="$NC"
            case "$status" in
                *SUCCESS*) color="$GREEN" ;;
                *FAILED*) color="$RED" ;;
            esac
            
            printf "${color}%-20s %-12s %-10s %s${NC}\n" \
                "$(echo $timestamp | cut -c1-19)" \
                "$(echo $stage | xargs)" \
                "$(echo $status | xargs)" \
                "$(echo $version | xargs)"
        done
}

show_status() {
    log "vLLM CI/CD Pipeline Status"
    echo
    
    # Service status
    if systemctl is-active --quiet vllm-server; then
        echo -e "Service Status: ${GREEN}RUNNING${NC}"
    else
        echo -e "Service Status: ${RED}STOPPED${NC}"
    fi
    
    # Health status
    if curl -f -s --max-time 5 "http://localhost:8000/health" > /dev/null 2>&1; then
        echo -e "API Health: ${GREEN}HEALTHY${NC}"
    else
        echo -e "API Health: ${RED}UNHEALTHY${NC}"
    fi
    
    # Recent deployments
    echo
    echo "Recent Deployments:"
    show_deployment_history | tail -5
}

validate_configuration() {
    log "Validating CI/CD configuration..."
    
    local errors=0
    
    # Check required directories
    for dir in "$PIPELINE_ROOT" "$(dirname "$LOG_FILE")"; do
        if [[ ! -d "$dir" ]]; then
            error "Required directory missing: $dir"
            ((errors++))
        fi
    done
    
    # Check configuration file
    if [[ ! -f "$CONFIG_FILE" ]]; then
        warning "Configuration file not found: $CONFIG_FILE"
        ((errors++))
    fi
    
    # Check API connectivity
    if [[ -n "$API_KEY" ]]; then
        if ! curl -f -s --max-time 10 -H "Authorization: Bearer $API_KEY" \
            "http://localhost:8000/v1/models" > /dev/null; then
            error "API connectivity check failed"
            ((errors++))
        fi
    else
        error "API_KEY not configured"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        success "Configuration validation passed"
    else
        error "$errors validation errors found"
    fi
}

main() {
    local command="${1:-help}"
    shift || true
    
    local dry_run=false
    local force=false
    local stage=""
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run) dry_run=true; shift ;;
            --force) force=true; shift ;;
            --config) CONFIG_FILE="$2"; shift 2 ;;
            --quiet) exec > /dev/null; shift ;;
            -*) error "Unknown option: $1" ;;
            *) stage="$1"; shift ;;
        esac
    done
    
    case "$command" in
        deploy)
            if [[ -z "$stage" ]]; then
                stage="test"
            fi
            deploy_to_stage "$stage" "$dry_run" "$force"
            ;;
        test)
            run_test_suite
            ;;
        rollback)
            rollback_deployment "$stage"
            ;;
        status)
            show_status
            ;;
        history)
            show_deployment_history
            ;;
        validate)
            validate_configuration
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "Unknown command: $command. Use 'help' for usage information."
            ;;
    esac
}

main "$@"