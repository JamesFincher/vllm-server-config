# CRUSH Integration Guide for vLLM Qwen3-480B

## Table of Contents
1. [Overview](#overview)
2. [CRUSH Installation](#crush-installation)
3. [Configuration Setup](#configuration-setup)
4. [Basic Usage](#basic-usage)
5. [Advanced Workflows](#advanced-workflows)
6. [Development Integration](#development-integration)
7. [Troubleshooting](#troubleshooting)
8. [Performance Optimization](#performance-optimization)
9. [Custom Extensions](#custom-extensions)
10. [Best Practices](#best-practices)

---

## Overview

CRUSH (Command Line AI) is a powerful command-line tool that integrates seamlessly with your local vLLM Qwen3-480B server, providing instant access to AI capabilities directly from your terminal. This integration transforms your development workflow by bringing 700k context AI assistance to every aspect of your work.

### Key Benefits

- **Local AI Power**: Full 700k context window with no external API calls
- **Zero Cost**: No per-token charges or API limits
- **Privacy**: All processing happens locally on your server
- **Speed**: Direct connection to your optimized vLLM instance
- **Integration**: Works with any command-line workflow
- **Unlimited Usage**: Process massive documents without restrictions

### What You Can Do

- 📝 **Document Analysis**: Process entire codebases, research papers, books
- 🔧 **Code Review**: Analyze large projects with full context
- 📊 **Data Processing**: Transform and analyze large datasets
- 🎯 **Content Generation**: Create comprehensive documentation, reports
- 🔍 **Research**: Synthesize information from multiple long sources
- 🛠️ **Development**: Get coding assistance with full project context

---

## CRUSH Installation

### Method 1: Official Installer (Recommended)

```bash
# Install CRUSH using the official installer
curl -sSL https://install.charm.sh/crush | bash

# Verify installation
crush --version
```

### Method 2: Manual Installation

```bash
# Download latest release
wget https://github.com/charmbracelet/crush/releases/latest/download/crush_linux_amd64.tar.gz

# Extract and install
tar -xzf crush_linux_amd64.tar.gz
sudo mv crush /usr/local/bin/

# Make executable
sudo chmod +x /usr/local/bin/crush

# Verify installation
crush --version
```

### Method 3: Build from Source

```bash
# Clone repository
git clone https://github.com/charmbracelet/crush.git
cd crush

# Build and install
go build -o crush
sudo mv crush /usr/local/bin/

# Verify installation
crush --version
```

### Post-Installation Setup

```bash
# Create CRUSH config directory
mkdir -p ~/.crush

# Verify CRUSH can run
crush --help
```

---

## Configuration Setup

### Basic Configuration

Create the CRUSH configuration file with your vLLM server settings:

```bash
# Create configuration file
cat > ~/.crush/config.json << 'EOF'
{
  "$schema": "https://charm.land/crush.json",
  "providers": {
    "vllm-local": {
      "type": "openai",
      "base_url": "http://localhost:8000/v1",
      "api_key": "YOUR_API_KEY_HERE",
      "models": [
        {
          "id": "qwen3",
          "name": "Qwen3-480B Local (700k context)",
          "context_window": 700000,
          "default_max_tokens": 8192,
          "cost_per_1m_in": 0,
          "cost_per_1m_out": 0
        }
      ]
    }
  },
  "default_provider": "vllm-local",
  "default_model": "qwen3",
  "options": {
    "debug": false,
    "stream": true,
    "temperature": 0.7,
    "max_tokens": 8192
  }
}
EOF
```

### Advanced Configuration

```bash
# Create advanced configuration with multiple profiles
cat > ~/.crush/config.json << 'EOF'
{
  "$schema": "https://charm.land/crush.json",
  "providers": {
    "vllm-local": {
      "type": "openai",
      "base_url": "http://localhost:8000/v1",
      "api_key": "YOUR_API_KEY_HERE",
      "models": [
        {
          "id": "qwen3",
          "name": "Qwen3-480B Local (700k context)",
          "context_window": 700000,
          "default_max_tokens": 8192,
          "cost_per_1m_in": 0,
          "cost_per_1m_out": 0
        },
        {
          "id": "qwen3-creative",
          "name": "Qwen3-480B Creative Mode",
          "context_window": 700000,
          "default_max_tokens": 8192,
          "cost_per_1m_in": 0,
          "cost_per_1m_out": 0,
          "temperature": 1.2
        },
        {
          "id": "qwen3-precise",
          "name": "Qwen3-480B Precise Mode",
          "context_window": 700000,
          "default_max_tokens": 8192,
          "cost_per_1m_in": 0,
          "cost_per_1m_out": 0,
          "temperature": 0.1
        }
      ]
    }
  },
  "default_provider": "vllm-local",
  "default_model": "qwen3",
  "profiles": {
    "code": {
      "model": "qwen3-precise",
      "system_prompt": "You are an expert programmer. Provide clear, efficient, and well-documented code solutions.",
      "temperature": 0.1,
      "max_tokens": 4096
    },
    "creative": {
      "model": "qwen3-creative",
      "system_prompt": "You are a creative AI assistant. Think outside the box and provide innovative solutions.",
      "temperature": 1.0,
      "max_tokens": 8192
    },
    "analysis": {
      "model": "qwen3",
      "system_prompt": "You are an analytical AI assistant. Provide thorough, evidence-based analysis.",
      "temperature": 0.3,
      "max_tokens": 8192
    }
  },
  "options": {
    "debug": false,
    "stream": true,
    "auto_save": true,
    "history_size": 1000
  }
}
EOF
```

### Configuration Validation

```bash
# Test configuration
crush config validate

# Test connection to vLLM server
crush test

# List available models
crush models

# Show current configuration
crush config show
```

### Environment Setup Script

```bash
#!/bin/bash
# setup_crush.sh - Automated CRUSH setup

set -e

echo "=== CRUSH Integration Setup ==="

# Check if vLLM server is running
if ! curl -s http://localhost:8000/health > /dev/null; then
    echo "Error: vLLM server not running on localhost:8000"
    echo "Please start your vLLM server first"
    exit 1
fi

# Get API key from environment or prompt user
if [ -z "$VLLM_API_KEY" ]; then
    echo "VLLM_API_KEY not set in environment"
    read -p "Enter your vLLM API key: " VLLM_API_KEY
fi

# Create CRUSH config directory
mkdir -p ~/.crush

# Generate configuration file
cat > ~/.crush/config.json << EOF
{
  "\$schema": "https://charm.land/crush.json",
  "providers": {
    "vllm-local": {
      "type": "openai",
      "base_url": "http://localhost:8000/v1",
      "api_key": "$VLLM_API_KEY",
      "models": [
        {
          "id": "qwen3",
          "name": "Qwen3-480B Local (700k context)",
          "context_window": 700000,
          "default_max_tokens": 8192,
          "cost_per_1m_in": 0,
          "cost_per_1m_out": 0
        }
      ]
    }
  },
  "default_provider": "vllm-local",
  "default_model": "qwen3",
  "options": {
    "debug": false,
    "stream": true,
    "temperature": 0.7,
    "max_tokens": 8192
  }
}
EOF

# Test configuration
echo "Testing CRUSH configuration..."
if crush test; then
    echo "✅ CRUSH setup successful!"
    echo ""
    echo "Try these commands:"
    echo "  crush 'Hello, how are you?'"
    echo "  crush -f README.md 'Summarize this file'"
    echo "  echo 'Write a Python function' | crush"
else
    echo "❌ CRUSH setup failed"
    echo "Please check your vLLM server and API key"
    exit 1
fi
```

---

## Basic Usage

### Simple Commands

```bash
# Basic chat
crush "Explain quantum computing in simple terms"

# Code generation
crush "Write a Python function to calculate fibonacci numbers"

# Problem solving
crush "How do I optimize a slow database query?"
```

### File Processing

```bash
# Analyze a file
crush -f document.txt "Summarize this document"

# Multiple files
crush -f file1.py -f file2.py "Compare these two Python scripts"

# Process from stdin
cat large_log.txt | crush "Extract error patterns from this log"

# Directory analysis
find . -name "*.py" | head -10 | xargs cat | crush "Review this codebase and suggest improvements"
```

### Interactive Mode

```bash
# Start interactive session
crush -i

# In interactive mode:
> How do neural networks work?
> Can you give me a Python example?
> What are the limitations?
> exit
```

### Using Profiles

```bash
# Use coding profile
crush --profile code "Implement a binary search algorithm"

# Use creative profile
crush --profile creative "Write a sci-fi story about AI"

# Use analysis profile
crush --profile analysis -f research_paper.pdf "Analyze the methodology"
```

---

## Advanced Workflows

### Code Review Workflow

```bash
#!/bin/bash
# code_review.sh - Automated code review with CRUSH

# Review changes in current branch
git diff HEAD~1 | crush --profile code "Review these code changes and provide detailed feedback on:
1. Code quality and best practices
2. Potential bugs or issues
3. Performance considerations
4. Security implications
5. Suggested improvements"

# Review entire file
crush --profile code -f src/main.py "Provide a comprehensive code review focusing on:
- Architecture and design patterns
- Error handling
- Code maintainability
- Performance optimizations
- Security best practices"

# Generate documentation
crush --profile code -f src/api.py "Generate comprehensive API documentation for this code including:
- Function descriptions
- Parameter details
- Return values
- Usage examples
- Error conditions"
```

### Document Processing Pipeline

```bash
#!/bin/bash
# document_pipeline.sh - Process large documents with CRUSH

INPUT_FILE="$1"
OUTPUT_DIR="processed_docs"

mkdir -p "$OUTPUT_DIR"

echo "Processing document: $INPUT_FILE"

# Generate summary
crush -f "$INPUT_FILE" "Create a comprehensive summary of this document including:
- Main topics and themes
- Key findings or conclusions
- Important statistics or data points
- Action items or recommendations" > "$OUTPUT_DIR/summary.md"

# Extract key points
crush -f "$INPUT_FILE" "Extract the top 20 most important points from this document. Format as a numbered list with brief explanations." > "$OUTPUT_DIR/key_points.md"

# Generate questions
crush -f "$INPUT_FILE" "Generate 15 thoughtful questions that could be used to test understanding of this document's content." > "$OUTPUT_DIR/questions.md"

# Create outline
crush -f "$INPUT_FILE" "Create a detailed outline of this document's structure and content." > "$OUTPUT_DIR/outline.md"

echo "Document processing complete. Results in $OUTPUT_DIR/"
```

### Research Synthesis

```bash
#!/bin/bash
# research_synthesis.sh - Synthesize multiple research sources

RESEARCH_DIR="research_papers"
OUTPUT_FILE="synthesis_report.md"

echo "# Research Synthesis Report" > "$OUTPUT_FILE"
echo "Generated on: $(date)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Process all PDF files in research directory
for pdf in "$RESEARCH_DIR"/*.pdf; do
    echo "Processing: $pdf"
    
    # Extract key findings from each paper
    crush -f "$pdf" "Extract the key findings, methodology, and conclusions from this research paper. Focus on novel contributions and significant results." >> temp_findings.txt
done

# Synthesize all findings
crush -f temp_findings.txt "Synthesize these research findings into a comprehensive report that:
1. Identifies common themes and patterns
2. Highlights contradictions or conflicting results
3. Suggests areas for future research
4. Provides an integrated conclusion
5. Creates a bibliography of the most relevant points

Format as a professional research synthesis report." >> "$OUTPUT_FILE"

rm temp_findings.txt
echo "Research synthesis complete: $OUTPUT_FILE"
```

### Development Assistant Integration

```bash
#!/bin/bash
# dev_assistant.sh - Development workflow integration

# Function to get AI assistance for git commits
ai_commit() {
    local changes=$(git diff --cached)
    if [ -z "$changes" ]; then
        echo "No staged changes found"
        return 1
    fi
    
    local commit_msg=$(echo "$changes" | crush --profile code "Generate a clear, concise git commit message for these changes. Follow conventional commit format.")
    
    echo "Suggested commit message:"
    echo "$commit_msg"
    echo ""
    read -p "Use this commit message? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git commit -m "$commit_msg"
    fi
}

# Function to explain code
explain_code() {
    local file="$1"
    crush --profile code -f "$file" "Explain this code in detail, including:
    - What it does
    - How it works
    - Key algorithms or patterns used
    - Potential improvements
    - Usage examples"
}

# Function to generate tests
generate_tests() {
    local file="$1"
    crush --profile code -f "$file" "Generate comprehensive unit tests for this code. Include:
    - Test cases for normal operation
    - Edge cases and error conditions
    - Mock objects where needed
    - Test setup and teardown
    Use appropriate testing framework for the language."
}

# Function to refactor code
refactor_code() {
    local file="$1"
    crush --profile code -f "$file" "Suggest refactoring improvements for this code:
    - Extract methods/functions where appropriate
    - Improve naming conventions
    - Reduce complexity
    - Apply design patterns
    - Enhance readability
    Provide the refactored code with explanations."
}

# Make functions available
export -f ai_commit explain_code generate_tests refactor_code

echo "Development assistant functions loaded:"
echo "  ai_commit - Generate AI commit messages"
echo "  explain_code <file> - Explain code functionality"
echo "  generate_tests <file> - Generate unit tests"
echo "  refactor_code <file> - Suggest refactoring"
```

---

## Development Integration

### IDE Integration

**VS Code Integration:**
```json
// .vscode/tasks.json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "AI Code Review",
            "type": "shell",
            "command": "crush",
            "args": [
                "--profile", "code",
                "-f", "${file}",
                "Review this code for quality, bugs, and improvements"
            ],
            "group": "build",
            "presentation": {
                "echo": true,
                "reveal": "always",
                "focus": false,
                "panel": "new"
            }
        },
        {
            "label": "AI Explain Code",
            "type": "shell",
            "command": "crush",
            "args": [
                "--profile", "code",
                "-f", "${file}",
                "Explain this code in detail with examples"
            ],
            "group": "build"
        },
        {
            "label": "AI Generate Tests",
            "type": "shell",
            "command": "crush",
            "args": [
                "--profile", "code",
                "-f", "${file}",
                "Generate comprehensive unit tests for this code"
            ],
            "group": "test"
        }
    ]
}
```

**Vim Integration:**
```vim
" ~/.vimrc additions for CRUSH integration

" AI code review
command! AIReview !crush --profile code -f % "Review this code for quality and improvements"

" AI explain selection
vnoremap <leader>ae :w !crush --profile code "Explain this code:"<CR>

" AI generate comment
command! AIComment !crush --profile code -f % "Generate detailed comments for this code"

" AI refactor suggestions
command! AIRefactor !crush --profile code -f % "Suggest refactoring improvements"
```

### Git Hooks Integration

```bash
#!/bin/bash
# .git/hooks/pre-commit - AI-assisted pre-commit hook

# Check if CRUSH is available
if ! command -v crush &> /dev/null; then
    echo "CRUSH not available, skipping AI checks"
    exit 0
fi

echo "Running AI-assisted pre-commit checks..."

# Get staged files
staged_files=$(git diff --cached --name-only --diff-filter=ACM)

# Check for potential issues
for file in $staged_files; do
    if [[ "$file" =~ \.(py|js|ts|go|java|cpp|c)$ ]]; then
        echo "Checking $file..."
        
        # Get AI review of the file
        review=$(crush --profile code -f "$file" "Quick code review: identify any obvious bugs, security issues, or code quality problems. Be concise.")
        
        # Check if review indicates problems
        if echo "$review" | grep -qi "bug\|error\|issue\|problem\|security\|vulnerability"; then
            echo "⚠️  AI found potential issues in $file:"
            echo "$review"
            echo ""
            read -p "Continue with commit? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
done

echo "✅ AI pre-commit checks passed"
```

### Continuous Integration

```yaml
# .github/workflows/ai-review.yml
name: AI Code Review

on:
  pull_request:
    branches: [ main, develop ]

jobs:
  ai-review:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Install CRUSH
      run: |
        curl -sSL https://install.charm.sh/crush | bash
        echo "$HOME/.local/bin" >> $GITHUB_PATH
    
    - name: Setup CRUSH config
      run: |
        mkdir -p ~/.crush
        cat > ~/.crush/config.json << EOF
        {
          "providers": {
            "vllm-local": {
              "type": "openai",
              "base_url": "${{ secrets.VLLM_BASE_URL }}",
              "api_key": "${{ secrets.VLLM_API_KEY }}",
              "models": [{"id": "qwen3", "name": "Qwen3-480B"}]
            }
          },
          "default_provider": "vllm-local",
          "default_model": "qwen3"
        }
        EOF
    
    - name: AI Code Review
      run: |
        # Get changed files
        changed_files=$(git diff --name-only origin/main...HEAD | grep -E '\.(py|js|ts|go|java)$' | head -10)
        
        for file in $changed_files; do
          if [ -f "$file" ]; then
            echo "## AI Review: $file" >> review_comment.md
            crush --profile code -f "$file" "Provide a code review focusing on bugs, security, and best practices. Be constructive and specific." >> review_comment.md
            echo "" >> review_comment.md
          fi
        done
    
    - name: Comment PR
      if: hashFiles('review_comment.md') != ''
      uses: actions/github-script@v6
      with:
        script: |
          const fs = require('fs');
          const review = fs.readFileSync('review_comment.md', 'utf8');
          
          github.rest.issues.createComment({
            issue_number: context.issue.number,
            owner: context.repo.owner,
            repo: context.repo.repo,
            body: `# 🤖 AI Code Review\n\n${review}`
          });
```

---

## Troubleshooting

### Common Issues

#### 1. Connection Refused

**Symptoms:**
- `Error: connection refused`
- `Failed to connect to server`

**Solutions:**
```bash
# Check if vLLM server is running
curl http://localhost:8000/health

# Verify server is accepting connections
netstat -tlnp | grep 8000

# Test with correct API key
crush test

# Check CRUSH configuration
crush config show
```

#### 2. Authentication Errors

**Symptoms:**
- `401 Unauthorized`
- `Invalid API key`

**Solutions:**
```bash
# Update API key in config
crush config set api_key "your-correct-api-key"

# Or edit config file directly
vim ~/.crush/config.json

# Test authentication
crush test
```

#### 3. Slow Responses

**Symptoms:**
- Long delays before responses
- Timeouts

**Solutions:**
```bash
# Check server performance
curl -w "Time: %{time_total}s\n" -X POST http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen3", "messages": [{"role": "user", "content": "test"}], "max_tokens": 10}'

# Reduce max_tokens in CRUSH config
crush config set max_tokens 2048

# Use streaming for long responses
crush config set stream true
```

#### 4. Context Length Errors

**Symptoms:**
- `Context length exceeded`
- `Request too large`

**Solutions:**
```bash
# Check file size before processing
wc -w large_file.txt

# Split large files
split -l 1000 large_file.txt chunk_

# Process chunks separately
for chunk in chunk_*; do
    crush -f "$chunk" "Summarize this section" >> summaries.txt
done

# Final synthesis
crush -f summaries.txt "Create a comprehensive summary from these section summaries"
```

### Debug Mode

```bash
# Enable debug mode
crush config set debug true

# Or use debug flag
crush --debug "test message"

# Check logs
tail -f ~/.crush/logs/crush.log
```

### Health Check Script

```bash
#!/bin/bash
# crush_health_check.sh

echo "=== CRUSH Health Check ==="

# 1. Check CRUSH installation
if command -v crush &> /dev/null; then
    echo "✅ CRUSH installed: $(crush --version)"
else
    echo "❌ CRUSH not installed"
    exit 1
fi

# 2. Check configuration
if [ -f ~/.crush/config.json ]; then
    echo "✅ Configuration file exists"
    
    # Validate JSON
    if python3 -m json.tool ~/.crush/config.json > /dev/null 2>&1; then
        echo "✅ Configuration is valid JSON"
    else
        echo "❌ Configuration has JSON syntax errors"
    fi
else
    echo "❌ Configuration file not found"
    exit 1
fi

# 3. Check vLLM server
if curl -s http://localhost:8000/health > /dev/null; then
    echo "✅ vLLM server responding"
else
    echo "❌ vLLM server not responding"
    echo "   Make sure your vLLM server is running on localhost:8000"
fi

# 4. Test CRUSH connection
echo "Testing CRUSH connection..."
if output=$(crush "Hello" 2>&1); then
    echo "✅ CRUSH test successful"
    echo "   Response: ${output:0:50}..."
else
    echo "❌ CRUSH test failed"
    echo "   Error: $output"
fi

echo "=== Health Check Complete ==="
```

---

## Performance Optimization

### Configuration Tuning

```bash
# Optimize for speed
crush config set stream true
crush config set max_tokens 2048
crush config set temperature 0.1

# Optimize for quality
crush config set temperature 0.7
crush config set max_tokens 8192
```

### Batch Processing

```bash
#!/bin/bash
# batch_process.sh - Efficient batch processing with CRUSH

INPUT_DIR="$1"
OUTPUT_DIR="$2"
BATCH_SIZE=5

mkdir -p "$OUTPUT_DIR"

# Process files in batches
files=($(find "$INPUT_DIR" -name "*.txt" | head -20))
total=${#files[@]}

for ((i=0; i<total; i+=BATCH_SIZE)); do
    batch_files=("${files[@]:i:BATCH_SIZE}")
    
    echo "Processing batch $((i/BATCH_SIZE + 1)): ${batch_files[@]}"
    
    # Process batch in parallel
    for file in "${batch_files[@]}"; do
        filename=$(basename "$file")
        (
            crush -f "$file" "Summarize this document concisely" > "$OUTPUT_DIR/${filename%.txt}_summary.txt"
        ) &
    done
    
    # Wait for batch to complete
    wait
    
    echo "Batch complete. Processed $((i + BATCH_SIZE < total ? i + BATCH_SIZE : total))/$total files"
done

echo "All files processed."
```

### Caching Strategies

```bash
#!/bin/bash
# crush_cache.sh - Implement caching for CRUSH responses

CACHE_DIR="$HOME/.crush/cache"
mkdir -p "$CACHE_DIR"

cached_crush() {
    local prompt="$1"
    local cache_key=$(echo "$prompt" | sha256sum | cut -d' ' -f1)
    local cache_file="$CACHE_DIR/$cache_key"
    
    # Check if cached response exists and is less than 1 day old
    if [ -f "$cache_file" ] && [ $(($(date +%s) - $(stat -c %Y "$cache_file"))) -lt 86400 ]; then
        echo "Using cached response..."
        cat "$cache_file"
    else
        echo "Generating new response..."
        crush "$prompt" | tee "$cache_file"
    fi
}

# Usage
cached_crush "Explain machine learning"
```

### Memory Management

```bash
#!/bin/bash
# crush_memory_manager.sh - Monitor and manage CRUSH memory usage

monitor_crush_usage() {
    while true; do
        # Get CRUSH process info
        if pgrep -f crush > /dev/null; then
            pid=$(pgrep -f crush)
            memory=$(ps -p $pid -o rss= | awk '{print $1/1024}')
            cpu=$(ps -p $pid -o %cpu= | awk '{print $1}')
            
            echo "$(date): CRUSH - Memory: ${memory}MB, CPU: ${cpu}%"
            
            # Alert if memory usage is high
            if (( $(echo "$memory > 1000" | bc -l) )); then
                echo "WARNING: High memory usage detected"
            fi
        fi
        
        sleep 30
    done
}

# Run in background
monitor_crush_usage &
monitor_pid=$!

echo "Memory monitoring started (PID: $monitor_pid)"
echo "Kill with: kill $monitor_pid"
```

---

## Custom Extensions

### Custom CRUSH Commands

```bash
#!/bin/bash
# ~/.crush/extensions/code_review.sh - Custom code review extension

crush_code_review() {
    local file="$1"
    local review_type="${2:-standard}"
    
    case "$review_type" in
        "security")
            crush --profile code -f "$file" "Focus on security vulnerabilities and best practices in this code"
            ;;
        "performance")
            crush --profile code -f "$file" "Analyze this code for performance bottlenecks and optimization opportunities"
            ;;
        "style")
            crush --profile code -f "$file" "Review this code for style, naming conventions, and readability"
            ;;
        *)
            crush --profile code -f "$file" "Comprehensive code review covering quality, bugs, security, and improvements"
            ;;
    esac
}

# Make function available
export -f crush_code_review
```

### CRUSH Plugins

```python
#!/usr/bin/env python3
# ~/.crush/plugins/document_processor.py

import sys
import json
import subprocess
from pathlib import Path

class DocumentProcessor:
    def __init__(self):
        self.temp_dir = Path.home() / ".crush" / "temp"
        self.temp_dir.mkdir(exist_ok=True)
    
    def process_pdf(self, pdf_path, query):
        """Process PDF with OCR if needed"""
        try:
            # Try extracting text with pdftotext
            text_file = self.temp_dir / f"{Path(pdf_path).stem}.txt"
            subprocess.run(['pdftotext', pdf_path, str(text_file)], check=True)
            
            # Use CRUSH to process the text
            result = subprocess.run([
                'crush', '-f', str(text_file), query
            ], capture_output=True, text=True)
            
            return result.stdout
            
        except subprocess.CalledProcessError:
            return "Error processing PDF file"
    
    def process_multiple_files(self, file_paths, query):
        """Process multiple files and synthesize results"""
        summaries = []
        
        for file_path in file_paths:
            if file_path.endswith('.pdf'):
                summary = self.process_pdf(file_path, f"Summarize key points from this document")
            else:
                result = subprocess.run([
                    'crush', '-f', file_path, f"Summarize key points from this document"
                ], capture_output=True, text=True)
                summary = result.stdout
            
            summaries.append(f"File: {file_path}\nSummary: {summary}\n")
        
        # Synthesize all summaries
        combined_summary = "\n".join(summaries)
        temp_summary_file = self.temp_dir / "combined_summaries.txt"
        
        with open(temp_summary_file, 'w') as f:
            f.write(combined_summary)
        
        result = subprocess.run([
            'crush', '-f', str(temp_summary_file), query
        ], capture_output=True, text=True)
        
        return result.stdout

def main():
    if len(sys.argv) < 3:
        print("Usage: document_processor.py <command> <args...>")
        sys.exit(1)
    
    processor = DocumentProcessor()
    command = sys.argv[1]
    
    if command == "pdf":
        pdf_path = sys.argv[2]
        query = sys.argv[3] if len(sys.argv) > 3 else "Summarize this document"
        result = processor.process_pdf(pdf_path, query)
        print(result)
    
    elif command == "multi":
        file_paths = sys.argv[2:-1]
        query = sys.argv[-1]
        result = processor.process_multiple_files(file_paths, query)
        print(result)
    
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)

if __name__ == "__main__":
    main()
```

### Shell Functions Library

```bash
#!/bin/bash
# ~/.crush/lib/functions.sh - CRUSH utility functions library

# Load this with: source ~/.crush/lib/functions.sh

# Enhanced file processing
crush_file_enhanced() {
    local file="$1"
    local query="$2"
    local profile="${3:-analysis}"
    
    # Check file size and warn if large
    local size=$(wc -c < "$file")
    if [ $size -gt 1000000 ]; then  # 1MB
        echo "Warning: Large file detected ($(($size / 1024))KB)"
        read -p "Continue? (y/n): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && return 1
    fi
    
    # Process with appropriate profile
    crush --profile "$profile" -f "$file" "$query"
}

# Project-wide analysis
crush_project_analysis() {
    local project_dir="${1:-.}"
    local output_file="${2:-project_analysis.md}"
    
    echo "# Project Analysis Report" > "$output_file"
    echo "Generated on: $(date)" >> "$output_file"
    echo "" >> "$output_file"
    
    # Analyze structure
    echo "## Project Structure" >> "$output_file"
    tree "$project_dir" -I 'node_modules|.git|__pycache__|venv' >> "$output_file"
    echo "" >> "$output_file"
    
    # Analyze key files
    find "$project_dir" -name "*.py" -o -name "*.js" -o -name "*.ts" | head -10 | while read file; do
        echo "### Analysis: $file" >> "$output_file"
        crush --profile code -f "$file" "Provide a brief analysis of this code's purpose and key functionality" >> "$output_file"
        echo "" >> "$output_file"
    done
    
    echo "Project analysis complete: $output_file"
}

# Smart commit messages
crush_smart_commit() {
    # Check for staged changes
    if ! git diff --cached --quiet; then
        local changes=$(git diff --cached)
        local message=$(echo "$changes" | crush --profile code "Generate a concise, descriptive commit message for these changes. Use conventional commit format (type: description).")
        
        echo "Suggested commit message:"
        echo "$message"
        echo ""
        
        read -p "Use this message? (y/n): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git commit -m "$message"
        else
            echo "Commit cancelled"
        fi
    else
        echo "No staged changes found"
    fi
}

# Batch file processor
crush_batch_process() {
    local pattern="$1"
    local query="$2"
    local output_dir="${3:-batch_output}"
    
    mkdir -p "$output_dir"
    
    find . -name "$pattern" | while read file; do
        echo "Processing: $file"
        local basename=$(basename "$file" | sed 's/\.[^.]*$//')
        crush -f "$file" "$query" > "$output_dir/${basename}_processed.txt"
    done
    
    echo "Batch processing complete. Results in $output_dir/"
}

# Export functions
export -f crush_file_enhanced crush_project_analysis crush_smart_commit crush_batch_process
```

---

## Best Practices

### Command Optimization

```bash
# ✅ Good: Specific, clear prompts
crush "Write a Python function to parse JSON files with error handling"

# ❌ Avoid: Vague prompts
crush "Help me with Python"

# ✅ Good: Use appropriate profiles
crush --profile code -f script.py "Review this code"

# ✅ Good: Limit output when needed
crush --max-tokens 500 "Briefly explain quantum computing"
```

### File Processing Best Practices

```bash
# ✅ Good: Check file size first
ls -lh large_document.pdf
crush -f large_document.pdf "Summarize key points"

# ✅ Good: Process in chunks for very large files
split -l 1000 huge_log.txt chunk_
for chunk in chunk_*; do
    crush -f "$chunk" "Extract error patterns" >> errors.txt
done

# ✅ Good: Use appropriate context
crush -f README.md "As a new developer, explain how to get started with this project"
```

### Performance Best Practices

```bash
# ✅ Use streaming for long responses
crush config set stream true

# ✅ Cache frequently used responses
# Implement caching wrapper (see Performance Optimization section)

# ✅ Batch similar requests
# Process multiple files of same type together

# ✅ Monitor resource usage
# Keep an eye on memory and token usage
```

### Security Best Practices

```bash
# ✅ Never put sensitive data in prompts
# Sanitize files before processing
sed 's/password=.*/password=***REDACTED***/g' config.txt | crush "Analyze this config"

# ✅ Use environment variables for API keys
export VLLM_API_KEY="your-key-here"

# ✅ Be careful with code execution
# Don't blindly execute AI-generated code without review
```

### Integration Best Practices

```bash
# ✅ Create project-specific configurations
# Each project can have its own .crush/config.json

# ✅ Use version control for prompts
# Store commonly used prompts in version-controlled files

# ✅ Document your CRUSH workflows
# Create README files explaining your CRUSH setup and common commands

# ✅ Test configurations regularly
crush test  # Regular health checks
```

### Workflow Optimization

```bash
#!/bin/bash
# ~/.crush/workflows/daily_routine.sh

# Daily development routine with CRUSH

echo "=== Daily CRUSH Routine ==="

# 1. Health check
echo "1. Health check..."
crush test

# 2. Review yesterday's commits
echo "2. Reviewing recent commits..."
git log --since="1 day ago" --pretty=format:"%h %s" | \
    crush "Analyze these recent commits and suggest any follow-up tasks"

# 3. Check TODO comments in code
echo "3. Checking TODO items..."
grep -r "TODO\|FIXME\|HACK" --include="*.py" --include="*.js" . | \
    crush "Prioritize these TODO items and suggest which ones to tackle first"

# 4. Generate daily standup notes
echo "4. Generating standup notes..."
git log --since="1 day ago" --author="$(git config user.name)" --pretty=format:"%s" | \
    crush "Create concise standup notes based on these commits: what was accomplished, what's in progress, any blockers"

echo "=== Daily routine complete ==="
```

This comprehensive CRUSH integration guide transforms your vLLM Qwen3-480B server into a powerful development assistant, accessible directly from your command line with unlimited usage and full privacy. The 700k context window enables processing of entire codebases, books, and complex documents that would be impossible with traditional API-limited services.