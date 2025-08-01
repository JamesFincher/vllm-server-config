#!/bin/bash
# Health Monitoring System Deployment Script
# Deploys comprehensive monitoring and alerting for vLLM server

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE=""
MONITORING_ROOT="/opt/vllm-monitoring"
LOG_FILE="/var/log/vllm-deployment/monitoring-deployment.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] [MONITORING]${NC} $1" | tee -a "$LOG_FILE"
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

log "Deploying monitoring system..."

# Create monitoring directories
mkdir -p "$MONITORING_ROOT"/{scripts,config,logs,data,dashboards}
mkdir -p /etc/vllm/monitoring

# Install monitoring dependencies
log "Installing monitoring dependencies..."
apt-get update
apt-get install -y curl jq htop iotop nethogs python3-pip

# Install Python monitoring packages
pip3 install psutil nvidia-ml-py3 prometheus-client flask requests

# Create monitoring configuration
cat > /etc/vllm/monitoring/monitor.conf << EOF
# vLLM Monitoring Configuration
MONITORING_ROOT="$MONITORING_ROOT"
API_ENDPOINT="http://localhost:8000"
API_KEY="$API_KEY"

# Monitoring intervals (seconds)
HEALTH_CHECK_INTERVAL=30
PERFORMANCE_CHECK_INTERVAL=60
GPU_CHECK_INTERVAL=30
SYSTEM_CHECK_INTERVAL=60

# Thresholds
GPU_MEMORY_THRESHOLD=95
GPU_TEMP_THRESHOLD=85
CPU_THRESHOLD=90
MEMORY_THRESHOLD=90
DISK_THRESHOLD=85

# Response time thresholds (seconds)
API_RESPONSE_THRESHOLD=5.0
GENERATION_TIME_THRESHOLD=30.0

# Alerting
ENABLE_SLACK_ALERTS=false
SLACK_WEBHOOK=""
ENABLE_EMAIL_ALERTS=false
EMAIL_RECIPIENTS=""

# Logging
LOG_LEVEL="INFO"
RETAIN_LOGS_DAYS=30
EOF

success "Monitoring configuration created"

# Install health monitor script
cp "$SCRIPT_DIR/health-monitor.py" "$MONITORING_ROOT/scripts/"
chmod +x "$MONITORING_ROOT/scripts/health-monitor.py"

# Create systemd service for continuous monitoring
cat > /etc/systemd/system/vllm-health-monitor.service << EOF
[Unit]
Description=vLLM Health Monitor
After=network.target
Wants=vllm-server.service

[Service]
Type=simple
User=root
WorkingDirectory=$MONITORING_ROOT
ExecStart=/usr/bin/python3 $MONITORING_ROOT/scripts/health-monitor.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create dashboard script
cat > "$MONITORING_ROOT/scripts/dashboard.py" << 'EOF'
#!/usr/bin/env python3
"""
Simple web dashboard for vLLM monitoring
"""

import json
import os
from datetime import datetime, timedelta
from pathlib import Path
from flask import Flask, render_template_string, jsonify
import glob

app = Flask(__name__)

MONITORING_ROOT = os.environ.get('MONITORING_ROOT', '/opt/vllm-monitoring')

