#!/bin/bash

# Performance Regression Detection Tool
# Analyzes performance data and detects regressions using statistical methods
# Usage: ./regression-detector.sh [DATA_FILE] [CONFIG_FILE]

set -euo pipefail

# Configuration
DATA_FILE="${1:-performance_trends.json}"
CONFIG_FILE="${2:-regression_config.json}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/regression_analysis"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Default configuration
DEFAULT_CONFIG=$(cat << 'EOF'
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
        "enabled": true,
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

# Load configuration
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log "Configuration file not found. Creating default: $CONFIG_FILE"
        echo "$DEFAULT_CONFIG" > "$CONFIG_FILE"
    fi
    
    if ! jq . "$CONFIG_FILE" > /dev/null 2>&1; then
        error "Invalid JSON in configuration file: $CONFIG_FILE"
        exit 1
    fi
    
    log "Configuration loaded from: $CONFIG_FILE"
}

# Send alert
send_alert() {
    local title="$1"
    local message="$2"
    local severity="${3:-warning}"
    
    local alerts_enabled=$(jq -r '.alerts.enabled' "$CONFIG_FILE")
    local enabled_severities=$(jq -r '.alerts.severity_levels[]' "$CONFIG_FILE")
    
    # Check if this severity level is enabled
    if [ "$alerts_enabled" = "true" ] && echo "$enabled_severities" | grep -q "$severity"; then
        local webhook_url=$(jq -r '.alerts.webhook_url' "$CONFIG_FILE")
        local slack_webhook=$(jq -r '.alerts.slack_webhook' "$CONFIG_FILE")
        
        # Generic webhook
        if [ -n "$webhook_url" ] && [ "$webhook_url" != "null" ]; then
            curl -s -X POST "$webhook_url" \
                -H "Content-Type: application/json" \
                -d "{\"title\":\"$title\",\"message\":\"$message\",\"severity\":\"$severity\",\"timestamp\":\"$(date -Iseconds)\",\"source\":\"regression-detector\"}" &
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
    fi
}

# Calculate statistical measures
calculate_statistics() {
    local data_array="$1"
    local output_file="$2"
    
    # Use jq to calculate statistics
    echo "$data_array" | jq -r '
        def mean: add / length;
        def variance: . as $data | mean as $mean | map(. - $mean | . * .) | mean;
        def stddev: variance | sqrt;
        def median: sort | if length % 2 == 0 then (.[length/2-1] + .[length/2]) / 2 else .[length/2 | floor] end;
        def percentile(p): sort | .[((length - 1) * p / 100) | floor];
        
        {
            count: length,
            mean: mean,
            median: median,
            stddev: stddev,
            min: min,
            max: max,
            p25: percentile(25),
            p75: percentile(75),
            p95: percentile(95),
            p99: percentile(99)
        }
    ' > "$output_file"
}

# Detect trend using linear regression approximation
detect_trend() {
    local data_array="$1"
    
    # Simple trend detection using first and last values
    echo "$data_array" | jq -r '
        if length < 3 then
            {trend: "insufficient_data", slope: 0, correlation: 0}
        else
            . as $data |
            (keys | map(tonumber)) as $x |
            ($x | add / length) as $x_mean |
            ($data | add / length) as $y_mean |
            
            # Calculate correlation coefficient (simplified)
            ([$x[], $data[]] | transpose | 
             map(.[0] - $x_mean) | add) as $sum_x_diff |
            ([$x[], $data[]] | transpose | 
             map(.[1] - $y_mean) | add) as $sum_y_diff |
            
            # Simple slope calculation
            if length > 1 then
                (($data[-1] - $data[0]) / (length - 1)) as $slope |
                {
                    trend: (if $slope > 0 then "increasing" elif $slope < 0 then "decreasing" else "stable" end),
                    slope: $slope,
                    change_pct: (($data[-1] - $data[0]) / $data[0] * 100)
                }
            else
                {trend: "stable", slope: 0, change_pct: 0}
            end
        end
    '
}

# Detect anomalies using modified Z-score
detect_anomalies() {
    local data_array="$1"
    local threshold="${2:-3.5}"
    
    echo "$data_array" | jq -r --arg threshold "$threshold" '
        def median: sort | if length % 2 == 0 then (.[length/2-1] + .[length/2]) / 2 else .[length/2 | floor] end;
        def mad: . as $data | median as $med | map(. - $med | abs) | median;
        
        median as $median |
        mad as $mad |
        map({
            value: .,
            z_score: (if $mad > 0 then 0.6745 * (. - $median) / $mad else 0 end),
            is_anomaly: (if $mad > 0 then (0.6745 * (. - $median) / $mad | abs) > ($threshold | tonumber) else false end)
        })
    '
}

