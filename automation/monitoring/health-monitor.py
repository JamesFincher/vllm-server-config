#!/usr/bin/env python3
"""
Comprehensive Health Monitoring System for vLLM Server
Monitors API health, GPU utilization, system resources, and performance metrics
"""

import os
import sys
import json
import time
import logging
import requests
import psutil
import subprocess
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Any
import configparser

try:
    import pynvml
    NVIDIA_AVAILABLE = True
except ImportError:
    NVIDIA_AVAILABLE = False

class VLLMHealthMonitor:
    def __init__(self, config_file: str = "/etc/vllm/monitoring/monitor.conf"):
        self.config_file = config_file
        self.config = self.load_config()
        self.setup_logging()
        self.setup_nvidia()
        
        # Monitoring state
        self.last_checks = {}
        self.alert_counts = {}
        self.performance_history = []
        
    def load_config(self) -> Dict[str, Any]:
        """Load monitoring configuration"""
        config = {
            'MONITORING_ROOT': '/opt/vllm-monitoring',
            'API_ENDPOINT': 'http://localhost:8000',
            'API_KEY': '',
            'HEALTH_CHECK_INTERVAL': 30,
            'PERFORMANCE_CHECK_INTERVAL': 60,
            'GPU_CHECK_INTERVAL': 30,
            'SYSTEM_CHECK_INTERVAL': 60,
            'GPU_MEMORY_THRESHOLD': 95,
            'GPU_TEMP_THRESHOLD': 85,
            'CPU_THRESHOLD': 90,
            'MEMORY_THRESHOLD': 90,
            'DISK_THRESHOLD': 85,
            'API_RESPONSE_THRESHOLD': 5.0,
            'GENERATION_TIME_THRESHOLD': 30.0,
            'LOG_LEVEL': 'INFO',
            'ENABLE_SLACK_ALERTS': False,
            'ENABLE_EMAIL_ALERTS': False,
        }
        
        if os.path.exists(self.config_file):
            with open(self.config_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        key, value = line.split('=', 1)
                        key = key.strip()
                        value = value.strip().strip('"')
                        
                        # Convert to appropriate type
                        if value.lower() in ('true', 'false'):
                            config[key] = value.lower() == 'true'
                        elif value.isdigit():
                            config[key] = int(value)
                        elif '.' in value and value.replace('.', '').isdigit():
                            config[key] = float(value)
                        else:
                            config[key] = value
        
        return config
    
    def setup_logging(self):
        """Setup logging configuration"""
        log_dir = Path(self.config['MONITORING_ROOT']) / 'logs'
        log_dir.mkdir(parents=True, exist_ok=True)
        
        log_file = log_dir / f"health-monitor-{datetime.now().strftime('%Y-%m-%d')}.log"
        
        logging.basicConfig(
            level=getattr(logging, self.config['LOG_LEVEL']),
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler(sys.stdout)
            ]
        )
        
        self.logger = logging.getLogger(__name__)
    
    def setup_nvidia(self):
        """Initialize NVIDIA monitoring"""
        if NVIDIA_AVAILABLE:
            try:
                pynvml.nvmlInit()
                self.gpu_count = pynvml.nvmlDeviceGetCount()
                self.logger.info(f"Initialized NVIDIA monitoring for {self.gpu_count} GPUs")
            except Exception as e:
                self.logger.error(f"Failed to initialize NVIDIA monitoring: {e}")
                self.gpu_count = 0
        else:
            self.logger.warning("NVIDIA monitoring not available (pynvml not installed)")
            self.gpu_count = 0
    
    def check_api_health(self) -> Dict[str, Any]:
        """Check vLLM API health and response time"""
        try:
            start_time = time.time()
            
            # Check /health endpoint
            health_url = f"{self.config['API_ENDPOINT']}/health"
            response = requests.get(health_url, timeout=10)
            health_response_time = time.time() - start_time
            
            health_status = response.status_code == 200
            
            # Check /models endpoint
            start_time = time.time()
            models_url = f"{self.config['API_ENDPOINT']}/v1/models"
            headers = {"Authorization": f"Bearer {self.config['API_KEY']}"}
            response = requests.get(models_url, headers=headers, timeout=10)
            models_response_time = time.time() - start_time
            
            models_status = response.status_code == 200
            
            # Test generation
            generation_time = self.test_generation()
            
            result = {
                'timestamp': datetime.now().isoformat(),
                'health_endpoint': {
                    'status': health_status,
                    'response_time': health_response_time
                },
                'models_endpoint': {
                    'status': models_status,
                    'response_time': models_response_time
                },
                'generation_test': {
                    'status': generation_time is not None,
                    'response_time': generation_time
                },
                'overall_status': health_status and models_status and generation_time is not None
            }
            
            # Check thresholds
            if health_response_time > self.config['API_RESPONSE_THRESHOLD']:
                self.send_alert("API Response Time High", f"Health endpoint response time: {health_response_time:.2f}s")
            
            if generation_time and generation_time > self.config['GENERATION_TIME_THRESHOLD']:
                self.send_alert("Generation Time High", f"Generation response time: {generation_time:.2f}s")
            
            return result
            
        except Exception as e:
            self.logger.error(f"API health check failed: {e}")
            return {
                'timestamp': datetime.now().isoformat(),
                'error': str(e),
                'overall_status': False
            }
    
    def test_generation(self) -> Optional[float]:
        """Test API generation with a simple prompt"""
        try:
            start_time = time.time()
            
            url = f"{self.config['API_ENDPOINT']}/v1/chat/completions"
            headers = {
                "Authorization": f"Bearer {self.config['API_KEY']}",
                "Content-Type": "application/json"
            }
            data = {
                "model": "qwen3",
                "messages": [{"role": "user", "content": "Say 'OK' if you're working."}],
                "max_tokens": 5,
                "temperature": 0.1
            }
            
            response = requests.post(url, headers=headers, json=data, timeout=30)
            generation_time = time.time() - start_time
            
            if response.status_code == 200:
                return generation_time
            else:
                self.logger.error(f"Generation test failed: {response.status_code}")
                return None
                
        except Exception as e:
            self.logger.error(f"Generation test failed: {e}")
            return None
    
    def check_gpu_status(self) -> Dict[str, Any]:
        """Check GPU utilization, memory, and temperature"""
        if not NVIDIA_AVAILABLE or self.gpu_count == 0:
            return {'available': False, 'message': 'NVIDIA monitoring not available'}
        
        try:
            gpu_data = []
            
            for i in range(self.gpu_count):
                handle = pynvml.nvmlDeviceGetHandleByIndex(i)
                
                # Get basic info
                name = pynvml.nvmlDeviceGetName(handle).decode('utf-8')
                
                # Memory info
                mem_info = pynvml.nvmlDeviceGetMemoryInfo(handle)
                memory_used_percent = (mem_info.used / mem_info.total) * 100
                
                # Temperature
                temp = pynvml.nvmlDeviceGetTemperature(handle, pynvml.NVML_TEMPERATURE_GPU)
                
                # Utilization
                util = pynvml.nvmlDeviceGetUtilizationRates(handle)
                
                # Power usage
                try:
                    power = pynvml.nvmlDeviceGetPowerUsage(handle) / 1000.0  # Convert to watts
                except:
                    power = None
                
                gpu_info = {
                    'index': i,
                    'name': name,
                    'memory': {
                        'used': mem_info.used,
                        'total': mem_info.total,
                        'used_percent': memory_used_percent
                    },
                    'temperature': temp,
                    'utilization': {
                        'gpu': util.gpu,
                        'memory': util.memory
                    },
                    'power_usage': power
                }
                
                gpu_data.append(gpu_info)
                
                # Check thresholds
                if memory_used_percent > self.config['GPU_MEMORY_THRESHOLD']:
                    self.send_alert("GPU Memory High", f"GPU {i} memory usage: {memory_used_percent:.1f}%")
                
                if temp > self.config['GPU_TEMP_THRESHOLD']:
                    self.send_alert("GPU Temperature High", f"GPU {i} temperature: {temp}°C")
            
            return {
                'timestamp': datetime.now().isoformat(),
                'available': True,
                'gpu_count': self.gpu_count,
                'gpus': gpu_data
            }
            
        except Exception as e:
            self.logger.error(f"GPU status check failed: {e}")
            return {'available': True, 'error': str(e)}
    
    def check_system_resources(self) -> Dict[str, Any]:
        """Check CPU, memory, and disk usage"""
        try:
            # CPU usage
            cpu_percent = psutil.cpu_percent(interval=1)
            cpu_count = psutil.cpu_count()
            
            # Memory usage
            memory = psutil.virtual_memory()
            
            # Disk usage
            disk = psutil.disk_usage('/')
            disk_percent = (disk.used / disk.total) * 100
            
            # Network statistics
            network = psutil.net_io_counters()
            
            # Process count
            process_count = len(psutil.pids())
            
            # Load average (Linux/Unix only)
            try:
                load_avg = os.getloadavg()
            except (OSError, AttributeError):
                load_avg = None
            
            result = {
                'timestamp': datetime.now().isoformat(),
                'cpu': {
                    'usage_percent': cpu_percent,
                    'count': cpu_count,
                    'load_average': load_avg
                },
                'memory': {
                    'total': memory.total,
                    'used': memory.used,
                    'available': memory.available,
                    'used_percent': memory.percent
                },
                'disk': {
                    'total': disk.total,
                    'used': disk.used,
                    'free': disk.free,
                    'used_percent': disk_percent
                },
                'network': {
                    'bytes_sent': network.bytes_sent,
                    'bytes_recv': network.bytes_recv,
                    'packets_sent': network.packets_sent,
                    'packets_recv': network.packets_recv
                },
                'processes': process_count
            }
            
            # Check thresholds
            if cpu_percent > self.config['CPU_THRESHOLD']:
                self.send_alert("CPU Usage High", f"CPU usage: {cpu_percent:.1f}%")
            
            if memory.percent > self.config['MEMORY_THRESHOLD']:
                self.send_alert("Memory Usage High", f"Memory usage: {memory.percent:.1f}%")
            
            if disk_percent > self.config['DISK_THRESHOLD']:
                self.send_alert("Disk Usage High", f"Disk usage: {disk_percent:.1f}%")
            
            return result
            
        except Exception as e:
            self.logger.error(f"System resource check failed: {e}")
            return {'error': str(e)}
    
    def check_vllm_processes(self) -> Dict[str, Any]:
        """Check vLLM process status and resource usage"""
        try:
            vllm_processes = []
            
            for proc in psutil.process_iter(['pid', 'name', 'cmdline', 'cpu_percent', 'memory_percent', 'status']):
                try:
                    if 'vllm' in proc.info['name'].lower() or any('vllm' in arg.lower() for arg in proc.info['cmdline']):
                        vllm_processes.append({
                            'pid': proc.info['pid'],
                            'name': proc.info['name'],
                            'cpu_percent': proc.info['cpu_percent'],
                            'memory_percent': proc.info['memory_percent'],
                            'status': proc.info['status']
                        })
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue
            
            return {
                'timestamp': datetime.now().isoformat(),
                'process_count': len(vllm_processes),
                'processes': vllm_processes
            }
            
        except Exception as e:
            self.logger.error(f"vLLM process check failed: {e}")
            return {'error': str(e)}
    
    def send_alert(self, title: str, message: str):
        """Send alert notification"""
        alert_key = f"{title}:{message}"
        current_time = time.time()
        
        # Rate limiting: don't send same alert more than once per hour
        if alert_key in self.alert_counts:
            if current_time - self.alert_counts[alert_key] < 3600:
                return
        
        self.alert_counts[alert_key] = current_time
        
        self.logger.warning(f"ALERT: {title} - {message}")
        
        # Slack notification
        if self.config.get('ENABLE_SLACK_ALERTS') and self.config.get('SLACK_WEBHOOK'):
            try:
                payload = {
                    "text": f"🚨 vLLM Alert: {title}",
                    "attachments": [{
                        "color": "danger",
                        "fields": [{
                            "title": "Details",
                            "value": message,
                            "short": False
                        }]
                    }]
                }
                requests.post(self.config['SLACK_WEBHOOK'], json=payload, timeout=10)
            except Exception as e:
                self.logger.error(f"Failed to send Slack alert: {e}")
        
        # Email notification (requires system mail configuration)
        if self.config.get('ENABLE_EMAIL_ALERTS') and self.config.get('EMAIL_RECIPIENTS'):
            try:
                subject = f"vLLM Alert: {title}"
                body = f"Alert: {title}\nDetails: {message}\nTime: {datetime.now()}"
                subprocess.run([
                    'mail', '-s', subject, self.config['EMAIL_RECIPIENTS']
                ], input=body, text=True, timeout=30)
            except Exception as e:
                self.logger.error(f"Failed to send email alert: {e}")
    
    def save_metrics(self, metrics: Dict[str, Any]):
        """Save metrics to file for later analysis"""
        metrics_dir = Path(self.config['MONITORING_ROOT']) / 'data'
        metrics_dir.mkdir(parents=True, exist_ok=True)
        
        date_str = datetime.now().strftime('%Y-%m-%d')
        metrics_file = metrics_dir / f"metrics-{date_str}.jsonl"
        
        try:
            with open(metrics_file, 'a') as f:
                json.dump(metrics, f)
                f.write('\n')
        except Exception as e:
            self.logger.error(f"Failed to save metrics: {e}")
    
    def run_health_check(self):
        """Run comprehensive health check"""
        self.logger.info("Starting health check cycle")
        
        # Collect all metrics
        metrics = {
            'timestamp': datetime.now().isoformat(),
            'api_health': self.check_api_health(),
            'gpu_status': self.check_gpu_status(),
            'system_resources': self.check_system_resources(),
            'vllm_processes': self.check_vllm_processes()
        }
        
        # Save metrics
        self.save_metrics(metrics)
        
        # Log summary
        api_status = metrics['api_health'].get('overall_status', False)
        gpu_available = metrics['gpu_status'].get('available', False)
        
        self.logger.info(f"Health check complete - API: {'OK' if api_status else 'FAIL'}, "
                        f"GPUs: {'OK' if gpu_available else 'N/A'}")
        
        return metrics
    
    def run_monitoring_loop(self):
        """Main monitoring loop"""
        self.logger.info("Starting vLLM health monitoring")
        
        try:
            while True:
                self.run_health_check()
                time.sleep(self.config['HEALTH_CHECK_INTERVAL'])
                
        except KeyboardInterrupt:
            self.logger.info("Monitoring stopped by user")
        except Exception as e:
            self.logger.error(f"Monitoring loop failed: {e}")
            raise

def main():
    """Main entry point"""
    if len(sys.argv) > 1 and sys.argv[1] in ['-h', '--help']:
        print("vLLM Health Monitor")
        print("Usage: python3 health-monitor.py [config_file]")
        print("Default config: /etc/vllm/monitoring/monitor.conf")
        return
    
    config_file = sys.argv[1] if len(sys.argv) > 1 else "/etc/vllm/monitoring/monitor.conf"
    
    monitor = VLLMHealthMonitor(config_file)
    
    if len(sys.argv) > 1 and sys.argv[1] == '--check-once':
        # Run single health check
        metrics = monitor.run_health_check()
        print(json.dumps(metrics, indent=2))
    else:
        # Run continuous monitoring
        monitor.run_monitoring_loop()

if __name__ == "__main__":
    main()