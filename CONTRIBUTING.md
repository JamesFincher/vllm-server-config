# Contributing to vLLM Server Configuration

Thank you for your interest in contributing to this vLLM server configuration project! This repository contains production-tested configurations for running Qwen3-480B with vLLM on high-end GPU systems.

## Table of Contents

- [How to Contribute](#how-to-contribute)
- [Development Setup](#development-setup)
- [Configuration Testing](#configuration-testing)
- [Submitting Changes](#submitting-changes)
- [Code Style Guidelines](#code-style-guidelines)
- [Hardware Testing](#hardware-testing)
- [Reporting Issues](#reporting-issues)

## How to Contribute

We welcome contributions in several areas:

### 🔧 Configuration Improvements
- Optimizations for different GPU configurations
- Memory usage improvements
- Performance tuning for specific hardware

### 📚 Documentation
- Setup guides for different operating systems
- Troubleshooting guides
- Performance benchmarking results

### 🐛 Bug Fixes
- Script corrections
- Environment setup issues
- Documentation errors

### ✨ New Features
- Support for additional models
- Alternative deployment methods
- Monitoring and logging improvements

## Development Setup

1. **Fork the Repository**
   ```bash
   git clone <your-fork-url>
   cd vllm-server-config
   ```

2. **Create a Development Branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Test Environment**
   - Ensure you have access to compatible hardware (see README.md requirements)
   - Set up a virtual environment for testing
   - Use the provided `environment-template.sh` as a starting point

## Configuration Testing

### Required Testing

Before submitting configuration changes, please test:

1. **Startup Success**
   - Script runs without errors
   - Model loads successfully
   - API endpoint responds

2. **Memory Usage**
   - Monitor GPU memory utilization
   - Check for memory leaks during operation
   - Document maximum stable context length

3. **Performance Benchmarks**
   - Measure tokens per second
   - Test response latency
   - Document any quality changes (if applicable)

### Testing Checklist

- [ ] Script has proper error handling
- [ ] Environment variables are validated
- [ ] Logs are written to appropriate locations
- [ ] API key handling is secure
- [ ] Compatible with existing directory structure

## Submitting Changes

1. **Create a Pull Request**
   - Use descriptive titles
   - Include detailed description of changes
   - Reference any related issues

2. **Pull Request Requirements**
   - All scripts must be tested on target hardware
   - Include documentation updates if applicable
   - Follow the established script header format
   - No hardcoded sensitive information

3. **Pull Request Template**
   ```markdown
   ## Description
   Brief description of changes

   ## Hardware Tested
   - GPU: [e.g., 4x H200 140GB]
   - RAM: [e.g., 700GB]
   - OS: [e.g., Ubuntu 22.04]

   ## Performance Results
   - Context Length: [e.g., 700k tokens]
   - Memory Usage: [e.g., 98% GPU utilization]
   - Throughput: [e.g., 15-20 tokens/sec]

   ## Changes Made
   - [ ] Configuration optimization
   - [ ] Documentation update  
   - [ ] Bug fix
   - [ ] New feature

   ## Testing Completed
   - [ ] Startup testing
   - [ ] Memory usage validation
   - [ ] Performance benchmarking
   ```

## Code Style Guidelines

### Shell Scripts

1. **Header Format**
   ```bash
   #!/bin/bash
   # Script Name - Brief Description
   # Purpose and configuration details
   #
   # Configuration:
   # - Key parameters and settings
   # - Hardware requirements
   # - Performance characteristics
   ```

2. **Error Handling**
   ```bash
   set -e  # Exit on error
   
   # Validate environment variables
   if [[ -z "$REQUIRED_VAR" ]]; then
       echo "Error: REQUIRED_VAR must be set"
       exit 1
   fi
   ```

3. **Logging**
   ```bash
   # Use timestamped logs
   LOG_FILE="/var/log/vllm/script_name_$(date +%Y%m%d-%H%M%S).log"
   mkdir -p "$(dirname "$LOG_FILE")"
   ```

### Documentation

1. **Use clear, descriptive headings**
2. **Include code examples where appropriate**
3. **Document hardware requirements**
4. **Provide troubleshooting information**

## Hardware Testing

### Minimum Testing Requirements

For configuration submissions, testing should be performed on:

- **GPU**: NVIDIA H100/H200 series (or equivalent with 80GB+ VRAM)
- **Memory**: 500GB+ system RAM
- **Storage**: NVMe SSD with 1TB+ available space

### Testing Documentation

Include in your PR:

1. **Hardware Specifications**
   - Exact GPU models and memory
   - System RAM
   - CPU specifications
   - Storage type and speed

2. **Performance Metrics**
   - Maximum stable context length
   - Memory utilization at stable operation
   - Tokens per second throughput
   - Model loading time

3. **Stability Testing**
   - Duration of testing (minimum 1 hour)
   - Any crashes or errors encountered
   - Memory leak observations

## Reporting Issues

### Bug Reports

Please include:

1. **Environment Information**
   - Operating system and version
   - Hardware specifications
   - vLLM version
   - Python version

2. **Reproduction Steps**
   - Exact commands run
   - Configuration used
   - Expected vs actual behavior

3. **Logs and Error Messages**
   - Full error traces
   - Relevant log excerpts
   - System resource usage at time of error

### Feature Requests

For new features, please:

1. **Describe the use case**
2. **Explain expected benefits**
3. **Consider implementation complexity**
4. **Discuss hardware compatibility**

## Getting Help

- **Issues**: Use GitHub issues for bug reports and feature requests
- **Discussions**: Use GitHub discussions for general questions
- **Documentation**: Check existing docs first

## Recognition

Contributors will be acknowledged in:
- Repository contributors list
- Release notes for significant contributions
- Documentation credits where appropriate

Thank you for helping improve this project! 🚀