# Analyze performance data
analyze_performance_data() {
    if [ ! -f "$DATA_FILE" ]; then
        error "Data file not found: $DATA_FILE"
        exit 1
    fi
    
    log "Analyzing performance data from: $DATA_FILE"
    
    # Extract recent data
    local window_size=$(jq -r '.statistical_analysis.window_size' "$CONFIG_FILE")
    local recent_data=$(jq -r ".results | map(select(.tokens_per_second != null and (.tokens_per_second | type) == \"number\")) | sort_by(.timestamp) | tail($window_size)" "$DATA_FILE")
    
    if [ "$(echo "$recent_data" | jq 'length')" -lt 3 ]; then
        warning "Insufficient data for analysis (need at least 3 data points)"
        return 1
    fi
    
    # Analysis results file
    local analysis_file="${OUTPUT_DIR}/analysis_${TIMESTAMP}.json"
    
    # Initialize analysis results
    cat > "$analysis_file" << EOF
{
    "analysis_timestamp": "$(date -Iseconds)",
    "data_source": "$DATA_FILE",
    "config_source": "$CONFIG_FILE",
    "window_size": $window_size,
    "data_points_analyzed": $(echo "$recent_data" | jq 'length'),
    "metrics_analysis": {}
}
EOF
    
    # Analyze each enabled metric
    local metrics=$(jq -r '.metrics | keys[]' "$CONFIG_FILE")
    
    for metric in $metrics; do
        local enabled=$(jq -r ".metrics.${metric}.enabled" "$CONFIG_FILE")
        
        if [ "$enabled" = "true" ]; then
            log "Analyzing metric: $metric"
            analyze_metric "$metric" "$recent_data" "$analysis_file"
        fi
    done
    
    # Generate overall assessment
    generate_regression_assessment "$analysis_file"
    
    success "Analysis completed: $analysis_file"
    echo "$analysis_file"
}

# Analyze individual metric
analyze_metric() {
    local metric="$1"
    local data="$2"
    local analysis_file="$3"
    
    # Extract values for this metric
    local values=$(echo "$data" | jq -r "map(.${metric}) | map(select(. != null and (. | type) == \"number\"))")
    
    if [ "$(echo "$values" | jq 'length')" -lt 3 ]; then
        warning "Insufficient data for metric: $metric"
        return
    fi
    
    # Calculate statistics
    local stats_file=$(mktemp)
    calculate_statistics "$values" "$stats_file"
    
    # Detect trend
    local trend_info=$(detect_trend "$values")
    
    # Detect anomalies
    local anomalies=$(detect_anomalies "$values")
    
    # Get baseline and thresholds
    local baseline_value
    case "$metric" in
        "tokens_per_second")
            baseline_value=$(jq -r '.baseline_tps' "$CONFIG_FILE")
            ;;
        "response_time"|"duration_seconds")
            baseline_value=$(jq -r '.baseline_response_time' "$CONFIG_FILE")
            ;;
        *)
            baseline_value="null"
            ;;
    esac
    
    local weight=$(jq -r ".metrics.${metric}.weight" "$CONFIG_FILE")
    local lower_is_better=$(jq -r ".metrics.${metric}.lower_is_better" "$CONFIG_FILE")
    
    # Current performance assessment
    local current_value=$(echo "$values" | jq -r '.[-1]')
    local regression_status="normal"
    local regression_percentage=0
    
    if [ "$baseline_value" != "null" ] && (( $(echo "$baseline_value > 0" | bc -l) )); then
        if [ "$lower_is_better" = "true" ]; then
            regression_percentage=$(echo "scale=2; ($current_value - $baseline_value) / $baseline_value * 100" | bc -l)
        else
            regression_percentage=$(echo "scale=2; ($baseline_value - $current_value) / $baseline_value * 100" | bc -l)
        fi
        
        local warning_threshold=$(jq -r '.thresholds.warning_percentage' "$CONFIG_FILE")
        local critical_threshold=$(jq -r '.thresholds.critical_percentage' "$CONFIG_FILE")
        
        if (( $(echo "$regression_percentage > $critical_threshold" | bc -l) )); then
            regression_status="critical"
        elif (( $(echo "$regression_percentage > $warning_threshold" | bc -l) )); then
            regression_status="warning"
        fi
    fi
    
    # Create metric analysis
    local metric_analysis=$(cat << EOF
{
    "metric_name": "$metric",
    "baseline_value": $baseline_value,
    "current_value": $current_value,
    "weight": $weight,
    "lower_is_better": $lower_is_better,
    "regression_status": "$regression_status",
    "regression_percentage": $regression_percentage,
    "statistics": $(cat "$stats_file"),
    "trend_analysis": $trend_info,
    "anomaly_count": $(echo "$anomalies" | jq '[.[] | select(.is_anomaly)] | length'),
    "anomalies": $anomalies
}
EOF
)
    
    # Add to analysis file
    local temp_file=$(mktemp)
    jq ".metrics_analysis.${metric} = $metric_analysis" "$analysis_file" > "$temp_file" && mv "$temp_file" "$analysis_file"
    
    # Send alerts if needed
    if [ "$regression_status" != "normal" ]; then
        local alert_message="Metric: ${metric}\nCurrent: ${current_value}\nBaseline: ${baseline_value}\nRegression: ${regression_percentage}%"
        send_alert "Performance Regression Detected" "$alert_message" "$regression_status"
    fi
    
    rm -f "$stats_file"
}

