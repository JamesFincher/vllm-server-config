#!/bin/bash
# One-Command Deployment Script for vLLM Qwen3-480B Server
# Usage: ./deploy.sh [OPTIONS]
# 
# This script provides complete automation for:
# - Server setup and configuration
# - Model deployment
# - Health monitoring setup
# - Backup configuration
# - CI/CD pipeline deployment
#
# Version: 2.0
# Author: Automated Deployment System
# Date: $(date)

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_ID="vllm-$(date +%Y%m%d-%H%M%S)"
LOG_DIR="/var/log/vllm-deployment"
CONFIG_DIR="/etc/vllm"
BACKUP_DIR="/opt/vllm-backups"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default values
SKIP_HARDWARE_CHECK=false
SKIP_MODEL_DOWNLOAD=false
ENABLE_MONITORING=true
ENABLE_BACKUP=true
ENABLE_CICD=true
API_KEY=""
CONTEXT_LENGTH=700000
DEPLOYMENT_MODE="production"

# Functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] [INFO]${NC} $1" | tee -a "${LOG_DIR}/deployment.log"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR]${NC} $1" | tee -a "${LOG_DIR}/deployment.log"
    exit 1
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] [WARNING]${NC} $1" | tee -a "${LOG_DIR}/deployment.log"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS]${NC} $1" | tee -a "${LOG_DIR}/deployment.log"
}

info() {
    echo -e "${CYAN}[$(date +'%Y-%m-%d %H:%M:%S')] [INFO]${NC} $1" | tee -a "${LOG_DIR}/deployment.log"
}

show_banner() {
    echo -e "${PURPLE}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                    vLLM Qwen3-480B Deployment                   ║
║                     Automated Setup Script                      ║
║                                                                  ║
║  • Complete server setup and configuration                      ║
║  • Model deployment with optimized settings                     ║
║  • Health monitoring and alerting                               ║
║  • Backup and recovery automation                               ║
║  • CI/CD pipeline deployment                                    ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

One-command deployment script for vLLM Qwen3-480B server with complete automation.

OPTIONS:
    --api-key KEY               Set API key for authentication (required)
    --context-length LENGTH     Set maximum context length (default: 700000)
    --mode MODE                 Deployment mode: production|development|testing (default: production)
    
    --skip-hardware-check       Skip hardware requirements validation
    --skip-model-download       Skip model download (assumes model exists)
    --no-monitoring             Disable health monitoring setup
    --no-backup                 Disable backup system setup
    --no-cicd                   Disable CI/CD pipeline setup
    
    --help                      Show this help message
    --version                   Show version information

EXAMPLES:
    # Basic production deployment
    sudo ./deploy.sh --api-key "your-secret-key"
    
    # Development deployment with custom context
    sudo ./deploy.sh --api-key "dev-key" --mode development --context-length 200000
    
    # Minimal deployment (no monitoring/backup)
    sudo ./deploy.sh --api-key "key" --no-monitoring --no-backup

REQUIREMENTS:
    - Root privileges (use sudo)
    - Ubuntu 22.04+ with 4x NVIDIA H200 GPUs
    - 700GB+ RAM, 1TB+ storage
    - Internet connection for downloads

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --api-key)
                API_KEY="$2"
                shift 2
                ;;
            --context-length)
                CONTEXT_LENGTH="$2"
                shift 2
                ;;
            --mode)
                DEPLOYMENT_MODE="$2"
                if [[ ! "$DEPLOYMENT_MODE" =~ ^(production|development|testing)$ ]]; then
                    error "Invalid deployment mode: $DEPLOYMENT_MODE"
                fi
                shift 2
                ;;
            --skip-hardware-check)
                SKIP_HARDWARE_CHECK=true
                shift
                ;;
            --skip-model-download)
                SKIP_MODEL_DOWNLOAD=true
                shift
                ;;
            --no-monitoring)
                ENABLE_MONITORING=false
                shift
                ;;
            --no-backup)
                ENABLE_BACKUP=false
                shift
                ;;
            --no-cicd)
                ENABLE_CICD=false
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            --version)
                echo "vLLM Deployment Script v2.0"
                exit 0
                ;;
            *)
                error "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$API_KEY" ]]; then
        error "API key is required. Use --api-key to specify it."
    fi
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root. Use sudo ./deploy.sh"
    fi
    
    # Check OS
    if ! grep -q "Ubuntu 22.04" /etc/os-release 2>/dev/null; then
        warning "This script is optimized for Ubuntu 22.04. Continuing anyway..."
    fi
    
    # Create necessary directories
    mkdir -p "$LOG_DIR" "$CONFIG_DIR" "$BACKUP_DIR"
    
    # Check internet connectivity
    if ! ping -c 1 google.com &> /dev/null; then
        error "Internet connection required for deployment"
    fi
    
    success "Prerequisites check passed"
}