DASHBOARD_HTML = """
<!DOCTYPE html>
<html>
<head>
    <title>vLLM Health Dashboard</title>
    <meta http-equiv="refresh" content="30">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; }
        .card { background: white; padding: 20px; margin: 10px 0; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .status-ok { color: #28a745; font-weight: bold; }
        .status-error { color: #dc3545; font-weight: bold; }
        .metric { display: inline-block; margin: 10px 20px 10px 0; }
        .metric-label { font-weight: bold; }
        .progress-bar { width: 200px; height: 20px; background: #e9ecef; border-radius: 10px; overflow: hidden; display: inline-block; }
        .progress-fill { height: 100%; background: #007bff; }
        .progress-fill.warning { background: #ffc107; }
        .progress-fill.danger { background: #dc3545; }
        h1, h2 { color: #333; }
        .timestamp { color: #666; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 vLLM Health Dashboard</h1>
        
        <div class="card">
            <h2>📊 System Status</h2>
            <div class="timestamp">Last updated: {{ timestamp }}</div>
            {% if metrics %}
                <div class="metric">
                    <span class="metric-label">API Status:</span>
                    <span class="{{ 'status-ok' if metrics.api_health.overall_status else 'status-error' }}">
                        {{ 'HEALTHY' if metrics.api_health.overall_status else 'UNHEALTHY' }}
                    </span>
                </div>
                
                {% if metrics.gpu_status.available and metrics.gpu_status.gpus %}
                <h3>🎮 GPU Status</h3>
                {% for gpu in metrics.gpu_status.gpus %}
                <div class="metric">
                    <span class="metric-label">GPU {{ gpu.index }} ({{ gpu.name }}):</span>
                    <div class="progress-bar">
                        <div class="progress-fill {{ 'danger' if gpu.memory.used_percent > 95 else 'warning' if gpu.memory.used_percent > 85 else '' }}" 
                             style="width: {{ gpu.memory.used_percent }}%"></div>
                    </div>
                    {{ "%.1f"|format(gpu.memory.used_percent) }}% ({{ gpu.temperature }}°C)
                </div>
                {% endfor %}
                {% endif %}
                
                <h3>💻 System Resources</h3>
                <div class="metric">
                    <span class="metric-label">CPU:</span>
                    <div class="progress-bar">
                        <div class="progress-fill {{ 'danger' if metrics.system_resources.cpu.usage_percent > 90 else 'warning' if metrics.system_resources.cpu.usage_percent > 75 else '' }}" 
                             style="width: {{ metrics.system_resources.cpu.usage_percent }}%"></div>
                    </div>
                    {{ "%.1f"|format(metrics.system_resources.cpu.usage_percent) }}%
                </div>
                
                <div class="metric">
                    <span class="metric-label">Memory:</span>
                    <div class="progress-bar">
                        <div class="progress-fill {{ 'danger' if metrics.system_resources.memory.used_percent > 90 else 'warning' if metrics.system_resources.memory.used_percent > 75 else '' }}" 
                             style="width: {{ metrics.system_resources.memory.used_percent }}%"></div>
                    </div>
                    {{ "%.1f"|format(metrics.system_resources.memory.used_percent) }}%
                </div>
                
                <div class="metric">
                    <span class="metric-label">Disk:</span>
                    <div class="progress-bar">
                        <div class="progress-fill {{ 'danger' if metrics.system_resources.disk.used_percent > 85 else 'warning' if metrics.system_resources.disk.used_percent > 75 else '' }}" 
                             style="width: {{ metrics.system_resources.disk.used_percent }}%"></div>
                    </div>
                    {{ "%.1f"|format(metrics.system_resources.disk.used_percent) }}%
                </div>
                
                <h3>⚡ Performance</h3>
                {% if metrics.api_health.health_endpoint %}
                <div class="metric">
                    <span class="metric-label">Health Check:</span>
                    {{ "%.3f"|format(metrics.api_health.health_endpoint.response_time) }}s
                </div>
                {% endif %}
                
                {% if metrics.api_health.generation_test %}
                <div class="metric">
                    <span class="metric-label">Generation Test:</span>
                    {{ "%.3f"|format(metrics.api_health.generation_test.response_time) }}s
                </div>
                {% endif %}
                
            {% else %}
                <p class="status-error">No monitoring data available</p>
            {% endif %}
        </div>
        
        <div class="card">
            <h2>📈 Recent Activity</h2>
            <p>Auto-refresh every 30 seconds</p>
            {% if recent_logs %}
                <pre style="background: #f8f9fa; padding: 10px; border-radius: 4px; font-size: 0.9em;">{{ recent_logs }}</pre>
            {% else %}
                <p>No recent logs available</p>
            {% endif %}
        </div>
    </div>
</body>
</html>
"""