# Generate overall regression assessment
generate_regression_assessment() {
    local analysis_file="$1"
    
    # Calculate weighted regression score
    local regression_score=$(jq -r '
        .metrics_analysis | 
        [to_entries[] | 
         select(.value.regression_percentage != null) | 
         {
           metric: .key,
           weighted_regression: (.value.regression_percentage * .value.weight),
           weight: .value.weight,
           status: .value.regression_status
         }
        ] as $metrics |
        
        {
            total_weighted_regression: ($metrics | map(.weighted_regression) | add // 0),
            total_weight: ($metrics | map(.weight) | add // 1),
            critical_count: ($metrics | map(select(.status == "critical")) | length),
            warning_count: ($metrics | map(select(.status == "warning")) | length),
            normal_count: ($metrics | map(select(.status == "normal")) | length)
        } |
        
        .overall_regression_score = (.total_weighted_regression / .total_weight) |
        .overall_status = (
            if .critical_count > 0 then "critical"
            elif .warning_count > 0 then "warning"
            else "normal"
            end
        )
    ' "$analysis_file")
    
    # Add assessment to analysis file
    local temp_file=$(mktemp)
    jq ".regression_assessment = $regression_score" "$analysis_file" > "$temp_file" && mv "$temp_file" "$analysis_file"
    
    # Display summary
    local overall_status=$(echo "$regression_score" | jq -r '.overall_status')
    local overall_score=$(echo "$regression_score" | jq -r '.overall_regression_score')
    
    echo ""
    echo -e "${BLUE}=== REGRESSION ANALYSIS SUMMARY ===${NC}"
    echo -e "${CYAN}Overall Status:${NC} $overall_status"
    echo -e "${CYAN}Regression Score:${NC} ${overall_score}%"
    
    case "$overall_status" in
        "critical")
            error "CRITICAL: Significant performance regression detected!"
            ;;
        "warning")
            warning "WARNING: Performance degradation detected"
            ;;
        "normal")
            success "NORMAL: No significant performance regression"
            ;;
    esac
    
    # Display metric details
    echo ""
    echo -e "${BLUE}Metric Details:${NC}"
    jq -r '.metrics_analysis | to_entries[] | "  \(.key): \(.value.regression_status) (\(.value.regression_percentage)%)"' "$analysis_file"
    echo ""
}

