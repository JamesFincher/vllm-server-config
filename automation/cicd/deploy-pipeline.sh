#!/bin/bash
# CI/CD Pipeline Deployment Script
# Sets up automated testing, deployment, and rollback pipelines

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE=""
PIPELINE_ROOT="/opt/vllm-cicd"
LOG_FILE="/var/log/vllm-deployment/cicd-deployment.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] [CICD]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

if [[ -z "$CONFIG_FILE" ]]; then
    error "Configuration file required. Use --config"
fi

# Source configuration
source "$CONFIG_FILE"

log "Deploying CI/CD pipeline..."

# Create pipeline directories
mkdir -p "$PIPELINE_ROOT"/{scripts,templates,workflows,tests,deployments}
mkdir -p /etc/vllm/cicd

# Create CI/CD configuration
cat > /etc/vllm/cicd/pipeline.conf << EOF
# vLLM CI/CD Pipeline Configuration
PIPELINE_ROOT="$PIPELINE_ROOT"
MODEL_PATH="$MODEL_PATH"
VLLM_ENV_PATH="$VLLM_ENV_PATH"
API_KEY="$API_KEY"
CONTEXT_LENGTH=$CONTEXT_LENGTH

# Git configuration
GIT_REPO=""
GIT_BRANCH="main"
GIT_TOKEN=""

# Deployment stages
ENABLE_TESTING=true
ENABLE_STAGING=true
ENABLE_PRODUCTION=true

# Test configuration
TEST_TIMEOUT=300
PERFORMANCE_THRESHOLD=10.0
API_TIMEOUT=30

# Rollback configuration
ENABLE_AUTO_ROLLBACK=true
ROLLBACK_THRESHOLD=3
HEALTH_CHECK_RETRIES=5

# Notifications
SLACK_WEBHOOK=""
EMAIL_NOTIFICATIONS=""
EOF

# Install Git hooks
mkdir -p "$PIPELINE_ROOT/hooks"

cat > "$PIPELINE_ROOT/hooks/pre-commit" << 'EOF'
#!/bin/bash
# Pre-commit hook for vLLM configuration validation

echo "Running pre-commit checks..."

