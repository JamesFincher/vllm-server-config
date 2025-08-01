# vLLM Infrastructure Debugging and Troubleshooting Toolkit

A comprehensive suite of debugging tools for vLLM server infrastructure, designed to quickly identify, diagnose, and automatically resolve common issues.

## 🚀 Quick Start

```bash
# Make all scripts executable
chmod +x *.sh

# Run quick health check
./debug-master.sh --quick

# Run comprehensive diagnostics with auto-fix
./debug-master.sh --full --fix

# Start real-time monitoring
./debug-master.sh --monitor
```

## 📁 Tool Overview

### 🎯 debug-master.sh - Master Control Script
**The main entry point for all debugging operations**

```bash
# Quick health check
./debug-master.sh --quick

# Full diagnostics
./debug-master.sh --full

# Auto-fix issues
./debug-master.sh --full --fix

# Real-time monitoring
./debug-master.sh --monitor

# Specific tool access
./debug-master.sh health --verbose
./debug-master.sh logs --errors-only
./debug-master.sh network --fix-issues
./debug-master.sh gpu --realtime
./debug-master.sh recover --auto-fix
```

### 🩺 health-check.sh - System Health Validation
**Comprehensive health checks for all system components**

```bash
# Basic health check
./health-check.sh

# Verbose output with auto-fix
./health-check.sh --verbose --fix-issues

# JSON output for automation
./health-check.sh --json
```

**Checks:**
- Python environment and vLLM installation
- Model files and configuration
- GPU hardware and drivers
- SSH tunnel connectivity
- API endpoints and authentication
- vLLM server processes and logs

### 📊 log-analyzer.sh - vLLM Log Analysis
**Intelligent parsing and analysis of vLLM server logs**

```bash
# Analyze recent logs
./log-analyzer.sh --recent

# Show only errors
./log-analyzer.sh --errors-only

# Performance metrics
./log-analyzer.sh --performance

# Live log monitoring
./log-analyzer.sh --follow

# Analyze specific log file
./log-analyzer.sh /path/to/logfile.log
```

**Features:**
- Error pattern detection and categorization
- Performance metrics and throughput analysis
- Timeline analysis and trend identification
- Real-time log monitoring with color coding
- Automatic issue recommendations

### 🌐 network-diagnostics.sh - Network Connectivity Testing
**Comprehensive network and SSH tunnel diagnostics**

```bash
# Full network diagnostics
./network-diagnostics.sh

# Test only SSH tunnel
./network-diagnostics.sh --tunnel-only

# Test only API endpoints
./network-diagnostics.sh --api-only

# Auto-fix network issues
./network-diagnostics.sh --fix-issues

# Continuous monitoring
./network-diagnostics.sh --continuous
```

**Tests:**
- SSH key validation and permissions
- SSH server connectivity and command execution
- SSH tunnel establishment and health
- API endpoint accessibility and authentication
- Network latency and performance
- Port conflicts and binding issues

### 🖥️ gpu-monitor.sh - GPU Resource Monitoring
**Real-time GPU monitoring and resource tracking**

```bash
# Current GPU status
./gpu-monitor.sh --summary

# Real-time monitoring
./gpu-monitor.sh --realtime

# Historical performance analysis
./gpu-monitor.sh --history

# Alert checking
./gpu-monitor.sh --alerts

# Custom thresholds
./gpu-monitor.sh --threshold-temp 80 --threshold-mem 90
```

**Monitoring:**
- GPU utilization and memory usage
- Temperature and power consumption
- Process tracking and memory allocation
- Performance trends and bottleneck detection
- Customizable alert thresholds
- Historical data analysis

### 🔧 recovery-tools.sh - Automated Recovery System
**Intelligent failure detection and automated recovery**

```bash
# Check for issues and suggest fixes
./recovery-tools.sh --check-all

# Automatic recovery
./recovery-tools.sh --check-all --auto-fix

# Specific recovery actions
./recovery-tools.sh tunnel-restart
./recovery-tools.sh vllm-restart
./recovery-tools.sh process-cleanup
./recovery-tools.sh memory-cleanup
./recovery-tools.sh full-recovery

# Dry run (show what would be done)
./recovery-tools.sh --dry-run --auto-fix
```

**Recovery Actions:**
- SSH tunnel restart and validation
- vLLM server restart via remote SSH
- Process cleanup (hung/zombie processes)
- GPU memory clearing and CUDA cache reset
- Full system recovery sequence
- Automated validation of fixes

## 🎛️ Common Usage Patterns

### Daily Health Check
```bash
# Quick morning health check
./debug-master.sh --quick

# If issues found, run comprehensive diagnostics
./debug-master.sh --full --fix
```

### Performance Monitoring
```bash
# Check current performance
./debug-master.sh gpu --summary
./debug-master.sh logs --performance

# Start real-time monitoring
./debug-master.sh --monitor
```

### Issue Investigation
```bash
# Investigate errors
./debug-master.sh logs --errors-only --recent

# Check network issues
./debug-master.sh network --verbose

# Full diagnostic sweep
./debug-master.sh --full --verbose
```

### Automated Recovery
```bash
# Check and auto-fix issues
./debug-master.sh --full --fix

# Specific recovery scenarios
./recovery-tools.sh tunnel-restart      # SSH tunnel issues
./recovery-tools.sh vllm-restart        # vLLM server problems  
./recovery-tools.sh memory-cleanup      # Memory/GPU issues
./recovery-tools.sh full-recovery       # Complete recovery
```

## 📋 Issue Detection and Resolution

### SSH Tunnel Issues
**Symptoms:** Connection refused, tunnel not accessible
**Detection:** Network diagnostics, health checks
**Auto-fixes:** Tunnel restart, SSH key permission correction

