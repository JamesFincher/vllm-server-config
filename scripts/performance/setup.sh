#!/bin/bash

# vLLM Performance Suite Setup Script
# Initializes the performance monitoring environment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[SETUP]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check system requirements
check_requirements() {
    log "Checking system requirements..."
    
    local missing_deps=()
    
    # Check required tools
    for cmd in curl jq bc; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        error "Missing required dependencies: ${missing_deps[*]}"
        echo "Install with: sudo apt-get install ${missing_deps[*]}"
        return 1
    fi
    
    # Check NVIDIA tools (optional)
    if ! command -v nvidia-smi &> /dev/null; then
        warning "nvidia-smi not found. GPU monitoring will be limited."
        echo "Install with: sudo apt-get install nvidia-utils"
    else
        success "NVIDIA tools found"
    fi
    
    success "System requirements check passed"
}

# Create directory structure
setup_directories() {
    log "Setting up directory structure..."
    
    local dirs=(
        "continuous_benchmark_data"
        "benchmark_history"
        "dashboard"
        "regression_analysis"
        "logs"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$SCRIPT_DIR/$dir"
        log "Created directory: $dir"
    done
    
    success "Directory structure created"
}

# Create default configuration files
create_configs() {
    log "Creating default configuration files..."
    
    # Continuous benchmark config
    if [ ! -f "$SCRIPT_DIR/continuous_benchmark_config.json" ]; then
        cat > "$SCRIPT_DIR/continuous_benchmark_config.json" << 'EOF'
{
    "api_key": "qwen3-secret-key",
    "base_url": "http://localhost:8000/v1",
    "benchmark_interval_minutes": 60,
    "retention_days": 30,
    "baseline_tps": 75.0,
    "regression_threshold": 0.15,
    "alerts": {
        "enabled": false,
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
            "enabled": false,
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
        success "Created continuous_benchmark_config.json"
    else
        log "continuous_benchmark_config.json already exists, skipping"
    fi
    
    # Regression detector config
    if [ ! -f "$SCRIPT_DIR/regression_config.json" ]; then
        cat > "$SCRIPT_DIR/regression_config.json" << 'EOF'
{
    "baseline_tps": 75.0,
    "baseline_response_time": 0.87,
    "thresholds": {
        "regression_percentage": 15.0,
        "warning_percentage": 10.0,
        "critical_percentage": 25.0
    },
    "statistical_analysis": {
        "enabled": true,
        "window_size": 20,
        "confidence_level": 0.95,
        "trend_detection": true,
        "anomaly_detection": true
    },
    "alerts": {
        "enabled": false,
        "webhook_url": "",
        "slack_webhook": "",
        "severity_levels": ["warning", "critical"]
    },
    "metrics": {
        "tokens_per_second": {
            "enabled": true,
            "weight": 1.0,
            "lower_is_better": false
        },
        "response_time": {
            "enabled": true,
            "weight": 0.8,
            "lower_is_better": true
        },
        "error_rate": {
            "enabled": true,
            "weight": 1.2,
            "lower_is_better": true
        }
    }
}
EOF
        success "Created regression_config.json"
    else
        log "regression_config.json already exists, skipping"
    fi
    
    # Environment configuration template
    if [ ! -f "$SCRIPT_DIR/.env.template" ]; then
        cat > "$SCRIPT_DIR/.env.template" << 'EOF'
# vLLM Performance Suite Environment Configuration
# Copy to .env and customize for your environment

# API Configuration
API_KEY=qwen3-secret-key
BASE_URL=http://localhost:8000/v1
MODEL_NAME=qwen3

# Performance Baselines (from production analysis)
PERFORMANCE_BASELINE_TPS=75.0
BASELINE_RESPONSE_TIME=0.87
REGRESSION_THRESHOLD=0.15

# GPU Monitoring Thresholds
ALERT_THRESHOLD_TEMP=85
ALERT_THRESHOLD_MEMORY=90

# Alerting Configuration
ENABLE_ALERTS=false
ENABLE_MONITORING=true
WEBHOOK_URL=
SLACK_WEBHOOK=

# Continuous Monitoring
BENCHMARK_INTERVAL_MINUTES=60
RETENTION_DAYS=30

# Load Testing
DEFAULT_LOAD_PROFILE=realistic
CONCURRENT_USERS=5
REQUEST_RATE=2
TEST_DURATION=300
EOF
        success "Created .env.template"
    else
        log ".env.template already exists, skipping"
    fi
}

# Initialize empty data files
initialize_data() {
    log "Initializing data files..."
    
    # Performance trends file
    local trends_file="$SCRIPT_DIR/continuous_benchmark_data/performance_trends.json"
    if [ ! -f "$trends_file" ]; then
        cat > "$trends_file" << 'EOF'
{
    "results": [],
    "metadata": {
        "created": "",
        "version": "2.0.0",
        "baseline_tps": 75.0
    }
}
EOF
        # Update timestamp
        local temp_file=$(mktemp)
        jq ".metadata.created = \"$(date -Iseconds)\"" "$trends_file" > "$temp_file" && mv "$temp_file" "$trends_file"
        success "Created performance_trends.json"
    fi
    
    # Regression analysis file
    local regression_file="$SCRIPT_DIR/benchmark_history/regression_analysis.json"
    if [ ! -f "$regression_file" ]; then
        echo '[]' > "$regression_file"
        success "Created regression_analysis.json"
    fi
}

# Set up scripts with proper permissions
setup_scripts() {
    log "Setting up script permissions..."
    
    chmod +x "$SCRIPT_DIR"/*.sh
    success "All scripts made executable"
}

# Test basic connectivity
test_connectivity() {
    log "Testing vLLM server connectivity..."
    
    local api_key="${1:-qwen3-secret-key}"
    local base_url="${2:-http://localhost:8000/v1}"
    
    if curl -s --max-time 10 "${base_url}/models" \
        -H "Authorization: Bearer ${api_key}" \
        -H "Content-Type: application/json" > /dev/null 2>&1; then
        success "vLLM server is accessible at $base_url"
        return 0
    else
        warning "Cannot connect to vLLM server at $base_url"
        warning "Make sure the server is running before starting monitoring"
        return 1
    fi
}

# Generate quick start script
create_quick_start() {
    local quick_start_script="$SCRIPT_DIR/quick-start.sh"
    
    cat > "$quick_start_script" << 'EOF'
#!/bin/bash

# Quick Start Script for vLLM Performance Suite
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 vLLM Performance Suite Quick Start"
echo "====================================="

# Load environment if exists
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

API_KEY="${API_KEY:-qwen3-secret-key}"
BASE_URL="${BASE_URL:-http://localhost:8000/v1}"

echo "1. Running quick benchmark test..."
if ./benchmark-suite.sh "$API_KEY" "$BASE_URL"; then
    echo "✅ Benchmark test completed successfully"
else
    echo "❌ Benchmark test failed - check your vLLM server"
    exit 1
fi

echo ""
echo "2. Starting GPU monitoring (30 seconds)..."
./gpu-monitor.sh 2 30 "logs/gpu_test_$(date +%Y%m%d_%H%M%S).log"

echo ""
echo "3. Running realistic load test..."
./load-tester.sh "$API_KEY" "$BASE_URL" realistic

echo ""
echo "4. Generating performance dashboard..."
./metrics-dashboard.sh continuous_benchmark_data dashboard

echo ""
echo "🎉 Quick start completed!"
echo ""
echo "📊 View dashboard: open dashboard/index.html"
echo "📈 Start continuous monitoring: ./continuous-benchmark.sh start"
echo "📋 View logs: ls -la logs/"
echo ""
echo "For more options, see README.md"
EOF
    
    chmod +x "$quick_start_script"
    success "Created quick-start.sh"
}

# Main setup function
main() {
    echo -e "${BLUE}"
    cat << 'EOF'
 _____ _     _     __  __   ____            __                                       
|  _  | |   | |   |  \/  | |  _ \ ___ _ __ / _| ___  _ __ _ __ ___   __ _ _ __   ___ ___ 
| | | | |   | |   | |\/| | | |_) / _ \ '__| |_ / _ \| '__| '_ ` _ \ / _` | '_ \ / __/ _ \
| |_| | |___| |___| |  | | |  __/  __/ |  |  _| (_) | |  | | | | | | (_| | | | | (_|  __/
 \___/|_____|_____|_|  |_| |_|   \___|_|  |_|  \___/|_|  |_| |_| |_|\__,_|_| |_|\___\___|
                                                                                        
 ____        _  _          
/ ___| _   _(_)| |_ ___    
\___ \| | | | || __/ _ \   
 ___) | |_| | || ||  __/   
|____/ \__,_|_| \__\___|   
                           
EOF
    echo -e "${NC}"
    
    echo "Production-Ready Performance Monitoring Suite"
    echo "============================================="
    echo ""
    
    # Run setup steps
    check_requirements || exit 1
    setup_directories
    create_configs
    initialize_data
    setup_scripts
    create_quick_start
    
    echo ""
    echo -e "${GREEN}🎉 Setup completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Configure your environment:"
    echo "   cp .env.template .env"
    echo "   # Edit .env with your settings"
    echo ""
    echo "2. Test the setup:"
    echo "   ./quick-start.sh"
    echo ""
    echo "3. Start continuous monitoring:"
    echo "   ./continuous-benchmark.sh start"
    echo ""
    echo "4. Generate dashboard:"
    echo "   ./metrics-dashboard.sh continuous_benchmark_data dashboard"
    echo ""
    echo -e "${YELLOW}For detailed usage instructions, see README.md${NC}"
    
    # Optional connectivity test
    echo ""
    read -p "Test vLLM server connectivity now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "API Key (default: qwen3-secret-key): " api_key
        read -p "Base URL (default: http://localhost:8000/v1): " base_url
        test_connectivity "${api_key:-qwen3-secret-key}" "${base_url:-http://localhost:8000/v1}"
    fi
    
    echo ""
    echo -e "${GREEN}Setup complete! Happy monitoring! 🚀${NC}"
}

# Run main function
main "$@"