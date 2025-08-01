# vLLM Production Performance Suite

A comprehensive production-ready performance monitoring and testing suite for vLLM workloads, based on production metrics (~75 tokens/sec, 200k context).

## 🚀 Features

- **Comprehensive Benchmarking**: Enhanced benchmark suite with regression detection
- **Real-time GPU Monitoring**: Live GPU utilization, temperature, and memory tracking
- **Load Testing**: Realistic load testing scenarios based on production patterns
- **Continuous Monitoring**: Automated benchmarking with alerting and trends
- **Regression Detection**: Statistical analysis for performance degradation detection
- **Interactive Dashboard**: Real-time performance metrics visualization

## 📁 Tools Overview

### 1. Enhanced Benchmark Suite (`benchmark-suite.sh`)
**Production-ready benchmarking with comprehensive monitoring**

```bash
# Basic usage
./benchmark-suite.sh [API_KEY] [BASE_URL]

# With monitoring and alerts enabled
ENABLE_MONITORING=true ENABLE_ALERTS=true WEBHOOK_URL="https://your-webhook" ./benchmark-suite.sh

# Environment variables
export PERFORMANCE_BASELINE_TPS=75.0     # Performance baseline
export REGRESSION_THRESHOLD=0.15         # 15% regression threshold
export WEBHOOK_URL="https://hooks.slack.com/..."
export SLACK_WEBHOOK="https://hooks.slack.com/..."
```

**New Features:**
- Comprehensive GPU and system metrics collection
- Automated performance regression detection
- Real-time alerting via webhooks/Slack
- Historical performance tracking
- Statistical analysis and trend detection

### 2. GPU Monitor (`gpu-monitor.sh`)
**Real-time GPU performance monitoring**

```bash
# Monitor for 5 minutes with 2-second intervals
./gpu-monitor.sh 2 300 gpu_monitor.log

# Background monitoring with alerts
ENABLE_ALERTS=true WEBHOOK_URL="https://your-webhook" ./gpu-monitor.sh 5 3600 &
```

**Features:**
- Real-time GPU utilization, temperature, power monitoring
- Memory usage tracking with visual indicators
- Alert thresholds for temperature (85°C) and memory (90%)
- JSON output for integration with other tools
- Summary statistics and trend analysis

### 3. Load Tester (`load-tester.sh`)
**Production-grade load testing with realistic scenarios**

```bash
# Test profiles available
./load-tester.sh [API_KEY] [BASE_URL] realistic   # 5 users, 2 req/s, 5 min
./load-tester.sh [API_KEY] [BASE_URL] stress      # 20 users, 10 req/s, 10 min
./load-tester.sh [API_KEY] [BASE_URL] burst       # 50 users, 25 req/s, 3 min
./load-tester.sh [API_KEY] [BASE_URL] sustained   # 10 users, 5 req/s, 30 min
```

**Features:**
- Multiple test profiles based on real usage patterns
- Token distribution matching production workloads
- Concurrent request handling with proper rate limiting
- GPU monitoring integration during load tests
- Comprehensive metrics and performance analysis
- Baseline comparison against 75 tokens/sec production metric

### 4. Continuous Benchmark (`continuous-benchmark.sh`)
**Automated performance monitoring service**

```bash
# Start continuous monitoring service
./continuous-benchmark.sh start

# Check service status
./continuous-benchmark.sh status

# Stop service
./continuous-benchmark.sh stop

# Generate performance report
./continuous-benchmark.sh report

# Run quick test
./continuous-benchmark.sh test
```

**Configuration:**
Create `continuous_benchmark_config.json`:
```json
{
    "api_key": "qwen3-secret-key",
    "base_url": "http://localhost:8000/v1",
    "benchmark_interval_minutes": 60,
    "retention_days": 30,
    "baseline_tps": 75.0,
    "regression_threshold": 0.15,
    "alerts": {
        "enabled": true,
        "webhook_url": "https://your-webhook",
        "slack_webhook": "https://hooks.slack.com/...",
        "email_smtp": {
            "enabled": false,
            "server": "smtp.gmail.com",
            "port": 587,
            "username": "your-email",
            "password": "your-password",
            "to_addresses": ["admin@example.com"]
        }
    },
    "benchmarks": {
        "quick_test": {"enabled": true, "frequency": "every_run"},
        "comprehensive_test": {"enabled": true, "frequency": "hourly"},
        "load_test": {"enabled": true, "frequency": "daily", "profile": "realistic"},
        "stress_test": {"enabled": false, "frequency": "weekly", "profile": "stress"}
    }
}
```

