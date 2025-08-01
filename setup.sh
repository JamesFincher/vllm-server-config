#!/bin/bash
# Complete Server Setup Script for vLLM with Qwen3-480B
# Based on tested configuration from production deployment
#
# This script will:
# 1. Install system dependencies
# 2. Set up NVIDIA drivers and CUDA
# 3. Create Python virtual environment
# 4. Install vLLM and dependencies
# 5. Download the Qwen3 model
# 6. Configure system settings for optimal performance

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VLLM_ENV_PATH="/opt/vllm"
MODEL_PATH="/models/qwen3"
PYTHON_VERSION="3.10"
VLLM_VERSION="0.10.0"
TORCH_VERSION="2.7.1+cu126"

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

check_hardware() {
    log "Checking hardware requirements..."
    
    # Check GPU count
    GPU_COUNT=$(nvidia-smi --list-gpus 2>/dev/null | wc -l || echo "0")
    if [[ $GPU_COUNT -lt 4 ]]; then
        error "At least 4 GPUs required. Found: $GPU_COUNT"
    fi
    
    # Check GPU memory
    MIN_GPU_MEMORY=140000  # 140GB in MB
    while IFS= read -r line; do
        MEMORY=$(echo "$line" | grep -oP '\d+(?= MiB)')
        if [[ $MEMORY -lt $MIN_GPU_MEMORY ]]; then
            error "GPU memory insufficient. Need 140GB+, found: ${MEMORY}MB"
        fi
    done < <(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)
    
    # Check system RAM
    TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $TOTAL_RAM_GB -lt 500 ]]; then
        error "Insufficient system RAM. Need 500GB+, found: ${TOTAL_RAM_GB}GB"
    fi
    
    success "Hardware requirements met"
}

install_system_packages() {
    log "Installing system packages..."
    
    apt-get update
    apt-get install -y \
        python3-pip \
        python3-dev \
        python3-venv \
        build-essential \
        git \
        wget \
        curl \
        vim \
        screen \
        htop \
        nvtop \
        software-properties-common
    
    success "System packages installed"
}

setup_nvidia_drivers() {
    log "Setting up NVIDIA drivers and CUDA..."
    
    # Check if drivers are already installed
    if nvidia-smi >/dev/null 2>&1; then
        DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -1)
        log "NVIDIA drivers already installed (version: $DRIVER_VERSION)"
    else
        warning "NVIDIA drivers not found. Installing..."
        
        # Add NVIDIA repository
        wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
        dpkg -i cuda-keyring_1.1-1_all.deb
        apt-get update
        
        # Install CUDA toolkit
        apt-get install -y cuda-toolkit-12-8
        
        # Set PATH
        echo 'export PATH=/usr/local/cuda/bin:$PATH' >> /etc/environment
        echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> /etc/environment
        
        log "NVIDIA drivers installed. Please reboot and run this script again."
        exit 0
    fi
    
    # Set GPU persistence mode
    nvidia-smi -pm 1
    
    success "NVIDIA setup complete"
}

configure_system() {
    log "Configuring system settings..."
    
    # Disable swap for better performance
    swapoff -a
    sed -i '/ swap / s/^/#/' /etc/fstab
    
    # Increase file descriptor limits
    echo '* soft nofile 65535' >> /etc/security/limits.conf
    echo '* hard nofile 65535' >> /etc/security/limits.conf
    
    # Set kernel parameters for better networking
    cat >> /etc/sysctl.conf << EOF

# Optimizations for vLLM
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
EOF
    
    sysctl -p
    
    success "System configuration complete"
}

setup_python_environment() {
    log "Setting up Python environment..."
    
    # Create vLLM directory
    mkdir -p $(dirname $VLLM_ENV_PATH)
    
    # Create virtual environment
    python3 -m venv $VLLM_ENV_PATH
    source $VLLM_ENV_PATH/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip
    
    success "Python environment created at $VLLM_ENV_PATH"
}

install_vllm() {
    log "Installing vLLM and dependencies..."
    
    source $VLLM_ENV_PATH/bin/activate
    
    # Install PyTorch with CUDA support
    pip install torch==$TORCH_VERSION --index-url https://download.pytorch.org/whl/cu126
    
    # Install vLLM
    pip install vllm==$VLLM_VERSION
    
    # Install additional dependencies
    pip install huggingface-hub[hf_transfer]
    
    # Verify installation
    python -c "import vllm; print(f'vLLM version: {vllm.__version__}')"
    python -c "import torch; print(f'PyTorch version: {torch.__version__}')"
    python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"
    
    success "vLLM installation complete"
}

download_model() {
    log "Setting up model download..."
    
    mkdir -p $MODEL_PATH
    
    # Check if model already exists
    if [[ -f "$MODEL_PATH/config.json" ]]; then
        log "Model already exists at $MODEL_PATH"
        return 0
    fi
    
    source $VLLM_ENV_PATH/bin/activate
    
    cat > /tmp/download_model.py << 'EOF'
import os
from huggingface_hub import snapshot_download

model_id = "Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8"
local_dir = "/models/qwen3"

print(f"Downloading {model_id} to {local_dir}")
print("This will download approximately 450GB and may take several hours...")

snapshot_download(
    repo_id=model_id,
    local_dir=local_dir,
    local_dir_use_symlinks=False,
    resume_download=True
)

print("Download complete!")
EOF
    
    echo ""
    echo "=== Model Download ==="
    echo "The Qwen3-480B model is approximately 450GB and will take several hours to download."
    echo "You can run the download now or later using:"
    echo "  source $VLLM_ENV_PATH/bin/activate"
    echo "  python /tmp/download_model.py"
    echo ""
    read -p "Download model now? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        python /tmp/download_model.py
        success "Model download complete"
    else
        log "Model download skipped. Run the download script when ready."
    fi
}

create_service_files() {
    log "Creating systemd service file..."
    
    cat > /etc/systemd/system/vllm-server.service << EOF
[Unit]
Description=vLLM Server for Qwen3-480B
After=network.target

[Service]
Type=forking
User=root
WorkingDirectory=/root
Environment=CUDA_VISIBLE_DEVICES=0,1,2,3
Environment=VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
ExecStart=/bin/bash -c 'source $VLLM_ENV_PATH/bin/activate && screen -dmS vllm_server vllm serve /models/qwen3 --tensor-parallel-size 2 --pipeline-parallel-size 2 --max-model-len 700000 --kv-cache-dtype fp8 --host 0.0.0.0 --port 8000 --gpu-memory-utilization 0.98 --trust-remote-code'
ExecStop=/usr/bin/pkill -f vllm
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    
    success "Systemd service created (use 'systemctl start vllm-server' to start)"
}

main() {
    echo "=== vLLM Server Setup Script ==="
    echo "This script will set up a complete vLLM environment for Qwen3-480B"
    echo ""
    
    check_root
    check_hardware
    install_system_packages
    setup_nvidia_drivers
    configure_system
    setup_python_environment
    install_vllm
    download_model
    create_service_files
    
    echo ""
    success "Setup complete!"
    echo ""
    echo "Next steps:"
    echo "1. Set your API key: export VLLM_API_KEY='your-api-key'"
    echo "2. Start the server: ./scripts/production/start-vllm-server.sh"
    echo "3. Or use systemd: systemctl start vllm-server"
    echo ""
    echo "Server will be available at: http://localhost:8000"
    echo "Monitor with: tail -f /var/log/vllm/vllm-*.log"
}

# Run main function
main "$@"