### vLLM Server Problems
**Symptoms:** API not responding, model inference failures
**Detection:** Health checks, API testing, log analysis
**Auto-fixes:** Server restart, process cleanup, memory clearing

### GPU/Memory Issues
**Symptoms:** CUDA out of memory, low performance
**Detection:** GPU monitoring, error pattern analysis
**Auto-fixes:** Memory cleanup, process termination, GPU reset

### API Authentication Issues
**Symptoms:** HTTP 401 errors, authentication failures
**Detection:** API endpoint testing, log analysis
**Auto-fixes:** Configuration validation, key verification

## 🔍 Monitoring and Alerting

### Real-time Monitoring
```bash
# GPU monitoring dashboard
./gpu-monitor.sh --realtime

# Live log analysis
./log-analyzer.sh --follow

# Network connectivity monitoring
./network-diagnostics.sh --continuous
```

### Alert Thresholds
```bash
# Custom GPU temperature threshold
./gpu-monitor.sh --threshold-temp 85

# Custom memory usage threshold  
./gpu-monitor.sh --threshold-mem 95

# Check for alerts
./gpu-monitor.sh --alerts
```

### Performance Baselines
```bash
# Historical performance analysis
./gpu-monitor.sh --history
./log-analyzer.sh --performance

# Trend identification
./log-analyzer.sh --recent --summary
```

## 🤖 Automation and Integration

### JSON Output for Scripts
```bash
# All tools support JSON output
./health-check.sh --json
./network-diagnostics.sh --json
./gpu-monitor.sh --json
./log-analyzer.sh --json
./recovery-tools.sh --json
```

### Cron Job Integration
```bash
# Daily health check (example crontab entry)
0 8 * * * /path/to/debug-master.sh --quick --json >> /var/log/vllm-health.log

# Hourly monitoring
0 * * * * /path/to/gpu-monitor.sh --alerts --json >> /var/log/gpu-alerts.log
```

### CI/CD Integration
```bash
# Health check in deployment pipeline
./health-check.sh --json | jq '.overall_status == "PASS"'

# Performance validation
./gpu-monitor.sh --json | jq '.gpus[].utilization_gpu > 50'
```

## 🐛 Troubleshooting Common Issues

### Scripts Not Executable
```bash
chmod +x *.sh
# or
./debug-master.sh  # Will auto-fix permissions
```

### Missing Dependencies
```bash
# Install required tools
sudo apt-get install jq bc curl nvidia-utils

# Check nvidia-smi availability
nvidia-smi --version
```

### SSH Key Issues
```bash
# Fix SSH key permissions
chmod 600 ~/.ssh/qwen3-deploy-20250731-114902

# Test SSH connectivity
./network-diagnostics.sh --tunnel-only --verbose
```

### API Connection Issues
```bash
# Check tunnel status
./network-diagnostics.sh --api-only

# Verify API key
export VLLM_API_KEY='your-api-key'
./health-check.sh --verbose
```

## 📝 Log Files and Output

### Log Locations
- Health checks: Output to console (can redirect)
- GPU monitoring: `~/.vllm-gpu-monitor.log`
- Recovery actions: `~/.vllm-recovery.log`
- vLLM server logs: `/var/log/vllm/vllm-*.log`

### Verbose Output
```bash
# Enable verbose output for any tool
./debug-master.sh health --verbose
./network-diagnostics.sh --verbose
./recovery-tools.sh --verbose
```

## 🔧 Configuration

### Environment Variables
```bash
export VLLM_API_KEY='your-api-key'
export CUDA_VISIBLE_DEVICES='0,1,2,3'
```

### Customizable Thresholds
```bash
# GPU temperature alerts
./gpu-monitor.sh --threshold-temp 80

# Memory usage alerts
./gpu-monitor.sh --threshold-mem 90

# Custom log analysis
./log-analyzer.sh --recent --tail 2000
```

## 📊 Performance Metrics

### GPU Metrics
- Utilization percentage
- Memory usage and availability
- Temperature monitoring
- Power consumption
- Clock speeds

### API Performance
- Request latency
- Throughput (tokens/second)
- Success rates
- Error frequencies

### System Health
- Process status
- Memory usage
- Network connectivity
- Service availability

## 🆘 Emergency Procedures

### Complete System Recovery
```bash
# Nuclear option - full recovery sequence
./recovery-tools.sh full-recovery --verbose

# Manual step-by-step
./recovery-tools.sh process-cleanup
./recovery-tools.sh memory-cleanup
./recovery-tools.sh tunnel-restart
./recovery-tools.sh vllm-restart
```

### Quick Status Check
```bash
# Fast status overview
./debug-master.sh status

# If urgent issues
./debug-master.sh --quick --fix
```

### Emergency Contacts
- Check vLLM server logs: `tail -f /var/log/vllm/vllm-*.log`
- GPU status: `nvidia-smi`
- System resources: `htop` or `top`
- Network: `netstat -tlnp | grep 8000`

---

## 🎯 Best Practices

1. **Run daily health checks** to catch issues early
2. **Monitor GPU temperature** and memory usage continuously
3. **Analyze logs regularly** for error patterns
4. **Use auto-fix cautiously** in production environments
5. **Keep recovery logs** for troubleshooting patterns
6. **Test network connectivity** after any infrastructure changes
7. **Monitor performance trends** to identify degradation

## 📞 Support

For issues with these tools:
1. Run with `--verbose` flag for detailed output
2. Check log files for error details
3. Use `--dry-run` to see what recovery actions would do
4. Test individual components with specific tools

The debugging toolkit is designed to be self-contained and provide clear, actionable information for resolving vLLM infrastructure issues quickly and efficiently.