### 5. Regression Detector (`regression-detector.sh`)
**Statistical performance regression analysis**

```bash
# Analyze performance data for regressions
./regression-detector.sh performance_trends.json regression_config.json

# Generate HTML report from analysis
./regression-detector.sh report analysis_results.json

# Create default configuration
./regression-detector.sh config my_regression_config.json
```

**Features:**
- Statistical analysis using modified Z-score for anomaly detection
- Trend detection using linear regression approximation
- Configurable regression thresholds and baselines
- Multi-metric analysis with weighted scoring
- HTML reports with visualizations
- Integration with alerting systems

### 6. Metrics Dashboard (`metrics-dashboard.sh`)
**Interactive performance dashboard generator**

```bash
# Generate dashboard from continuous benchmark data
./metrics-dashboard.sh continuous_benchmark_data dashboard

# Update existing dashboard
cd dashboard && ./update_dashboard.sh
```

**Features:**
- Real-time performance metrics visualization
- Interactive charts and trend analysis
- Performance status indicators and alerts
- Responsive design for desktop and mobile
- Auto-refresh capabilities
- REST API for real-time data

## 🛠 Installation & Setup

### Prerequisites
```bash
# Required tools
sudo apt-get update
sudo apt-get install -y curl jq bc nvidia-utils

# Optional for advanced features
sudo apt-get install -y ssmtp php  # For email alerts and web dashboard
```

### Quick Setup
```bash
# Make all scripts executable
chmod +x *.sh

# Create data directories
mkdir -p continuous_benchmark_data benchmark_history dashboard

# Initialize continuous monitoring
./continuous-benchmark.sh start
```

### Production Deployment
```bash
# 1. Set up continuous monitoring as systemd service
sudo cp continuous-benchmark.sh /usr/local/bin/
sudo cp continuous_benchmark_config.json /etc/

# Create systemd service
sudo tee /etc/systemd/system/vllm-monitoring.service << EOF
[Unit]
Description=vLLM Continuous Performance Monitoring
After=network.target

[Service]
Type=simple
User=vllm
WorkingDirectory=/opt/vllm-performance
ExecStart=/usr/local/bin/continuous-benchmark.sh start /etc/continuous_benchmark_config.json
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl enable vllm-monitoring
sudo systemctl start vllm-monitoring

# 2. Set up dashboard web server
sudo cp -r dashboard/* /var/www/html/vllm-dashboard/
sudo chown -R www-data:www-data /var/www/html/vllm-dashboard/

# 3. Set up automated dashboard updates
sudo crontab -e
# Add: */5 * * * * /var/www/html/vllm-dashboard/update_dashboard.sh
```

## 📊 Performance Baselines

Based on production analysis from chat history:

| Metric | Baseline | Target | Alert Threshold |
|--------|----------|--------|-----------------|
| Tokens/Second | 75.0 | 80.0 | < 63.75 (15% below) |
| Response Time | 0.87s | 0.8s | > 1.0s |
| GPU Memory | 70% | 75% | > 90% |
| GPU Temperature | 75°C | 70°C | > 85°C |
| Error Rate | 0% | 0% | > 1% |

## 🔧 Configuration

### Environment Variables
```bash
# Performance thresholds
export PERFORMANCE_BASELINE_TPS=75.0
export REGRESSION_THRESHOLD=0.15
export ALERT_THRESHOLD_TEMP=85
export ALERT_THRESHOLD_MEMORY=90

# Alerting
export ENABLE_ALERTS=true
export WEBHOOK_URL="https://your-webhook-url"
export SLACK_WEBHOOK="https://hooks.slack.com/services/..."

# Monitoring
export ENABLE_MONITORING=true
```

### Alert Configuration
Supports multiple alert channels:

- **Webhooks**: Generic HTTP POST with JSON payload
- **Slack**: Direct Slack webhook integration
- **Email**: SMTP email notifications (requires ssmtp)

### Custom Metrics
Add custom metrics by modifying the respective configuration files:
- `benchmark-suite.sh`: Add new test scenarios
- `regression-detector.sh`: Configure metric weights and thresholds
- `continuous-benchmark.sh`: Add new benchmark frequencies
- `metrics-dashboard.sh`: Add new visualization metrics

## 📈 Usage Examples

