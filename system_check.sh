#!/bin/bash

echo "=== Python Environment Check ==="
source /opt/vllm/bin/activate

echo "Python packages related to vLLM and ML:"
pip list | grep -E "vllm|torch|transformers|numpy|cuda|flash|triton|xformers" | sort

echo -e "\n=== vLLM Installation Details ==="
python -c "
import vllm
import os
print(f'vLLM version: {vllm.__version__}')
print(f'vLLM location: {vllm.__file__}')
print(f'vLLM install dir: {os.path.dirname(vllm.__file__)}')
"

echo -e "\n=== Model Details ==="
echo "Model directory contents:"
ls -lah /models/qwen3/ | head -20

echo -e "\nModel size:"
du -sh /models/qwen3/

echo -e "\nModel config.json:"
cat /models/qwen3/config.json | python -m json.tool | head -30

echo -e "\n=== System Libraries ==="
echo "CUDA libraries:"
ldconfig -p | grep cuda | head -10

echo -e "\nNCCL version:"
python -c "import torch; print(f'NCCL version: {torch.cuda.nccl.version()}')"

echo -e "\n=== GPU Details ==="
python -c "
import torch
for i in range(torch.cuda.device_count()):
    props = torch.cuda.get_device_properties(i)
    print(f'GPU {i}: {props.name}')
    print(f'  Memory: {props.total_memory / 1024**3:.1f} GB')
    print(f'  Compute Capability: {props.major}.{props.minor}')
"

echo -e "\n=== vLLM Configuration Check ==="
python -c "
try:
    from vllm.config import ModelConfig
    print('vLLM ModelConfig available')
except:
    print('vLLM ModelConfig import failed')

try:
    from vllm import LLM
    print('vLLM LLM class available')
except Exception as e:
    print(f'vLLM LLM import failed: {e}')
"

echo -e "\n=== Recent Command History ==="
history | tail -20 | grep -E "vllm|start|./.*\.sh"

echo -e "\n=== Check for any running Python processes ==="
ps aux | grep python | grep -v grep

echo -e "\n=== Available vLLM scripts ==="
ls -la /root/*.sh | grep -E "start|vllm"