# Generate performance report
generate_report() {
    local analysis_file="$1"
    local report_file="${OUTPUT_DIR}/regression_report_${TIMESTAMP}.html"
    
    log "Generating regression analysis report: $report_file"
    
    # Create HTML report
    cat > "$report_file" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Performance Regression Analysis Report</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .status-normal { color: #28a745; }
        .status-warning { color: #ffc107; }
        .status-critical { color: #dc3545; }
        .metric-card { border: 1px solid #ddd; margin: 10px 0; padding: 15px; border-radius: 5px; }
        .metric-critical { border-left: 5px solid #dc3545; }
        .metric-warning { border-left: 5px solid #ffc107; }
        .metric-normal { border-left: 5px solid #28a745; }
        .chart-container { width: 100%; height: 300px; margin: 20px 0; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Performance Regression Analysis</h1>
        <p>Generated: TIMESTAMP_PLACEHOLDER</p>
        <p>Analysis Window: WINDOW_SIZE_PLACEHOLDER data points</p>
    </div>
    
    <div id="summary">
        <h2>Executive Summary</h2>
        <div id="overall-status"></div>
    </div>
    
    <div id="metrics-analysis">
        <h2>Metrics Analysis</h2>
        <div id="metrics-details"></div>
    </div>
    
    <div id="trends">
        <h2>Performance Trends</h2>
        <div class="chart-container">
            <canvas id="trendsChart"></canvas>
        </div>
    </div>
    
    <div id="statistics">
        <h2>Statistical Summary</h2>
        <table id="stats-table">
            <thead>
                <tr>
                    <th>Metric</th>
                    <th>Current</th>
                    <th>Baseline</th>
                    <th>Mean</th>
                    <th>Std Dev</th>
                    <th>95th %ile</th>
                    <th>Status</th>
                </tr>
            </thead>
            <tbody id="stats-body">
            </tbody>
        </table>
    </div>

    <script>
        const analysisData = ANALYSIS_DATA_PLACEHOLDER;
        
        // Populate summary
        const assessment = analysisData.regression_assessment;
        document.getElementById('overall-status').innerHTML = `
            <p class="status-${assessment.overall_status}">
                <strong>Overall Status: ${assessment.overall_status.toUpperCase()}</strong>
            </p>
            <p>Regression Score: ${assessment.overall_regression_score.toFixed(2)}%</p>
            <p>Critical Issues: ${assessment.critical_count}, Warnings: ${assessment.warning_count}</p>
        `;
        
        // Populate metrics details
        const metricsContainer = document.getElementById('metrics-details');
        Object.entries(analysisData.metrics_analysis).forEach(([metric, data]) => {
            const card = document.createElement('div');
            card.className = `metric-card metric-${data.regression_status}`;
            card.innerHTML = `
                <h3>${metric.replace('_', ' ').toUpperCase()}</h3>
                <p><strong>Status:</strong> <span class="status-${data.regression_status}">${data.regression_status}</span></p>
                <p><strong>Current Value:</strong> ${data.current_value.toFixed(2)}</p>
                <p><strong>Baseline:</strong> ${data.baseline_value}</p>
                <p><strong>Regression:</strong> ${data.regression_percentage.toFixed(2)}%</p>
                <p><strong>Trend:</strong> ${data.trend_analysis.trend} (${data.trend_analysis.change_pct.toFixed(1)}%)</p>
                <p><strong>Anomalies:</strong> ${data.anomaly_count}</p>
            `;
            metricsContainer.appendChild(card);
        });
        
        // Populate statistics table
        const statsBody = document.getElementById('stats-body');
        Object.entries(analysisData.metrics_analysis).forEach(([metric, data]) => {
            const row = statsBody.insertRow();
            row.innerHTML = `
                <td>${metric}</td>
                <td>${data.current_value.toFixed(2)}</td>
                <td>${data.baseline_value}</td>
                <td>${data.statistics.mean.toFixed(2)}</td>
                <td>${data.statistics.stddev.toFixed(2)}</td>
                <td>${data.statistics.p95.toFixed(2)}</td>
                <td class="status-${data.regression_status}">${data.regression_status}</td>
            `;
        });
    </script>
</body>
</html>
EOF
    
    # Replace placeholders
    local analysis_json=$(cat "$analysis_file")
    local window_size=$(jq -r '.window_size' "$analysis_file")
    
    sed -i.bak "s/TIMESTAMP_PLACEHOLDER/$(date)/g" "$report_file"
    sed -i.bak "s/WINDOW_SIZE_PLACEHOLDER/$window_size/g" "$report_file"
    sed -i.bak "s/ANALYSIS_DATA_PLACEHOLDER/$(echo "$analysis_json" | jq -c .)/g" "$report_file"
    rm -f "${report_file}.bak"
    
    success "Report generated: $report_file"
    echo "$report_file"
}

# Main execution
main() {
    case "${1:-analyze}" in
        "analyze")
            log "Starting performance regression analysis..."
            load_config
            local analysis_file=$(analyze_performance_data)
            if [ -n "$analysis_file" ]; then
                generate_report "$analysis_file"
            fi
            ;;
        "report")
            if [ -z "${2:-}" ]; then
                error "Analysis file required for report generation"
                echo "Usage: $0 report <analysis_file.json>"
                exit 1
            fi
            generate_report "$2"
            ;;
        "config")
            echo "$DEFAULT_CONFIG" > "${2:-regression_config.json}"
            success "Default configuration created: ${2:-regression_config.json}"
            ;;
        *)
            echo "Usage: $0 {analyze|report|config} [options]"
            echo ""
            echo "Commands:"
            echo "  analyze [data_file] [config_file]  - Analyze performance data for regressions"
            echo "  report <analysis_file>             - Generate HTML report from analysis"
            echo "  config [file]                      - Create default configuration file"
            echo ""
            echo "Examples:"
            echo "  $0 analyze performance_trends.json"
            echo "  $0 report analysis_20240101.json"
            echo "  $0 config my_config.json"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"