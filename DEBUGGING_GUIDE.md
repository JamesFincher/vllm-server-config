# vLLM Infrastructure Debugging and Troubleshooting Guide

## 🎯 Overview

This comprehensive debugging toolkit addresses the specific issues identified in your chat history with the vLLM server setup. Based on the problems you encountered - CRUSH connection issues, API authentication failures, SSH tunnel problems, and GPU memory management - these tools provide automated solutions and clear diagnostic information.

## 🚨 Common Issues from Your Setup

### Issue 1: CRUSH API Connection Problems
**What happened:** CRUSH couldn't connect to your vLLM server despite working curl tests
**Solution:** Use the network diagnostics and API testing tools

```bash
# Diagnose CRUSH connection issues
./scripts/debugging/debug-master.sh network --verbose

# Test API with exact CRUSH configuration
./scripts/debugging/network-diagnostics.sh --api-only --fix-issues

# Check model ID compatibility
curl -s http://localhost:8000/v1/models -H "Authorization: Bearer qwen3-secret-key" | jq
```

### Issue 2: SSH Tunnel Connectivity 
**What happened:** SSH tunnel would work but then CRUSH couldn't connect through it
**Solution:** Automated tunnel management and health checking

```bash
# Check tunnel health
./scripts/debugging/network-diagnostics.sh --tunnel-only

# Restart tunnel if needed
./scripts/debugging/recovery-tools.sh tunnel-restart

# Monitor tunnel continuously
./scripts/debugging/network-diagnostics.sh --continuous
```

### Issue 3: vLLM Server Performance and Memory
**What happened:** Server would work but sometimes have memory issues or slow responses
**Solution:** GPU monitoring and performance analysis

```bash
# Check current GPU status
./scripts/debugging/gpu-monitor.sh --summary

# Monitor performance in real-time
./scripts/debugging/gpu-monitor.sh --realtime

# Analyze server logs for memory issues
./scripts/debugging/log-analyzer.sh --errors-only --recent
```

## 🎛️ Quick Start for Your Specific Setup

### Daily Workflow
```bash
# 1. Morning health check
./scripts/debugging/debug-master.sh --quick

# 2. If issues found, auto-fix them
./scripts/debugging/debug-master.sh --full --fix

# 3. Start monitoring if needed
./scripts/debugging/debug-master.sh --monitor
```

### When CRUSH Stops Working
```bash
# Step 1: Quick diagnosis
./scripts/debugging/debug-master.sh network

# Step 2: Check what's broken
./scripts/debugging/health-check.sh --verbose

# Step 3: Auto-fix common issues
./scripts/debugging/recovery-tools.sh --check-all --auto-fix

# Step 4: Test the fix
curl -s http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer qwen3-secret-key" \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen3", "messages": [{"role": "user", "content": "test"}], "max_tokens": 5}'
```

### Performance Monitoring (Based on Your Speed Tests)
```bash
# Check current performance (you were getting ~75 tokens/sec)
./scripts/debugging/log-analyzer.sh --performance

# Monitor GPU usage during inference
./scripts/debugging/gpu-monitor.sh --realtime

# Historical performance analysis
./scripts/debugging/gpu-monitor.sh --history
```

## 🔧 Tool Mapping to Your Issues

### For "HTTP 400 Bad Request" Errors
**Tools:** `log-analyzer.sh`, `network-diagnostics.sh`
```bash
# Analyze the exact error patterns
./scripts/debugging/log-analyzer.sh --errors-only --recent

# Test different model name formats (qwen3 vs /models/qwen3)
./scripts/debugging/network-diagnostics.sh --api-only --verbose
```

### For "Unauthorized" API Errors  
**Tools:** `health-check.sh`, `network-diagnostics.sh`
```bash
# Check API key configuration
./scripts/debugging/health-check.sh --verbose

# Test authentication
./scripts/debugging/network-diagnostics.sh --api-only
```

### For SSH Tunnel Issues
**Tools:** `network-diagnostics.sh`, `recovery-tools.sh`
```bash
# Complete tunnel diagnostics
./scripts/debugging/network-diagnostics.sh --tunnel-only --verbose

# Restart tunnel if needed
./scripts/debugging/recovery-tools.sh tunnel-restart
```

### For vLLM Server Crashes or Hangs
**Tools:** `log-analyzer.sh`, `recovery-tools.sh`, `gpu-monitor.sh`
```bash
# Check what caused the crash
./scripts/debugging/log-analyzer.sh --errors-only

# Check GPU memory status
./scripts/debugging/gpu-monitor.sh --alerts

# Restart server if needed
./scripts/debugging/recovery-tools.sh vllm-restart
```

## 📊 Performance Baselines (Your Setup)

Based on your testing results:
- **Model:** Qwen3-480B (qwen3)
- **Response Time:** ~0.87 seconds for simple requests
- **Token Generation:** ~75 tokens/second
- **API Endpoint:** http://localhost:8000/v1
- **Model ID:** "qwen3" (not "/models/qwen3")

### Monitor Against These Baselines
```bash
# Set up monitoring with your baseline thresholds
./scripts/debugging/gpu-monitor.sh --threshold-temp 85 --threshold-mem 95

# Check if performance degrades below your baseline
./scripts/debugging/log-analyzer.sh --performance | grep "tokens/s"
```