install_base_system() {
    log "Installing base system components..."
    
    # Run the existing setup script
    if [[ -f "$SCRIPT_DIR/setup.sh" ]]; then
        log "Running base setup script..."
        bash "$SCRIPT_DIR/setup.sh"
    else
        error "Base setup script not found at $SCRIPT_DIR/setup.sh"
    fi
    
    success "Base system installation completed"
}

setup_configuration() {
    log "Setting up configuration files..."
    
    # Create main configuration file
    cat > "$CONFIG_DIR/deployment.conf" << EOF
# vLLM Deployment Configuration
# Generated: $(date)
# Deployment ID: $DEPLOYMENT_ID

DEPLOYMENT_MODE="$DEPLOYMENT_MODE"
API_KEY="$API_KEY"
CONTEXT_LENGTH=$CONTEXT_LENGTH
ENABLE_MONITORING=$ENABLE_MONITORING
ENABLE_BACKUP=$ENABLE_BACKUP
ENABLE_CICD=$ENABLE_CICD

# Paths
MODEL_PATH="/models/qwen3"
VLLM_ENV_PATH="/opt/vllm"
LOG_DIR="$LOG_DIR"
BACKUP_DIR="$BACKUP_DIR"

# Performance settings based on mode
EOF

    case $DEPLOYMENT_MODE in
        "production")
            cat >> "$CONFIG_DIR/deployment.conf" << EOF
TENSOR_PARALLEL_SIZE=2
PIPELINE_PARALLEL_SIZE=2
GPU_MEMORY_UTILIZATION=0.98
KV_CACHE_DTYPE="fp8"
EOF
            ;;
        "development")
            cat >> "$CONFIG_DIR/deployment.conf" << EOF
TENSOR_PARALLEL_SIZE=4
PIPELINE_PARALLEL_SIZE=1
GPU_MEMORY_UTILIZATION=0.95
KV_CACHE_DTYPE="auto"
EOF
            ;;
        "testing")
            cat >> "$CONFIG_DIR/deployment.conf" << EOF
TENSOR_PARALLEL_SIZE=2
PIPELINE_PARALLEL_SIZE=1
GPU_MEMORY_UTILIZATION=0.90
KV_CACHE_DTYPE="auto"
EOF
            ;;
    esac
    
    # Create environment file
    cp "$SCRIPT_DIR/configs/environment-template.sh" "$CONFIG_DIR/environment.sh"
    sed -i "s/YOUR_API_KEY_HERE/$API_KEY/g" "$CONFIG_DIR/environment.sh"
    sed -i "s/200000/$CONTEXT_LENGTH/g" "$CONFIG_DIR/environment.sh"
    
    success "Configuration setup completed"
}

deploy_monitoring() {
    if [[ "$ENABLE_MONITORING" != "true" ]]; then
        log "Monitoring disabled, skipping..."
        return 0
    fi
    
    log "Deploying monitoring system..."
    bash "$SCRIPT_DIR/automation/monitoring/deploy-monitoring.sh" --config "$CONFIG_DIR/deployment.conf"
    success "Monitoring system deployed"
}

deploy_backup_system() {
    if [[ "$ENABLE_BACKUP" != "true" ]]; then
        log "Backup system disabled, skipping..."
        return 0
    fi
    
    log "Deploying backup system..."
    bash "$SCRIPT_DIR/automation/backup/deploy-backup.sh" --config "$CONFIG_DIR/deployment.conf"
    success "Backup system deployed"
}

deploy_cicd() {
    if [[ "$ENABLE_CICD" != "true" ]]; then
        log "CI/CD disabled, skipping..."
        return 0
    fi
    
    log "Deploying CI/CD pipeline..."
    bash "$SCRIPT_DIR/automation/cicd/deploy-pipeline.sh" --config "$CONFIG_DIR/deployment.conf"
    success "CI/CD pipeline deployed"
}

start_services() {
    log "Starting vLLM services..."
    
    # Source configuration
    source "$CONFIG_DIR/deployment.conf"
    
    # Start the server using production script
    if [[ -f "$SCRIPT_DIR/scripts/production/start-vllm-server.sh" ]]; then
        log "Starting vLLM server..."
        bash "$SCRIPT_DIR/scripts/production/start-vllm-server.sh" \
            --context-length "$CONTEXT_LENGTH" \
            --api-key "$API_KEY"
    else
        error "Production start script not found"
    fi
    
    # Enable systemd service
    systemctl enable vllm-server
    systemctl start vllm-server
    
    success "Services started successfully"
}

