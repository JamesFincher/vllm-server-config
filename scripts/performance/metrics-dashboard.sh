#!/bin/bash

# Performance Metrics Dashboard Generator
# Creates comprehensive real-time and historical performance dashboards
# Usage: ./metrics-dashboard.sh [DATA_DIR] [OUTPUT_DIR]

set -euo pipefail

# Configuration
DATA_DIR="${1:-continuous_benchmark_data}"
OUTPUT_DIR="${2:-dashboard}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Dashboard configuration
DASHBOARD_CONFIG=$(cat << 'EOF'
{
    "dashboard_title": "vLLM Performance Metrics Dashboard",
    "refresh_interval_seconds": 30,
    "time_windows": {
        "last_hour": 3600,
        "last_day": 86400,
        "last_week": 604800,
        "last_month": 2592000
    },
    "metrics": {
        "tokens_per_second": {
            "label": "Tokens per Second",
            "unit": "tok/s",
            "baseline": 75.0,
            "target": 80.0,
            "color": "#3498db"
        },
        "response_time": {
            "label": "Response Time",
            "unit": "seconds",
            "baseline": 0.87,
            "target": 0.8,
            "color": "#e74c3c"
        },
        "gpu_utilization": {
            "label": "GPU Utilization",
            "unit": "%",
            "baseline": 80.0,
            "target": 85.0,
            "color": "#2ecc71"
        },
        "memory_usage": {
            "label": "Memory Usage",
            "unit": "%",
            "baseline": 70.0,
            "target": 75.0,
            "color": "#f39c12"
        }
    },
    "alerts": {
        "performance_degradation": {
            "threshold": 15.0,
            "message": "Performance degradation detected"
        },
        "high_response_time": {
            "threshold": 2.0,
            "message": "Response time above threshold"
        }
    }
}
EOF
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

mkdir -p "$OUTPUT_DIR"

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Collect and aggregate performance data
collect_performance_data() {
    local output_file="$1"
    
    log "Collecting performance data from: $DATA_DIR"
    
    # Initialize aggregated data structure
    cat > "$output_file" << 'EOF'
{
    "collection_timestamp": "",
    "data_sources": [],
    "aggregated_metrics": {
        "tokens_per_second": [],
        "response_time": [],
        "gpu_utilization": [],
        "memory_usage": [],
        "error_rate": []
    },
    "summary_statistics": {},
    "recent_alerts": [],
    "performance_trends": {}
}
EOF
    
    # Update timestamp
    local temp_file=$(mktemp)
    jq ".collection_timestamp = \"$(date -Iseconds)\"" "$output_file" > "$temp_file" && mv "$temp_file" "$output_file"
    
    # Collect from trends file
    if [ -f "${DATA_DIR}/performance_trends.json" ]; then
        log "Processing performance trends data..."
        process_trends_data "${DATA_DIR}/performance_trends.json" "$output_file"
    fi
    
    # Collect from benchmark results
    for benchmark_dir in "${DATA_DIR}"/benchmark_*; do
        if [ -d "$benchmark_dir" ]; then
            log "Processing benchmark data: $(basename "$benchmark_dir")"
            process_benchmark_data "$benchmark_dir" "$output_file"
        fi
    done
    
    # Collect from load test results
    for load_dir in "${DATA_DIR}"/load_test_*; do
        if [ -d "$load_dir" ]; then
            log "Processing load test data: $(basename "$load_dir")"
            process_load_test_data "$load_dir" "$output_file"
        fi
    done
    
    # Generate summary statistics
    generate_summary_statistics "$output_file"
    
    success "Data collection completed"
}

# Process trends data
process_trends_data() {
    local trends_file="$1"
    local output_file="$2"
    
    # Extract recent results (last 24 hours)
    local cutoff_time=$(date -d "24 hours ago" -Iseconds)
    local recent_data=$(jq --arg cutoff "$cutoff_time" '
        .results[] | 
        select(.timestamp >= $cutoff and .tokens_per_second != null)
    ' "$trends_file" 2>/dev/null || echo '[]')
    
    if [ "$recent_data" != "[]" ] && [ -n "$recent_data" ]; then
        # Add to aggregated metrics
        local temp_file=$(mktemp)
        echo "$recent_data" | jq -s '.' | jq --slurpfile existing "$output_file" '
            $existing[0] as $data |
            $data.aggregated_metrics.tokens_per_second += (map(select(.tokens_per_second != null) | {timestamp: .timestamp, value: .tokens_per_second})) |
            $data.aggregated_metrics.response_time += (map(select(.duration_seconds != null) | {timestamp: .timestamp, value: .duration_seconds})) |
            $data.data_sources += ["performance_trends.json"] |
            $data
        ' > "$temp_file" && mv "$temp_file" "$output_file"
    fi
}

# Process benchmark data
process_benchmark_data() {
    local benchmark_dir="$1"
    local output_file="$2"
    
    # Process individual test results
    for test_file in "$benchmark_dir"/test_*.json; do
        if [ -f "$test_file" ]; then
            local test_data=$(jq '{
                timestamp: .timestamp,
                tokens_per_second: .tokens_per_second,
                duration_seconds: .duration_seconds,
                test_type: "benchmark"
            }' "$test_file" 2>/dev/null || echo '{}')
            
            if [ "$test_data" != "{}" ]; then
                local temp_file=$(mktemp)
                jq --argjson data "$test_data" '
                    .aggregated_metrics.tokens_per_second += [
                        {timestamp: $data.timestamp, value: $data.tokens_per_second}
                    ] |
                    .aggregated_metrics.response_time += [
                        {timestamp: $data.timestamp, value: $data.duration_seconds}
                    ]
                ' "$output_file" > "$temp_file" && mv "$temp_file" "$output_file"
            fi
        fi
    done
    
    # Add data source
    local temp_file=$(mktemp)
    jq --arg source "$(basename "$benchmark_dir")" '.data_sources += [$source] | .data_sources |= unique' "$output_file" > "$temp_file" && mv "$temp_file" "$output_file"
}

# Process load test data
process_load_test_data() {
    local load_dir="$1"
    local output_file="$2"
    
    local metrics_file="$load_dir/load_metrics.json"
    if [ -f "$metrics_file" ]; then
        local load_data=$(jq '{
            timestamp: .load_test_summary.timestamp,
            avg_tokens_per_second: .performance_metrics.avg_tokens_per_sec,
            avg_response_time: .performance_metrics.avg_response_time,
            error_rate: .error_analysis.error_rate_pct,
            test_type: "load_test"
        }' "$metrics_file" 2>/dev/null || echo '{}')
        
        if [ "$load_data" != "{}" ]; then
            local temp_file=$(mktemp)
            jq --argjson data "$load_data" '
                .aggregated_metrics.tokens_per_second += [
                    {timestamp: $data.timestamp, value: $data.avg_tokens_per_second}
                ] |
                .aggregated_metrics.response_time += [
                    {timestamp: $data.timestamp, value: $data.avg_response_time}
                ] |
                .aggregated_metrics.error_rate += [
                    {timestamp: $data.timestamp, value: $data.error_rate}
                ]
            ' "$output_file" > "$temp_file" && mv "$temp_file" "$output_file"
        fi
    fi
    
    # Add data source
    local temp_file=$(mktemp)
    jq --arg source "$(basename "$load_dir")" '.data_sources += [$source] | .data_sources |= unique' "$output_file" > "$temp_file" && mv "$temp_file" "$output_file"
}

# Generate summary statistics
generate_summary_statistics() {
    local output_file="$1"
    
    log "Generating summary statistics..."
    
    local temp_file=$(mktemp)
    jq '
        def calculate_stats(data):
            data | map(.value) | 
            if length > 0 then
                {
                    count: length,
                    mean: (add / length),
                    min: min,
                    max: max,
                    latest: .[-1]
                }
            else
                {count: 0, mean: null, min: null, max: null, latest: null}
            end;
        
        .summary_statistics = {
            tokens_per_second: calculate_stats(.aggregated_metrics.tokens_per_second),
            response_time: calculate_stats(.aggregated_metrics.response_time),
            error_rate: calculate_stats(.aggregated_metrics.error_rate)
        }
    ' "$output_file" > "$temp_file" && mv "$temp_file" "$output_file"
}

# Generate main dashboard HTML
generate_dashboard_html() {
    local data_file="$1"
    local dashboard_file="${OUTPUT_DIR}/index.html"
    
    log "Generating main dashboard: $dashboard_file"
    
    cat > "$dashboard_file" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>vLLM Performance Dashboard</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns/dist/chartjs-adapter-date-fns.bundle.min.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f5f5f5; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; text-align: center; }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .card { background: white; border-radius: 10px; padding: 20px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        .metric-card { text-align: center; }
        .metric-value { font-size: 2.5em; font-weight: bold; margin: 10px 0; }
        .metric-label { color: #666; font-size: 0.9em; text-transform: uppercase; letter-spacing: 1px; }
        .metric-change { font-size: 0.9em; margin-top: 5px; }
        .positive { color: #27ae60; }
        .negative { color: #e74c3c; }
        .neutral { color: #7f8c8d; }
        .chart-container { height: 400px; margin: 20px 0; }
        .status-indicator { display: inline-block; width: 12px; height: 12px; border-radius: 50%; margin-right: 8px; }
        .status-good { background: #27ae60; }
        .status-warning { background: #f39c12; }
        .status-critical { background: #e74c3c; }
        .alerts { background: #fff3cd; border: 1px solid #ffeaa7; border-radius: 5px; padding: 15px; margin: 20px 0; }
        .refresh-info { text-align: center; color: #666; margin: 20px 0; }
        .tabs { display: flex; background: white; border-radius: 10px; margin-bottom: 20px; overflow: hidden; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .tab { flex: 1; padding: 15px; text-align: center; cursor: pointer; border-bottom: 3px solid transparent; transition: all 0.3s; }
        .tab:hover { background: #f8f9fa; }
        .tab.active { border-bottom-color: #667eea; background: #f8f9fa; }
        .tab-content { display: none; }
        .tab-content.active { display: block; }
        .data-table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        .data-table th, .data-table td { padding: 12px; text-align: left; border-bottom: 1px solid #eee; }
        .data-table th { background: #f8f9fa; font-weight: 600; }
        .performance-badge { padding: 4px 8px; border-radius: 4px; font-size: 0.8em; font-weight: bold; }
        .badge-excellent { background: #d4edda; color: #155724; }
        .badge-good { background: #cce5ff; color: #004085; }
        .badge-warning { background: #fff3cd; color: #856404; }
        .badge-poor { background: #f8d7da; color: #721c24; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🚀 vLLM Performance Dashboard</h1>
        <p>Real-time performance monitoring and analytics</p>
        <p id="last-updated">Last updated: --</p>
    </div>

    <div class="container">
        <div class="refresh-info">
            <span class="status-indicator status-good"></span>
            Auto-refresh enabled (30 seconds) | 
            <button onclick="refreshData()" style="padding: 5px 10px; border: 1px solid #ccc; border-radius: 3px; background: white; cursor: pointer;">Refresh Now</button>
        </div>

        <!-- Key Performance Indicators -->
        <div class="grid" id="kpi-cards">
            <!-- KPI cards will be inserted here -->
        </div>

        <!-- Alerts Section -->
        <div id="alerts-section" style="display: none;">
            <div class="alerts">
                <h3>🚨 Active Alerts</h3>
                <div id="alerts-content"></div>
            </div>
        </div>

        <!-- Tabs for different views -->
        <div class="tabs">
            <div class="tab active" onclick="showTab('overview')">Overview</div>
            <div class="tab" onclick="showTab('performance')">Performance Trends</div>
            <div class="tab" onclick="showTab('analytics')">Analytics</div>
            <div class="tab" onclick="showTab('system')">System Health</div>
        </div>

        <!-- Overview Tab -->
        <div id="overview" class="tab-content active">
            <div class="card">
                <h2>Performance Overview</h2>
                <div class="chart-container">
                    <canvas id="overviewChart"></canvas>
                </div>
            </div>
        </div>

        <!-- Performance Trends Tab -->
        <div id="performance" class="tab-content">
            <div class="grid">
                <div class="card">
                    <h3>Tokens per Second</h3>
                    <div class="chart-container">
                        <canvas id="tpsChart"></canvas>
                    </div>
                </div>
                <div class="card">
                    <h3>Response Time</h3>
                    <div class="chart-container">
                        <canvas id="responseChart"></canvas>
                    </div>
                </div>
            </div>
        </div>

        <!-- Analytics Tab -->
        <div id="analytics" class="tab-content">
            <div class="card">
                <h2>Performance Analytics</h2>
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>Metric</th>
                            <th>Current</th>
                            <th>Baseline</th>
                            <th>24h Avg</th>
                            <th>Status</th>
                        </tr>
                    </thead>
                    <tbody id="analytics-table">
                        <!-- Data will be inserted here -->
                    </tbody>
                </table>
            </div>
        </div>

        <!-- System Health Tab -->
        <div id="system" class="tab-content">
            <div class="grid">
                <div class="card">
                    <h3>System Status</h3>
                    <div id="system-status">
                        <!-- System status will be inserted here -->
                    </div>
                </div>
                <div class="card">
                    <h3>Resource Utilization</h3>
                    <div class="chart-container">
                        <canvas id="resourceChart"></canvas>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        let dashboardData = {};
        let charts = {};

        // Tab functionality
        function showTab(tabName) {
            document.querySelectorAll('.tab').forEach(tab => tab.classList.remove('active'));
            document.querySelectorAll('.tab-content').forEach(content => content.classList.remove('active'));
            
            event.target.classList.add('active');
            document.getElementById(tabName).classList.add('active');
        }

        // Load and refresh data
        async function loadData() {
            try {
                const response = await fetch('dashboard_data.json');
                dashboardData = await response.json();
                updateDashboard();
                document.getElementById('last-updated').textContent = `Last updated: ${new Date().toLocaleString()}`;
            } catch (error) {
                console.error('Error loading data:', error);
            }
        }

        function refreshData() {
            loadData();
        }

        // Update dashboard with new data
        function updateDashboard() {
            updateKPICards();
            updateCharts();
            updateAlerts();
            updateAnalyticsTable();
            updateSystemStatus();
        }

        // Update KPI cards
        function updateKPICards() {
            const kpiContainer = document.getElementById('kpi-cards');
            const stats = dashboardData.summary_statistics || {};
            
            const kpis = [
                {
                    label: 'Tokens per Second',
                    value: stats.tokens_per_second?.latest || 0,
                    baseline: 75.0,
                    format: (v) => v.toFixed(1) + ' tok/s'
                },
                {
                    label: 'Response Time',
                    value: stats.response_time?.latest || 0,
                    baseline: 0.87,
                    format: (v) => v.toFixed(2) + 's'
                },
                {
                    label: 'Error Rate',
                    value: stats.error_rate?.latest || 0,
                    baseline: 0,
                    format: (v) => v.toFixed(1) + '%'
                },
                {
                    label: 'Data Points',
                    value: stats.tokens_per_second?.count || 0,
                    baseline: null,
                    format: (v) => Math.floor(v).toString()
                }
            ];

            kpiContainer.innerHTML = kpis.map(kpi => {
                let changeClass = 'neutral';
                let changeText = 'No baseline';
                
                if (kpi.baseline !== null) {
                    const change = ((kpi.value - kpi.baseline) / kpi.baseline * 100);
                    changeClass = change > 0 ? 'positive' : change < 0 ? 'negative' : 'neutral';
                    changeText = (change > 0 ? '+' : '') + change.toFixed(1) + '% vs baseline';
                }

                return `
                    <div class="card metric-card">
                        <div class="metric-label">${kpi.label}</div>
                        <div class="metric-value">${kpi.format(kpi.value)}</div>
                        <div class="metric-change ${changeClass}">${changeText}</div>
                    </div>
                `;
            }).join('');
        }

        // Update charts
        function updateCharts() {
            const tpsData = dashboardData.aggregated_metrics?.tokens_per_second || [];
            const responseData = dashboardData.aggregated_metrics?.response_time || [];

            // Overview chart
            updateOverviewChart(tpsData, responseData);
            
            // Individual metric charts
            updateTpsChart(tpsData);
            updateResponseChart(responseData);
        }

        function updateOverviewChart(tpsData, responseData) {
            const ctx = document.getElementById('overviewChart').getContext('2d');
            
            if (charts.overview) {
                charts.overview.destroy();
            }

            charts.overview = new Chart(ctx, {
                type: 'line',
                data: {
                    datasets: [
                        {
                            label: 'Tokens/sec',
                            data: tpsData.map(d => ({x: d.timestamp, y: d.value})),
                            borderColor: '#3498db',
                            backgroundColor: 'rgba(52, 152, 219, 0.1)',
                            yAxisID: 'y'
                        },
                        {
                            label: 'Response Time (s)',
                            data: responseData.map(d => ({x: d.timestamp, y: d.value})),
                            borderColor: '#e74c3c',
                            backgroundColor: 'rgba(231, 76, 60, 0.1)',
                            yAxisID: 'y1'
                        }
                    ]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        x: {
                            type: 'time',
                            time: {
                                unit: 'hour'
                            }
                        },
                        y: {
                            type: 'linear',
                            display: true,
                            position: 'left',
                            title: {
                                display: true,
                                text: 'Tokens per Second'
                            }
                        },
                        y1: {
                            type: 'linear',
                            display: true,
                            position: 'right',
                            title: {
                                display: true,
                                text: 'Response Time (seconds)'
                            },
                            grid: {
                                drawOnChartArea: false,
                            },
                        }
                    },
                    plugins: {
                        title: {
                            display: true,
                            text: 'Performance Overview - Last 24 Hours'
                        }
                    }
                }
            });
        }

        function updateTpsChart(data) {
            const ctx = document.getElementById('tpsChart').getContext('2d');
            
            if (charts.tps) {
                charts.tps.destroy();
            }

            charts.tps = new Chart(ctx, {
                type: 'line',
                data: {
                    datasets: [{
                        label: 'Tokens per Second',
                        data: data.map(d => ({x: d.timestamp, y: d.value})),
                        borderColor: '#3498db',
                        backgroundColor: 'rgba(52, 152, 219, 0.1)',
                        fill: true
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        x: {
                            type: 'time',
                            time: {
                                unit: 'hour'
                            }
                        }
                    },
                    plugins: {
                        title: {
                            display: true,
                            text: 'Token Generation Performance'
                        }
                    }
                }
            });
        }

        function updateResponseChart(data) {
            const ctx = document.getElementById('responseChart').getContext('2d');
            
            if (charts.response) {
                charts.response.destroy();
            }

            charts.response = new Chart(ctx, {
                type: 'line',
                data: {
                    datasets: [{
                        label: 'Response Time (seconds)',
                        data: data.map(d => ({x: d.timestamp, y: d.value})),
                        borderColor: '#e74c3c',
                        backgroundColor: 'rgba(231, 76, 60, 0.1)',
                        fill: true
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        x: {
                            type: 'time',
                            time: {
                                unit: 'hour'
                            }
                        }
                    },
                    plugins: {
                        title: {
                            display: true,
                            text: 'Response Time Trends'
                        }
                    }
                }
            });
        }

        // Update alerts
        function updateAlerts() {
            const alertsSection = document.getElementById('alerts-section');
            const alertsContent = document.getElementById('alerts-content');
            const alerts = dashboardData.recent_alerts || [];

            if (alerts.length > 0) {
                alertsSection.style.display = 'block';
                alertsContent.innerHTML = alerts.map(alert => 
                    `<div>⚠️ ${alert.message} (${alert.timestamp})</div>`
                ).join('');
            } else {
                alertsSection.style.display = 'none';
            }
        }

        // Update analytics table
        function updateAnalyticsTable() {
            const tbody = document.getElementById('analytics-table');
            const stats = dashboardData.summary_statistics || {};
            
            const metrics = [
                {
                    name: 'Tokens per Second',
                    current: stats.tokens_per_second?.latest || 0,
                    baseline: 75.0,
                    avg: stats.tokens_per_second?.mean || 0
                },
                {
                    name: 'Response Time',
                    current: stats.response_time?.latest || 0,
                    baseline: 0.87,
                    avg: stats.response_time?.mean || 0
                },
                {
                    name: 'Error Rate',
                    current: stats.error_rate?.latest || 0,
                    baseline: 0,
                    avg: stats.error_rate?.mean || 0
                }
            ];

            tbody.innerHTML = metrics.map(metric => {
                const performance = getPerformanceStatus(metric.current, metric.baseline, metric.name);
                return `
                    <tr>
                        <td>${metric.name}</td>
                        <td>${metric.current.toFixed(2)}</td>
                        <td>${metric.baseline}</td>
                        <td>${metric.avg.toFixed(2)}</td>
                        <td><span class="performance-badge ${performance.class}">${performance.text}</span></td>
                    </tr>
                `;
            }).join('');
        }

        function getPerformanceStatus(current, baseline, metricName) {
            if (baseline === 0) return {class: 'badge-good', text: 'N/A'};
            
            const ratio = current / baseline;
            
            if (metricName === 'Response Time' || metricName === 'Error Rate') {
                // Lower is better
                if (ratio <= 0.9) return {class: 'badge-excellent', text: 'Excellent'};
                if (ratio <= 1.1) return {class: 'badge-good', text: 'Good'};
                if (ratio <= 1.3) return {class: 'badge-warning', text: 'Warning'};
                return {class: 'badge-poor', text: 'Poor'};
            } else {
                // Higher is better
                if (ratio >= 1.1) return {class: 'badge-excellent', text: 'Excellent'};
                if (ratio >= 0.9) return {class: 'badge-good', text: 'Good'};
                if (ratio >= 0.8) return {class: 'badge-warning', text: 'Warning'};
                return {class: 'badge-poor', text: 'Poor'};
            }
        }

        // Update system status
        function updateSystemStatus() {
            const systemStatus = document.getElementById('system-status');
            const dataSourceCount = dashboardData.data_sources?.length || 0;
            const lastUpdate = dashboardData.collection_timestamp || 'Unknown';
            
            systemStatus.innerHTML = `
                <p><span class="status-indicator status-good"></span> Data Sources: ${dataSourceCount}</p>
                <p><span class="status-indicator status-good"></span> Last Collection: ${new Date(lastUpdate).toLocaleString()}</p>
                <p><span class="status-indicator status-good"></span> Dashboard Status: Active</p>
            `;
        }

        // Initialize dashboard
        document.addEventListener('DOMContentLoaded', function() {
            loadData();
            
            // Auto-refresh every 30 seconds
            setInterval(loadData, 30000);
        });
    </script>
</body>
</html>
EOF
    
    success "Main dashboard created: $dashboard_file"
}

# Generate data file for dashboard
generate_dashboard_data() {
    local data_file="$1"
    local output_file="${OUTPUT_DIR}/dashboard_data.json"
    
    # Copy the aggregated data for the dashboard
    cp "$data_file" "$output_file"
    
    success "Dashboard data file created: $output_file"
}

# Generate API endpoint for real-time data
generate_api_endpoint() {
    local api_file="${OUTPUT_DIR}/api.php"
    
    log "Generating API endpoint: $api_file"
    
    cat > "$api_file" << 'EOF'
<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET');
header('Access-Control-Allow-Headers: Content-Type');

// Simple API to serve dashboard data
$data_file = 'dashboard_data.json';

if (file_exists($data_file)) {
    $data = file_get_contents($data_file);
    
    // Add cache headers
    $last_modified = filemtime($data_file);
    header('Last-Modified: ' . gmdate('D, d M Y H:i:s', $last_modified) . ' GMT');
    header('Cache-Control: public, max-age=30'); // Cache for 30 seconds
    
    echo $data;
} else {
    http_response_code(404);
    echo json_encode(['error' => 'Data file not found']);
}
?>
EOF
    
    success "API endpoint created: $api_file"
}

# Generate update script
generate_update_script() {
    local update_script="${OUTPUT_DIR}/update_dashboard.sh"
    
    log "Generating dashboard update script: $update_script"
    
    cat > "$update_script" << EOF
#!/bin/bash

# Dashboard Update Script
# Automatically updates dashboard data

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
PERFORMANCE_SCRIPT_DIR="$SCRIPT_DIR"
DATA_DIR="$DATA_DIR"
OUTPUT_DIR="$OUTPUT_DIR"

cd "\$PERFORMANCE_SCRIPT_DIR"

# Run metrics collection and dashboard generation
bash metrics-dashboard.sh "\$DATA_DIR" "\$OUTPUT_DIR"

echo "Dashboard updated at \$(date)"
EOF
    
    chmod +x "$update_script"
    success "Update script created: $update_script"
}

# Generate README with usage instructions
generate_readme() {
    local readme_file="${OUTPUT_DIR}/README.md"
    
    cat > "$readme_file" << 'EOF'
# vLLM Performance Dashboard

This dashboard provides comprehensive real-time monitoring and analytics for vLLM performance metrics.

## Features

- **Real-time Performance Monitoring**: Live updates of key performance indicators
- **Historical Trend Analysis**: Visualize performance trends over time
- **Automated Alerting**: Get notified of performance regressions
- **Multi-metric Support**: Track tokens/second, response time, error rates, and more
- **Responsive Design**: Works on desktop and mobile devices

## Files

- `index.html` - Main dashboard interface
- `dashboard_data.json` - Current performance data
- `api.php` - API endpoint for real-time data (requires PHP)
- `update_dashboard.sh` - Script to refresh dashboard data
- `README.md` - This documentation

## Usage

### Local File Access
Open `index.html` directly in your web browser. The dashboard will load data from `dashboard_data.json`.

### Web Server Setup
1. Copy all files to your web server directory
2. Ensure PHP is enabled (for API endpoint)
3. Set up a cron job to run `update_dashboard.sh` regularly:
   ```bash
   # Update dashboard every 5 minutes
   */5 * * * * /path/to/dashboard/update_dashboard.sh
   ```

### Manual Updates
Run the update script manually to refresh data:
```bash
./update_dashboard.sh
```

## Metrics Explained

- **Tokens per Second**: Rate of token generation (higher is better)
- **Response Time**: Time to complete requests (lower is better)  
- **Error Rate**: Percentage of failed requests (lower is better)
- **System Health**: Overall system status and resource utilization

## Performance Status Indicators

- 🟢 **Excellent**: Performance significantly above baseline
- 🔵 **Good**: Performance within acceptable range
- 🟡 **Warning**: Performance below baseline but acceptable
- 🔴 **Poor**: Performance significantly degraded

## Troubleshooting

### Dashboard Not Updating
1. Check that `update_dashboard.sh` is running successfully
2. Verify data files are being generated
3. Check browser console for JavaScript errors

### No Data Showing
1. Ensure performance monitoring tools are running
2. Check that data directory contains recent benchmark results
3. Verify file permissions allow reading data files

### API Errors
1. Ensure PHP is installed and enabled
2. Check web server error logs
3. Verify file permissions for data files

## Customization

Edit the dashboard configuration in `metrics-dashboard.sh` to:
- Change refresh intervals
- Modify baseline values
- Add custom metrics
- Adjust alert thresholds

## Support

For issues or questions, check the performance monitoring logs or review the source scripts in the performance tools directory.
EOF
    
    success "README created: $readme_file"
}

# Main execution
main() {
    log "Starting metrics dashboard generation..."
    log "Data directory: $DATA_DIR"
    log "Output directory: $OUTPUT_DIR"
    
    # Check if data directory exists
    if [ ! -d "$DATA_DIR" ]; then
        warning "Data directory not found: $DATA_DIR"
        warning "Creating sample data structure..."
        mkdir -p "$DATA_DIR"
        echo '{"results": []}' > "${DATA_DIR}/performance_trends.json"
    fi
    
    # Collect and aggregate all performance data
    local aggregated_data_file="${OUTPUT_DIR}/aggregated_data.json"
    collect_performance_data "$aggregated_data_file"
    
    # Generate dashboard components
    generate_dashboard_html "$aggregated_data_file"
    generate_dashboard_data "$aggregated_data_file"
    generate_api_endpoint
    generate_update_script
    generate_readme
    
    success "Dashboard generation completed!"
    echo ""
    echo -e "${BLUE}=== DASHBOARD READY ===${NC}"
    echo -e "${CYAN}Main Dashboard:${NC} ${OUTPUT_DIR}/index.html"
    echo -e "${CYAN}Data File:${NC} ${OUTPUT_DIR}/dashboard_data.json"
    echo -e "${CYAN}Update Script:${NC} ${OUTPUT_DIR}/update_dashboard.sh"
    echo ""
    echo -e "${YELLOW}To view the dashboard:${NC}"
    echo "1. Open ${OUTPUT_DIR}/index.html in your web browser"
    echo "2. Or serve from a web server for real-time updates"
    echo ""
    echo -e "${YELLOW}To keep data current:${NC}"
    echo "Run: ${OUTPUT_DIR}/update_dashboard.sh"
    echo "Or set up a cron job for automatic updates"
}

# Run main function
main "$@"