def get_latest_metrics():
    """Get the latest metrics from monitoring data"""
    data_dir = Path(MONITORING_ROOT) / 'data'
    if not data_dir.exists():
        return None
    
    # Find today's metrics file
    today = datetime.now().strftime('%Y-%m-%d')
    metrics_file = data_dir / f"metrics-{today}.jsonl"
    
    if not metrics_file.exists():
        # Try yesterday's file
        yesterday = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')
        metrics_file = data_dir / f"metrics-{yesterday}.jsonl"
    
    if not metrics_file.exists():
        return None
    
    try:
        # Read last line (most recent metrics)
        with open(metrics_file, 'r') as f:
            lines = f.readlines()
            if lines:
                return json.loads(lines[-1].strip())
    except Exception:
        pass
    
    return None

def get_recent_logs():
    """Get recent log entries"""
    log_dir = Path(MONITORING_ROOT) / 'logs'
    if not log_dir.exists():
        return ""
    
    today = datetime.now().strftime('%Y-%m-%d')
    log_file = log_dir / f"health-monitor-{today}.log"
    
    if not log_file.exists():
        return ""
    
    try:
        with open(log_file, 'r') as f:
            lines = f.readlines()
            return ''.join(lines[-20:])  # Last 20 lines
    except Exception:
        return ""

@app.route('/')
def dashboard():
    metrics = get_latest_metrics()
    recent_logs = get_recent_logs()
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    
    return render_template_string(DASHBOARD_HTML, 
                                metrics=metrics, 
                                recent_logs=recent_logs,
                                timestamp=timestamp)

@app.route('/api/metrics')
def api_metrics():
    return jsonify(get_latest_metrics())

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000, debug=False)
EOF

chmod +x "$MONITORING_ROOT/scripts/dashboard.py"

# Create dashboard service
cat > /etc/systemd/system/vllm-dashboard.service << EOF
[Unit]
Description=vLLM Monitoring Dashboard
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$MONITORING_ROOT
Environment=MONITORING_ROOT=$MONITORING_ROOT
ExecStart=/usr/bin/python3 $MONITORING_ROOT/scripts/dashboard.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create monitoring management script
cat > /usr/local/bin/vllm-monitor << 'EOF'
#!/bin/bash
# vLLM Monitoring Management Script

case "$1" in
    "start")
        systemctl start vllm-health-monitor
        systemctl start vllm-dashboard
        echo "Monitoring services started"
        ;;
    "stop")
        systemctl stop vllm-health-monitor
        systemctl stop vllm-dashboard
        echo "Monitoring services stopped"
        ;;
    "status")
        echo "=== vLLM Monitoring Status ==="
        systemctl status vllm-health-monitor --no-pager -l
        systemctl status vllm-dashboard --no-pager -l
        ;;
    "logs")
        echo "=== Recent Health Monitor Logs ==="
        journalctl -u vllm-health-monitor --no-pager -n 20
        ;;
    "dashboard")
        echo "Dashboard available at: http://localhost:3000"
        ;;
    "check")
        python3 /opt/vllm-monitoring/scripts/health-monitor.py --check-once
        ;;
    *)
        echo "Usage: $0 {start|stop|status|logs|dashboard|check}"
        echo ""
        echo "Commands:"
        echo "  start     - Start monitoring services"
        echo "  stop      - Stop monitoring services"
        echo "  status    - Show service status"
        echo "  logs      - Show recent logs"
        echo "  dashboard - Show dashboard URL"
        echo "  check     - Run single health check"
        ;;
esac
EOF

chmod +x /usr/local/bin/vllm-monitor

# Enable and start services
systemctl daemon-reload
systemctl enable vllm-health-monitor
systemctl enable vllm-dashboard
systemctl start vllm-health-monitor
systemctl start vllm-dashboard

success "Monitoring system deployed successfully"
log "Services:"
log "  - Health Monitor: systemctl status vllm-health-monitor"
log "  - Dashboard: http://localhost:3000"
log "Commands:"
log "  - vllm-monitor: Main monitoring control script"
log "  - vllm-monitor dashboard: Show dashboard URL"
log "  - vllm-monitor check: Run single health check"