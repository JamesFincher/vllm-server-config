#!/usr/bin/env python3
"""
Comprehensive Configuration Validation Tool for vLLM + CRUSH Setup
This tool validates all configuration files, environment variables, and system requirements.
"""

import os
import sys
import json
import subprocess
import argparse
import logging
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass
import yaml
import re

@dataclass
class ValidationResult:
    name: str
    status: str  # 'pass', 'fail', 'warning', 'info'
    message: str
    details: Optional[str] = None

class ConfigValidator:
    def __init__(self, config_dir: str = None):
        self.config_dir = Path(config_dir) if config_dir else Path(__file__).parent
        self.results: List[ValidationResult] = []
        self.setup_logging()
        
    def setup_logging(self):
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('config-validation.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)

    def validate_all(self) -> List[ValidationResult]:
        """Run all validation checks"""
        self.logger.info("Starting comprehensive configuration validation...")
        
        # Core configuration validation
        self.validate_crush_config()
        self.validate_environment_template()
        self.validate_claude_settings()
        
        # System validation
        self.validate_python_environment()
        self.validate_gpu_requirements()
        self.validate_network_configuration()
        
        # Scripts validation
        self.validate_scripts()
        
        # Integration validation
        self.validate_api_connectivity()
        self.validate_ssh_configuration()
        
        return self.results

    def add_result(self, name: str, status: str, message: str, details: str = None):
        """Add a validation result"""
        result = ValidationResult(name, status, message, details)
        self.results.append(result)
        
        log_level = {
            'pass': logging.INFO,
            'fail': logging.ERROR,
            'warning': logging.WARNING,
            'info': logging.INFO
        }.get(status, logging.INFO)
        
        self.logger.log(log_level, f"{name}: {message}")
        if details:
            self.logger.debug(f"Details: {details}")

    def validate_crush_config(self):
        """Validate CRUSH configuration file"""
        config_path = self.config_dir / "configs" / "crush-config.json"
        
        if not config_path.exists():
            self.add_result(
                "CRUSH Config File",
                "fail",
                f"Configuration file not found: {config_path}"
            )
            return
            
        try:
            with open(config_path) as f:
                config = json.load(f)
                
            # Validate schema
            required_fields = ["providers", "default_provider", "default_model"]
            for field in required_fields:
                if field not in config:
                    self.add_result(
                        "CRUSH Config Schema",
                        "fail",
                        f"Missing required field: {field}"
                    )
                    continue
                    
            # Validate provider configuration
            providers = config.get("providers", {})
            if "vllm-local" not in providers:
                self.add_result(
                    "CRUSH Providers",
                    "fail",
                    "Missing vllm-local provider configuration"
                )
            else:
                provider = providers["vllm-local"]
                self.validate_provider_config(provider)
                
            # Check for placeholder values
            if config.get("providers", {}).get("vllm-local", {}).get("api_key") == "YOUR_API_KEY_HERE":
                self.add_result(
                    "CRUSH API Key",
                    "warning",
                    "API key is still set to placeholder value"
                )
            else:
                self.add_result(
                    "CRUSH API Key",
                    "pass",
                    "API key has been configured"
                )
                
            self.add_result(
                "CRUSH Config File",
                "pass",
                "Configuration file is valid"
            )
            
        except json.JSONDecodeError as e:
            self.add_result(
                "CRUSH Config File",
                "fail",
                f"Invalid JSON format: {e}"
            )
        except Exception as e:
            self.add_result(
                "CRUSH Config File",
                "fail",
                f"Error reading config: {e}"
            )

    def validate_provider_config(self, provider: dict):
        """Validate individual provider configuration"""
        required_fields = ["type", "base_url", "api_key", "models"]
        
        for field in required_fields:
            if field not in provider:
                self.add_result(
                    f"Provider Config - {field}",
                    "fail",
                    f"Missing required field: {field}"
                )
                
        # Validate base_url format
        base_url = provider.get("base_url", "")
        if not base_url.startswith(("http://", "https://")):
            self.add_result(
                "Provider Base URL",
                "fail",
                f"Invalid base_url format: {base_url}"
            )
        elif "localhost:8000" in base_url:
            self.add_result(
                "Provider Base URL",
                "pass",
                "Base URL correctly configured for local vLLM"
            )
            
        # Validate models configuration
        models = provider.get("models", [])
        if not models:
            self.add_result(
                "Provider Models",
                "fail",
                "No models configured"
            )
        else:
            for model in models:
                self.validate_model_config(model)

    def validate_model_config(self, model: dict):
        """Validate individual model configuration"""
        required_fields = ["id", "name", "context_window"]
        
        for field in required_fields:
            if field not in model:
                self.add_result(
                    f"Model Config - {field}",
                    "fail",
                    f"Missing required field: {field}"
                )
                
        # Validate context window
        context_window = model.get("context_window", 0)
        if context_window >= 200000:
            self.add_result(
                "Model Context Window",
                "pass",
                f"Large context window configured: {context_window:,} tokens"
            )
        elif context_window > 0:
            self.add_result(
                "Model Context Window",
                "warning",
                f"Small context window: {context_window:,} tokens"
            )

    def validate_environment_template(self):
        """Validate environment template file"""
        env_path = self.config_dir / "configs" / "environment-template.sh"
        
        if not env_path.exists():
            self.add_result(
                "Environment Template",
                "fail",
                f"Environment template not found: {env_path}"
            )
            return
            
        try:
            with open(env_path) as f:
                content = f.read()
                
            # Check for required environment variables
            required_vars = [
                "VLLM_API_KEY",
                "MODEL_PATH", 
                "MAX_MODEL_LENGTH",
                "CUDA_VISIBLE_DEVICES",
                "SERVER_IP",
                "SSH_KEY"
            ]
            
            for var in required_vars:
                if f"export {var}=" in content:
                    self.add_result(
                        f"Environment Variable - {var}",
                        "pass",
                        f"Variable {var} is defined"
                    )
                else:
                    self.add_result(
                        f"Environment Variable - {var}",
                        "fail",
                        f"Missing environment variable: {var}"
                    )
                    
            # Check for placeholder values
            placeholders = [
                "YOUR_API_KEY_HERE",
                "YOUR_SSH_KEY", 
                "YOUR_SERVER_IP"
            ]
            
            placeholder_count = 0
            for placeholder in placeholders:
                if placeholder in content:
                    placeholder_count += 1
                    
            if placeholder_count > 0:
                self.add_result(
                    "Environment Placeholders",
                    "warning",
                    f"Found {placeholder_count} placeholder values that need to be replaced"
                )
            else:
                self.add_result(
                    "Environment Placeholders",
                    "pass",
                    "No placeholder values found"
                )
                
            # Validate GPU memory utilization
            if "GPU_MEMORY_UTILIZATION=0.95" in content:
                self.add_result(
                    "GPU Memory Utilization",
                    "pass",
                    "GPU memory utilization properly configured"
                )
                
            self.add_result(
                "Environment Template",
                "pass",
                "Environment template file is valid"
            )
            
        except Exception as e:
            self.add_result(
                "Environment Template",
                "fail",
                f"Error reading environment template: {e}"
            )

    def validate_claude_settings(self):
        """Validate Claude settings configuration"""
        claude_path = self.config_dir / ".claude" / "settings.local.json"
        
        if not claude_path.exists():
            self.add_result(
                "Claude Settings",
                "warning",
                f"Claude settings file not found: {claude_path}"
            )
            return
            
        try:
            with open(claude_path) as f:
                settings = json.load(f)
                
            # Validate permissions structure
            if "permissions" in settings:
                permissions = settings["permissions"]
                
                if "allow" in permissions and isinstance(permissions["allow"], list):
                    self.add_result(
                        "Claude Permissions - Allow",
                        "pass",
                        f"Found {len(permissions['allow'])} allowed permissions"
                    )
                    
                if "deny" in permissions and isinstance(permissions["deny"], list):
                    self.add_result(
                        "Claude Permissions - Deny",
                        "info",
                        f"Found {len(permissions['deny'])} denied permissions"
                    )
                    
                self.add_result(
                    "Claude Settings",
                    "pass",
                    "Claude settings file is valid"
                )
            else:
                self.add_result(
                    "Claude Settings",
                    "warning",
                    "Missing permissions configuration"
                )
                
        except json.JSONDecodeError as e:
            self.add_result(
                "Claude Settings",
                "fail",
                f"Invalid JSON format: {e}"
            )
        except Exception as e:
            self.add_result(
                "Claude Settings",
                "fail",
                f"Error reading Claude settings: {e}"
            )

    def validate_python_environment(self):
        """Validate Python environment and dependencies"""
        
        # Check Python version
        try:
            python_version = sys.version_info
            if python_version >= (3, 10):
                self.add_result(
                    "Python Version",
                    "pass",
                    f"Python {python_version.major}.{python_version.minor}.{python_version.micro}"
                )
            else:
                self.add_result(
                    "Python Version",
                    "warning",
                    f"Python version may be too old: {python_version.major}.{python_version.minor}"
                )
        except Exception as e:
            self.add_result(
                "Python Version",
                "fail",
                f"Could not determine Python version: {e}"
            )
            
        # Check for virtual environment
        if hasattr(sys, 'real_prefix') or (hasattr(sys, 'base_prefix') and sys.base_prefix != sys.prefix):
            self.add_result(
                "Virtual Environment",
                "pass",
                "Running in virtual environment"
            )
        else:
            self.add_result(
                "Virtual Environment", 
                "warning",
                "Not running in virtual environment"
            )
            
        # Check for key packages
        required_packages = [
            'requests',
            'openai'
        ]
        
        for package in required_packages:
            try:
                __import__(package)
                self.add_result(
                    f"Package - {package}",
                    "pass",
                    f"Package {package} is available"
                )
            except ImportError:
                self.add_result(
                    f"Package - {package}",
                    "warning",
                    f"Package {package} not found"
                )

    def validate_gpu_requirements(self):
        """Validate GPU requirements (if nvidia-smi is available)"""
        try:
            result = subprocess.run(['nvidia-smi', '--list-gpus'], 
                                 capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0:
                gpu_lines = result.stdout.strip().split('\n')
                gpu_count = len([line for line in gpu_lines if line.strip()])
                
                if gpu_count >= 4:
                    self.add_result(
                        "GPU Count",
                        "pass",
                        f"Found {gpu_count} GPUs (meets requirement of 4+)"
                    )
                else:
                    self.add_result(
                        "GPU Count",
                        "warning",
                        f"Found {gpu_count} GPUs (recommended: 4+)"
                    )
                    
                # Check GPU memory
                memory_result = subprocess.run([
                    'nvidia-smi', '--query-gpu=memory.total', 
                    '--format=csv,noheader,nounits'
                ], capture_output=True, text=True, timeout=10)
                
                if memory_result.returncode == 0:
                    memory_lines = memory_result.stdout.strip().split('\n')
                    total_memory = 0
                    for line in memory_lines:
                        if line.strip():
                            memory = int(line.strip())
                            total_memory += memory
                            
                    total_memory_gb = total_memory / 1024
                    
                    if total_memory_gb >= 500:  # 4x 125GB+ GPUs
                        self.add_result(
                            "GPU Memory",
                            "pass",
                            f"Total GPU memory: {total_memory_gb:.1f}GB"
                        )
                    else:
                        self.add_result(
                            "GPU Memory",
                            "warning",
                            f"Total GPU memory: {total_memory_gb:.1f}GB (recommended: 500GB+)"
                        )
                        
            else:
                self.add_result(
                    "GPU Detection",
                    "info",
                    "nvidia-smi not available or no GPUs found"
                )
                
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
            self.add_result(
                "GPU Detection",
                "info",
                "Could not check GPU status (nvidia-smi not available)"
            )

    def validate_network_configuration(self):
        """Validate network configuration and ports"""
        
        # Check if port 8000 is available or in use
        try:
            import socket
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(5)
            result = sock.connect_ex(('localhost', 8000))
            sock.close()
            
            if result == 0:
                self.add_result(
                    "vLLM Port (8000)",
                    "info",
                    "Port 8000 is in use (vLLM may be running)"
                )
            else:
                self.add_result(
                    "vLLM Port (8000)",
                    "pass",
                    "Port 8000 is available"
                )
                
        except Exception as e:
            self.add_result(
                "vLLM Port (8000)",
                "warning",
                f"Could not check port status: {e}"
            )
            
        # Check SSH connectivity (if SERVER_IP is configured)
        self.check_ssh_connectivity()

    def check_ssh_connectivity(self):
        """Check SSH connectivity to configured server"""
        try:
            env_path = self.config_dir / "configs" / "environment-template.sh"
            if not env_path.exists():
                return
                
            with open(env_path) as f:
                content = f.read()
                
            # Extract server IP (look for non-placeholder value)
            server_ip_match = re.search(r'export SERVER_IP="([^"]+)"', content)
            if server_ip_match:
                server_ip = server_ip_match.group(1)
                if server_ip != "YOUR_SERVER_IP":
                    # Try to ping the server
                    try:
                        result = subprocess.run(['ping', '-c', '1', '-W', '3', server_ip], 
                                             capture_output=True, timeout=10)
                        if result.returncode == 0:
                            self.add_result(
                                "Server Connectivity",
                                "pass",
                                f"Server {server_ip} is reachable"
                            )
                        else:
                            self.add_result(
                                "Server Connectivity",
                                "warning",
                                f"Server {server_ip} is not reachable"
                            )
                    except (subprocess.TimeoutExpired, FileNotFoundError):
                        self.add_result(
                            "Server Connectivity",
                            "info",
                            f"Could not check connectivity to {server_ip}"
                        )
                        
        except Exception as e:
            self.add_result(
                "Server Connectivity",
                "info",
                f"Could not check server connectivity: {e}"
            )

    def validate_scripts(self):
        """Validate script files"""
        scripts_dir = self.config_dir / "scripts"
        
        if not scripts_dir.exists():
            self.add_result(
                "Scripts Directory",
                "warning",
                f"Scripts directory not found: {scripts_dir}"
            )
            return
            
        # Check for key scripts
        key_scripts = [
            "experimental/start_700k_final.sh",
            "experimental/start_pipeline.sh", 
            "experimental/start_vllm_optimized.sh"
        ]
        
        script_count = 0
        for script_path in key_scripts:
            full_path = scripts_dir / script_path
            if full_path.exists():
                script_count += 1
                self.validate_script_file(full_path)
            else:
                self.add_result(
                    f"Script - {script_path}",
                    "warning",
                    f"Script not found: {script_path}"
                )
                
        if script_count > 0:
            self.add_result(
                "Scripts Directory",
                "pass",
                f"Found {script_count} key scripts"
            )

    def validate_script_file(self, script_path: Path):
        """Validate individual script file"""
        try:
            with open(script_path) as f:
                content = f.read()
                
            # Check for executable permission
            if os.access(script_path, os.X_OK):
                self.add_result(
                    f"Script Permissions - {script_path.name}",
                    "pass",
                    "Script is executable"
                )
            else:
                self.add_result(
                    f"Script Permissions - {script_path.name}",
                    "warning",
                    "Script is not executable"
                )
                
            # Check for API key placeholder
            if "YOUR_API_KEY_HERE" in content:
                self.add_result(
                    f"Script API Key - {script_path.name}",
                    "warning",
                    "Script contains API key placeholder"
                )
                
            # Check for vLLM serve command
            if "vllm serve" in content:
                self.add_result(
                    f"Script Content - {script_path.name}",
                    "pass",
                    "Script contains vLLM serve command"
                )
                
        except Exception as e:
            self.add_result(
                f"Script - {script_path.name}",
                "fail",
                f"Error reading script: {e}"
            )

    def validate_api_connectivity(self):
        """Test API connectivity"""
        try:
            import requests
            
            # Test local vLLM endpoint
            try:
                response = requests.get("http://localhost:8000/health", timeout=5)
                if response.status_code == 200:
                    self.add_result(
                        "vLLM API Health",
                        "pass",
                        "vLLM API is responding"
                    )
                else:
                    self.add_result(
                        "vLLM API Health",
                        "warning",
                        f"vLLM API returned status {response.status_code}"
                    )
            except requests.ConnectionError:
                self.add_result(
                    "vLLM API Health",
                    "info",
                    "vLLM API is not running (connection refused)"
                )
            except requests.Timeout:
                self.add_result(
                    "vLLM API Health",
                    "warning",
                    "vLLM API timeout (may be starting up)"
                )
                
            # Test models endpoint
            try:
                response = requests.get("http://localhost:8000/v1/models", timeout=5)
                if response.status_code == 200:
                    models = response.json()
                    model_count = len(models.get('data', []))
                    self.add_result(
                        "vLLM Models Endpoint",
                        "pass",
                        f"Found {model_count} available models"
                    )
                else:
                    self.add_result(
                        "vLLM Models Endpoint",
                        "info",
                        f"Models endpoint returned status {response.status_code}"
                    )
            except (requests.ConnectionError, requests.Timeout):
                self.add_result(
                    "vLLM Models Endpoint",
                    "info",
                    "Models endpoint not accessible"
                )
                
        except ImportError:
            self.add_result(
                "API Testing",
                "warning",
                "requests package not available for API testing"
            )

    def validate_ssh_configuration(self):
        """Validate SSH configuration"""
        
        # Check for SSH key existence
        ssh_dir = Path.home() / ".ssh"
        if ssh_dir.exists():
            key_files = list(ssh_dir.glob("id_*"))
            key_files.extend(ssh_dir.glob("*_rsa"))
            key_files.extend(ssh_dir.glob("*_ed25519"))
            
            if key_files:
                self.add_result(
                    "SSH Keys",
                    "pass",
                    f"Found {len(key_files)} SSH key files"
                )
            else:
                self.add_result(
                    "SSH Keys",
                    "warning",
                    "No SSH key files found in ~/.ssh"
                )
        else:
            self.add_result(
                "SSH Directory",
                "warning",
                "SSH directory ~/.ssh not found"
            )
            
        # Check SSH config
        ssh_config = Path.home() / ".ssh" / "config"
        if ssh_config.exists():
            self.add_result(
                "SSH Config",
                "pass",
                "SSH config file exists"
            )
        else:
            self.add_result(
                "SSH Config", 
                "info",
                "SSH config file not found (optional)"
            )

    def generate_report(self) -> str:
        """Generate a comprehensive validation report"""
        
        # Count results by status
        status_counts = {"pass": 0, "fail": 0, "warning": 0, "info": 0}
        for result in self.results:
            status_counts[result.status] += 1
            
        # Generate report
        report = f"""
# Configuration Validation Report

**Generated:** {subprocess.check_output(['date'], text=True).strip()}
**Total Checks:** {len(self.results)}

## Summary
- ✅ **Passed:** {status_counts['pass']}
- ❌ **Failed:** {status_counts['fail']} 
- ⚠️  **Warnings:** {status_counts['warning']}
- ℹ️  **Info:** {status_counts['info']}

## Detailed Results

"""
        
        # Group results by category
        categories = {}
        for result in self.results:
            category = result.name.split(' - ')[0] if ' - ' in result.name else result.name.split(' ')[0]
            if category not in categories:
                categories[category] = []
            categories[category].append(result)
            
        for category, results in sorted(categories.items()):
            report += f"### {category}\n\n"
            
            for result in results:
                icon = {"pass": "✅", "fail": "❌", "warning": "⚠️", "info": "ℹ️"}[result.status]
                report += f"- {icon} **{result.name}:** {result.message}\n"
                if result.details:
                    report += f"  - *Details:* {result.details}\n"
                    
            report += "\n"
            
        # Add recommendations section
        fail_count = status_counts['fail']
        warning_count = status_counts['warning']
        
        report += "## Recommendations\n\n"
        
        if fail_count == 0 and warning_count == 0:
            report += "🎉 **Excellent!** All checks passed. Your configuration appears to be ready for deployment.\n"
        elif fail_count == 0:
            report += f"✨ **Good!** No critical issues found. Please review the {warning_count} warnings above.\n"
        else:
            report += f"🔧 **Action Required:** Please address the {fail_count} failed checks before proceeding.\n"
            
        if warning_count > 0:
            report += f"📝 **Note:** The {warning_count} warnings should be reviewed but may not prevent operation.\n"
            
        report += "\n## Next Steps\n\n"
        
        if fail_count == 0:
            report += """1. **Update Placeholders:** Replace any remaining placeholder values in configuration files
2. **Test SSH Connection:** Verify SSH connectivity to your GPU server
3. **Start vLLM Server:** Use the provided scripts to start the vLLM server
4. **Test API Endpoints:** Verify API connectivity and model availability
5. **Configure CRUSH:** Set up CRUSH with the validated configuration
"""
        else:
            report += """1. **Fix Critical Issues:** Address all failed checks first
2. **Re-run Validation:** Run this validator again after fixes
3. **Proceed with Setup:** Continue with next steps once validation passes
"""
            
        return report

def main():
    parser = argparse.ArgumentParser(description="Validate vLLM + CRUSH configuration")
    parser.add_argument("--config-dir", help="Configuration directory path")
    parser.add_argument("--output", help="Output report file", default="validation-report.md")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose logging")
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
        
    validator = ConfigValidator(args.config_dir)
    results = validator.validate_all()
    
    # Generate and save report
    report = validator.generate_report()
    
    with open(args.output, 'w') as f:
        f.write(report)
        
    print(f"\n📋 Validation complete! Report saved to: {args.output}")
    
    # Print summary
    status_counts = {"pass": 0, "fail": 0, "warning": 0, "info": 0}
    for result in results:
        status_counts[result.status] += 1
        
    print(f"📊 Summary: {status_counts['pass']} passed, {status_counts['fail']} failed, {status_counts['warning']} warnings")
    
    # Exit with appropriate code
    if status_counts['fail'] > 0:
        sys.exit(1)
    elif status_counts['warning'] > 0:
        sys.exit(2)
    else:
        sys.exit(0)

if __name__ == "__main__":
    main()