# Check configuration files syntax
for config in configs/*.sh configs/*.json; do
    if [[ -f "$config" ]]; then
        case "$config" in
            *.sh)
                bash -n "$config" || { echo "Syntax error in $config"; exit 1; }
                ;;
            *.json)
                python3 -m json.tool "$config" > /dev/null || { echo "Invalid JSON in $config"; exit 1; }
                ;;
        esac
    fi
done

# Check for sensitive information
if grep -r "YOUR_API_KEY_HERE\|your-secret-key\|password123" . --exclude-dir=.git; then
    echo "Error: Found placeholder or test credentials in code"
    exit 1
fi

echo "Pre-commit checks passed"
EOF

chmod +x "$PIPELINE_ROOT/hooks/pre-commit"

success "CI/CD configuration created"

# Install pipeline manager
cp "$SCRIPT_DIR/pipeline-manager.sh" /usr/local/bin/vllm-pipeline
chmod +x /usr/local/bin/vllm-pipeline

# Create GitHub Actions workflow template
mkdir -p "$PIPELINE_ROOT/templates/github-actions"
cat > "$PIPELINE_ROOT/templates/github-actions/vllm-deploy.yml" << 'EOF'
name: vLLM Deployment Pipeline

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Validate Configuration
      run: |
        # Validate JSON configs
        find . -name "*.json" -exec python3 -m json.tool {} \; > /dev/null
        
        # Validate shell scripts
        find . -name "*.sh" -exec bash -n {} \;
        
        # Check for secrets
        if grep -r "YOUR_API_KEY_HERE\|your-secret-key" . --exclude-dir=.git; then
          echo "Error: Found placeholder credentials"
          exit 1
        fi

  deploy-test:
    needs: validate
    runs-on: self-hosted
    if: github.ref == 'refs/heads/develop'
    steps:
    - uses: actions/checkout@v3
    
    - name: Deploy to Test
      run: |
        sudo /usr/local/bin/vllm-pipeline deploy test
        
  deploy-staging:
    needs: validate
    runs-on: self-hosted
    if: github.ref == 'refs/heads/main'
    steps:
    - uses: actions/checkout@v3
    
    - name: Deploy to Staging
      run: |
        sudo /usr/local/bin/vllm-pipeline deploy staging

  deploy-production:
    needs: deploy-staging
    runs-on: self-hosted
    if: github.ref == 'refs/heads/main' && contains(github.event.head_commit.message, '[deploy-prod]')
    steps:
    - uses: actions/checkout@v3
    
    - name: Deploy to Production
      run: |
        sudo /usr/local/bin/vllm-pipeline deploy production
EOF

# Create GitLab CI template
cat > "$PIPELINE_ROOT/templates/gitlab-ci/.gitlab-ci.yml" << 'EOF'
stages:
  - validate
  - test
  - staging
  - production

variables:
  VLLM_PIPELINE: "/usr/local/bin/vllm-pipeline"

validate_config:
  stage: validate
  script:
    - find . -name "*.json" -exec python3 -m json.tool {} \; > /dev/null
    - find . -name "*.sh" -exec bash -n {} \;
    - |
      if grep -r "YOUR_API_KEY_HERE\|your-secret-key" . --exclude-dir=.git; then
        echo "Error: Found placeholder credentials"
        exit 1
      fi

deploy_test:
  stage: test
  script:
    - sudo $VLLM_PIPELINE deploy test
  only:
    - develop

deploy_staging:
  stage: staging
  script:
    - sudo $VLLM_PIPELINE deploy staging
  only:
    - main

deploy_production:
  stage: production
  script:
    - sudo $VLLM_PIPELINE deploy production
  only:
    - main
  when: manual
EOF

# Create Jenkins pipeline template
cat > "$PIPELINE_ROOT/templates/jenkins/Jenkinsfile" << 'EOF'
pipeline {
    agent any
    
    environment {
        VLLM_PIPELINE = '/usr/local/bin/vllm-pipeline'
    }
    
    stages {
        stage('Validate') {
            steps {
                script {
                    sh 'find . -name "*.json" -exec python3 -m json.tool {} \\; > /dev/null'
                    sh 'find . -name "*.sh" -exec bash -n {} \\;'
                    
                    def secretCheck = sh(
                        script: 'grep -r "YOUR_API_KEY_HERE\\|your-secret-key" . --exclude-dir=.git || true',
                        returnStdout: true
                    ).trim()
                    
                    if (secretCheck) {
                        error("Found placeholder credentials in code")
                    }
                }
            }
        }
        
        stage('Test Deploy') {
            when {
                branch 'develop'
            }
            steps {
                sh 'sudo $VLLM_PIPELINE deploy test'
            }
        }
        
        stage('Staging Deploy') {
            when {
                branch 'main'
            }
            steps {
                sh 'sudo $VLLM_PIPELINE deploy staging'
            }
        }
        
        stage('Production Deploy') {
            when {
                allOf {
                    branch 'main'
                    expression { env.BUILD_CAUSE == 'MANUAL' }
                }
            }
            steps {
                input message: 'Deploy to production?', ok: 'Deploy'
                sh 'sudo $VLLM_PIPELINE deploy production'
            }
        }
    }
    
    post {
        failure {
            script {
                if (env.BRANCH_NAME == 'main') {
                    sh 'sudo $VLLM_PIPELINE rollback'
                }
            }
        }
    }
}
EOF

# Create test suite
cat > "$PIPELINE_ROOT/tests/integration-tests.sh" << 'EOF'
#!/bin/bash
# Integration test suite for vLLM deployment

set -euo pipefail

API_ENDPOINT="http://localhost:8000"
API_KEY="${VLLM_API_KEY:-}"
TIMEOUT=30

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

test_count=0
passed_tests=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    ((test_count++))
    echo -n "Running $test_name... "
    
    if eval "$test_command" > /dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        ((passed_tests++))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        return 1
    fi
}

# Test API health endpoint
run_test "Health Endpoint" \
    "curl -f -s --max-time $TIMEOUT '$API_ENDPOINT/health'"

# Test models endpoint
run_test "Models Endpoint" \
    "curl -f -s --max-time $TIMEOUT -H 'Authorization: Bearer $API_KEY' '$API_ENDPOINT/v1/models'"

# Test completion endpoint
run_test "Completion Endpoint" \
    "curl -f -s --max-time $TIMEOUT -H 'Authorization: Bearer $API_KEY' -H 'Content-Type: application/json' -d '{\"model\":\"qwen3\",\"messages\":[{\"role\":\"user\",\"content\":\"Say OK\"}],\"max_tokens\":5}' '$API_ENDPOINT/v1/chat/completions'"

# Test GPU memory usage
run_test "GPU Memory Check" \
    "nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | awk '\$1 > 1000 {count++} END {exit (count >= 2 ? 0 : 1)}'"

# Test service status
run_test "Service Status" \
    "systemctl is-active --quiet vllm-server"

# Test log files
run_test "Log Files Exist" \
    "test -f /var/log/vllm/vllm-*.log"

echo
echo "Test Results: $passed_tests/$test_count tests passed"

if [ $passed_tests -eq $test_count ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
EOF

chmod +x "$PIPELINE_ROOT/tests/integration-tests.sh"

# Create deployment wrapper script
cat > /usr/local/bin/vllm-deploy << 'EOF'
#!/bin/bash
# vLLM Deployment Wrapper Script

case "$1" in
    "quick")
        echo "Running quick deployment to test environment..."
        /usr/local/bin/vllm-pipeline deploy test
        ;;
    "full")
        echo "Running full deployment pipeline..."
        /usr/local/bin/vllm-pipeline deploy test
        /usr/local/bin/vllm-pipeline deploy staging
        echo "Ready for production deployment. Run: vllm-deploy production"
        ;;
    "production")
        echo "Deploying to production..."
        read -p "Are you sure you want to deploy to production? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            /usr/local/bin/vllm-pipeline deploy production
        else
            echo "Production deployment cancelled"
        fi
        ;;
    "rollback")
        echo "Rolling back deployment..."
        /usr/local/bin/vllm-pipeline rollback
        ;;
    "status")
        /usr/local/bin/vllm-pipeline status
        ;;
    *)
        echo "Usage: $0 {quick|full|production|rollback|status}"
        echo ""
        echo "Commands:"
        echo "  quick      - Quick test deployment"
        echo "  full       - Full pipeline (test + staging)"
        echo "  production - Deploy to production (with confirmation)"
        echo "  rollback   - Rollback to previous version"
        echo "  status     - Show deployment status"
        echo ""
        echo "Advanced usage:"
        echo "  vllm-pipeline - Full pipeline manager with more options"
        ;;
esac
EOF

chmod +x /usr/local/bin/vllm-deploy

# Create systemd timer for automated deployments (optional)
cat > /etc/systemd/system/vllm-auto-deploy.service << EOF
[Unit]
Description=vLLM Automated Deployment Check
After=network.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/vllm-pipeline validate
EOF

cat > /etc/systemd/system/vllm-auto-deploy.timer << EOF
[Unit]
Description=Run vLLM deployment validation
Requires=vllm-auto-deploy.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Don't enable auto-deployment by default - it should be manually enabled
# systemctl enable vllm-auto-deploy.timer

success "CI/CD pipeline deployed successfully"
log "Commands available:"
log "  - vllm-pipeline: Full pipeline manager"
log "  - vllm-deploy: Simplified deployment wrapper"
log "Templates created:"
log "  - GitHub Actions: $PIPELINE_ROOT/templates/github-actions/"
log "  - GitLab CI: $PIPELINE_ROOT/templates/gitlab-ci/"
log "  - Jenkins: $PIPELINE_ROOT/templates/jenkins/"