## 🤖 Automation for Your Environment

### Environment Variables (From Your Setup)
```bash
export VLLM_API_KEY='qwen3-secret-key'
export SSH_KEY="$HOME/.ssh/qwen3-deploy-20250731-114902"
export SERVER_IP="86.38.238.64"
```

### Automated Health Checks
```bash
# Add to your crontab for automated monitoring
# Daily health check at 8 AM
0 8 * * * /path/to/scripts/debugging/debug-master.sh --quick --json >> ~/.vllm-daily-health.log

# Hourly CRUSH connectivity check
0 * * * * /path/to/scripts/debugging/network-diagnostics.sh --api-only --json >> ~/.vllm-api-check.log
```

### Integration with Your Connection Script
You can integrate these tools with your existing `connect.sh` script:

```bash
# Add health check to your connection script
health-check() {
    echo "Running health check..."
    /path/to/scripts/debugging/health-check.sh --verbose
    if [ $? -ne 0 ]; then
        echo "Issues detected. Running recovery..."
        /path/to/scripts/debugging/recovery-tools.sh --check-all --auto-fix
    fi
}

# Add to your connect.sh
case $1 in
    # ... your existing cases ...
    health)
        health-check
        ;;
    debug)
        /path/to/scripts/debugging/debug-master.sh --full --verbose
        ;;
esac
```

## 🚨 Troubleshooting Your Specific Configuration

### CRUSH Configuration Issues
Based on your chat history, CRUSH had trouble finding the right configuration:

```bash
# Test the exact configuration CRUSH needs
./scripts/debugging/network-diagnostics.sh --verbose

# This will show the exact curl commands that work
# Use this information to update your CRUSH config
```

### Model Name Confusion
Your logs showed the server serves model as "qwen3" but paths reference "/models/qwen3":

```bash
# Check what model ID the server actually serves
curl -s http://localhost:8000/v1/models -H "Authorization: Bearer qwen3-secret-key" | jq '.data[].id'

# Test both formats
./scripts/debugging/network-diagnostics.sh --verbose
```

### Performance Verification
You tested token generation speed - use these tools to monitor it continuously:

```bash
# Continuous performance monitoring
./scripts/debugging/gpu-monitor.sh --realtime

# Performance regression detection
./scripts/debugging/log-analyzer.sh --performance --recent
```

## 📝 Logs and Debugging Information

### Key Log Locations for Your Setup
- vLLM server: `/var/log/vllm/vllm-*.log` (on remote server)
- Health checks: Console output (can redirect)
- GPU monitoring: `~/.vllm-gpu-monitor.log`
- Recovery actions: `~/.vllm-recovery.log`
- Network diagnostics: Console output

### Getting Debug Information
```bash
# Comprehensive debug output
./scripts/debugging/debug-master.sh --full --verbose 2>&1 | tee debug-output.log

# Specific to your connection issues
./scripts/debugging/network-diagnostics.sh --verbose 2>&1 | tee network-debug.log

# For performance analysis
./scripts/debugging/gpu-monitor.sh --summary --verbose 2>&1 | tee gpu-status.log
```

## 🎯 Success Indicators

### Healthy System Indicators
- Health check returns exit code 0
- API responds with HTTP 200 or proper JSON
- GPU utilization > 0% when processing requests
- SSH tunnel accessible on port 8000
- Model responds with proper inference

### Performance Indicators
- Response time < 2 seconds for simple requests
- Token generation > 50 tokens/second
- GPU memory usage stable
- No error patterns in logs
- API success rate > 95%

## 🔄 Regular Maintenance

### Daily Tasks
```bash
# Run this every morning
./scripts/debugging/debug-master.sh --quick
```

### Weekly Tasks  
```bash
# Comprehensive system analysis
./scripts/debugging/debug-master.sh --full --verbose

# Performance trend analysis
./scripts/debugging/gpu-monitor.sh --history
./scripts/debugging/log-analyzer.sh --performance
```

### When Making Changes
```bash
# Before changes
./scripts/debugging/debug-master.sh status > before-changes.log

# After changes
./scripts/debugging/debug-master.sh status > after-changes.log

# Compare
diff before-changes.log after-changes.log
```

## 🚀 Advanced Usage

### Custom Monitoring Dashboards
```bash
# Create real-time monitoring setup
# Terminal 1: GPU monitoring
./scripts/debugging/gpu-monitor.sh --realtime

# Terminal 2: Log monitoring  
./scripts/debugging/log-analyzer.sh --follow

# Terminal 3: Network monitoring
./scripts/debugging/network-diagnostics.sh --continuous
```

### Integration with Your Development Workflow
```bash
# Before starting work
./scripts/debugging/debug-master.sh --quick

# During development (if issues arise)
./scripts/debugging/debug-master.sh --full --fix

# Performance testing
./scripts/debugging/gpu-monitor.sh --summary
```

This toolkit is specifically designed to address the issues you encountered and provide automated solutions for maintaining your vLLM infrastructure. The tools are ready to use and should resolve the CRUSH connectivity, API authentication, and performance monitoring challenges you faced.