### Daily Performance Monitoring
```bash
# Start continuous monitoring
./continuous-benchmark.sh start

# Generate daily performance report
./continuous-benchmark.sh report

# Check for regressions
./regression-detector.sh analyze continuous_benchmark_data/performance_trends.json
```

### Load Testing Before Deployment
```bash
# Quick performance check
./benchmark-suite.sh

# Realistic load test
./load-tester.sh qwen3-secret-key http://localhost:8000/v1 realistic

# Stress test for capacity planning
./load-tester.sh qwen3-secret-key http://localhost:8000/v1 stress
```

### GPU Monitoring During High Load
```bash
# Start GPU monitoring in background
./gpu-monitor.sh 2 3600 gpu_load_$(date +%Y%m%d_%H%M%S).log &

# Run load test
./load-tester.sh qwen3-secret-key http://localhost:8000/v1 burst

# Analyze GPU performance
tail gpu_load_*.log
```

## 🚨 Alerting & Notifications

### Alert Types
- **Performance Regression**: When metrics fall below baseline thresholds
- **System Health**: GPU temperature, memory usage alerts
- **Error Rate**: Increased failure rates in requests
- **Trend Analysis**: Declining performance trends over time

### Alert Channels
- Webhook notifications with detailed JSON payloads
- Slack integration with formatted messages
- Email alerts for critical issues
- Dashboard visual indicators

## 📋 Troubleshooting

### Common Issues

**"jq: command not found"**
```bash
sudo apt-get install jq
```

**"bc: command not found"**
```bash
sudo apt-get install bc
```

**GPU monitoring not working**
```bash
# Check NVIDIA drivers
nvidia-smi
# Install if missing
sudo apt-get install nvidia-utils
```

**Dashboard not updating**
```bash
# Check update script permissions
chmod +x dashboard/update_dashboard.sh
# Verify cron job
crontab -l
```

### Performance Issues
- Reduce monitoring frequency for high-load environments
- Adjust regression thresholds based on your performance requirements
- Use appropriate load test profiles to avoid overwhelming the system

### Log Analysis
All tools generate detailed logs:
- Benchmark results: `benchmark_results_*/benchmark.log`
- GPU monitoring: `gpu_monitor_*.log`
- Load testing: `load_test_*/load_test.log`
- Continuous monitoring: `continuous_benchmark_data/continuous_benchmark.log`

## 🔍 Integration

### CI/CD Integration
```yaml
# Example GitHub Actions workflow
- name: Performance Test
  run: |
    ./scripts/performance/benchmark-suite.sh $API_KEY $BASE_URL
    ./scripts/performance/regression-detector.sh analyze
```

### Monitoring Stack Integration
- **Prometheus**: Export metrics using custom webhook endpoints
- **Grafana**: Import dashboard data via API
- **ELK Stack**: Forward logs and metrics for centralized analysis
- **DataDog**: Use webhook integration for metric forwarding

## 📚 API Reference

### Webhook Payload Format
```json
{
    "title": "Performance Alert Title",
    "message": "Detailed alert message",
    "severity": "warning|critical|info",
    "timestamp": "2024-01-01T12:00:00Z",
    "source": "benchmark-suite|gpu-monitor|load-tester",
    "metrics": {
        "tokens_per_second": 65.5,
        "baseline": 75.0,
        "regression_percentage": 12.7
    }
}
```

### Dashboard API Endpoints
- `GET /dashboard_data.json` - Current performance data
- `GET /api.php` - Real-time data with caching headers

## 🤝 Contributing

To extend the performance suite:

1. Follow the existing script structure and logging patterns
2. Add configuration options via environment variables or config files
3. Include comprehensive error handling and validation
4. Update this README with new features and usage examples
5. Test with various load scenarios and edge cases

## 📜 License

This performance suite is designed for production vLLM deployments. Modify and distribute according to your organization's requirements.

---

## 🎯 Quick Start Checklist

- [ ] Install prerequisites (`jq`, `bc`, `nvidia-utils`)
- [ ] Make scripts executable (`chmod +x *.sh`)
- [ ] Configure baseline performance metrics
- [ ] Set up alerting endpoints (webhook/Slack)
- [ ] Run initial benchmark to establish baseline
- [ ] Start continuous monitoring service
- [ ] Generate performance dashboard
- [ ] Set up automated updates (cron)
- [ ] Test alert notifications
- [ ] Document custom configurations

For production deployments, consider running the continuous monitoring as a systemd service and hosting the dashboard on a web server for team access.