run_validation() {
    log "Running deployment validation..."
    
    # Run validation script
    bash "$SCRIPT_DIR/automation/validation/validate-deployment.sh" --config "$CONFIG_DIR/deployment.conf"
    
    success "Deployment validation completed"
}

generate_deployment_report() {
    log "Generating deployment report..."
    
    local report_file="$LOG_DIR/deployment-report-$DEPLOYMENT_ID.md"
    
    cat > "$report_file" << EOF
# vLLM Deployment Report

**Deployment ID**: $DEPLOYMENT_ID  
**Timestamp**: $(date)  
**Mode**: $DEPLOYMENT_MODE  
**Status**: SUCCESS  

## Configuration
- **Context Length**: $CONTEXT_LENGTH tokens
- **API Key**: ${API_KEY:0:8}... (masked)
- **Monitoring**: $ENABLE_MONITORING
- **Backup**: $ENABLE_BACKUP
- **CI/CD**: $ENABLE_CICD

## Services Status
EOF
    
    # Check service status
    if systemctl is-active --quiet vllm-server; then
        echo "- **vLLM Server**: ✅ Running" >> "$report_file"
    else
        echo "- **vLLM Server**: ❌ Not Running" >> "$report_file"
    fi
    
    if [[ "$ENABLE_MONITORING" == "true" ]]; then
        echo "- **Monitoring**: ✅ Deployed" >> "$report_file"
    fi
    
    if [[ "$ENABLE_BACKUP" == "true" ]]; then
        echo "- **Backup System**: ✅ Deployed" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

## Access Information
- **API Endpoint**: http://localhost:8000/v1
- **Health Check**: http://localhost:8000/health
- **Logs**: $LOG_DIR/
- **Configuration**: $CONFIG_DIR/

## Next Steps
1. Test the API endpoint: \`curl -H "Authorization: Bearer $API_KEY" http://localhost:8000/v1/models\`
2. Monitor logs: \`tail -f $LOG_DIR/vllm-*.log\`
3. Check system status: \`systemctl status vllm-server\`

## Support
- Configuration files: $CONFIG_DIR/
- Backup location: $BACKUP_DIR/
- Monitoring dashboard: http://localhost:3000 (if enabled)
EOF
    
    success "Deployment report generated: $report_file"
    
    # Display summary
    echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    DEPLOYMENT SUCCESSFUL                      ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "\n${CYAN}📋 Deployment Summary:${NC}"
    echo -e "   🆔 Deployment ID: $DEPLOYMENT_ID"
    echo -e "   🚀 Mode: $DEPLOYMENT_MODE"
    echo -e "   🌐 API Endpoint: http://localhost:8000/v1"
    echo -e "   📊 Context Length: $CONTEXT_LENGTH tokens"
    echo -e "   📄 Report: $report_file"
    echo -e "\n${YELLOW}🔑 Quick Test:${NC}"
    echo -e "   curl -H \"Authorization: Bearer $API_KEY\" http://localhost:8000/v1/models"
    echo -e "\n${YELLOW}📱 Management Commands:${NC}"
    echo -e "   • Check status: systemctl status vllm-server"
    echo -e "   • View logs: tail -f $LOG_DIR/vllm-*.log"
    echo -e "   • Restart: systemctl restart vllm-server"
}

cleanup_on_error() {
    error "Deployment failed. Running cleanup..."
    
    # Stop any running services
    systemctl stop vllm-server 2>/dev/null || true
    pkill -f vllm 2>/dev/null || true
    
    # Archive logs for debugging
    tar -czf "$LOG_DIR/failed-deployment-$DEPLOYMENT_ID.tar.gz" "$LOG_DIR/" 2>/dev/null || true
    
    error "Cleanup completed. Check logs in $LOG_DIR/ for details."
}

main() {
    # Set up error handling
    trap cleanup_on_error ERR
    
    show_banner
    parse_arguments "$@"
    
    info "Starting deployment with ID: $DEPLOYMENT_ID"
    info "Mode: $DEPLOYMENT_MODE | Context: $CONTEXT_LENGTH | Monitoring: $ENABLE_MONITORING"
    
    check_prerequisites
    install_base_system
    setup_configuration
    deploy_monitoring
    deploy_backup_system
    deploy_cicd
    start_services
    run_validation
    generate_deployment_report
    
    success "🎉 Deployment completed successfully!"
}

# Execute main function
main "$@"