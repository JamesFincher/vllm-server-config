omprehensive vLLM Debug and Start Script
# This will diagnose issues and try multiple approaches

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== vLLM Comprehensive Debug & Start Script ===${NC}"
echo "Time is money - let's fix this quickly!"
echo ""

# Function to print section headers
section() {
	    echo ""
	        echo -e "${YELLOW}>>> $1${NC}"
		    echo "----------------------------------------"
	    }

	    # Function to check command success
	    check_status() {
		        if [ $? -eq 0 ]; then
				        echo -e "${GREEN}✓ Success${NC}"
					    else
						            echo -e "${RED}✗ Failed${NC}"
							            return 1
								        fi
								}

								# 1. SYSTEM CHECKS
								section "1. SYSTEM CHECKS"

								echo "Checking Python environment..."
								if [ -f /opt/vllm/bin/activate ]; then
									    source /opt/vllm/bin/activate
									        echo -e "${GREEN}✓ vLLM environment activated${NC}"
										    which python
										        python --version
										else
											    echo -e "${RED}✗ vLLM environment not found!${NC}"
											        exit 1
								fi

								echo ""
								echo "Checking vLLM installation..."
								vllm --version 2>/dev/null && echo -e "${GREEN}✓ vLLM installed${NC}" || echo -e "${RED}✗ vLLM not found${NC}"

								echo ""
								echo "Checking GPU status..."
								nvidia-smi --query-gpu=index,name,memory.total,memory.free --format=csv,noheader,nounits
								echo ""
								nvidia-smi topo -m

								# 2. MODEL CHECKS
								section "2. MODEL CHECKS"

								MODEL_PATH="/models/qwen3"
								echo "Checking model at: $MODEL_PATH"
								if [ -d "$MODEL_PATH" ]; then
									    echo -e "${GREEN}✓ Model directory exists${NC}"
									        echo "Model size: $(du -sh $MODEL_PATH | cut -f1)"
										    echo "Config file:"
										        cat $MODEL_PATH/config.json | jq '.model_type, .num_hidden_layers, .hidden_size' 2>/dev/null || echo "Could not parse config"
										else
											    echo -e "${RED}✗ Model directory not found!${NC}"
											        echo "Available models:"
												    ls -la /models/ 2>/dev/null || echo "No /models directory"
												        exit 1
								fi

								# 3. CLEANUP
								section "3. CLEANUP OLD PROCESSES"

								echo "Killing any existing vLLM processes..."
								pkill -f vllm || true
								screen -ls | grep vllm | cut -d. -f1 | awk '{print $1}' | xargs -I {} screen -S {}.vllm -X quit 2>/dev/null || true
								sleep 2
								echo -e "${GREEN}✓ Cleanup complete${NC}"

								# 4. TEST BASIC VLLM FUNCTIONALITY
								section "4. TEST VLLM COMMAND SYNTAX"

								echo "Testing vLLM command syntax..."
								echo "Checking available options:"
								vllm serve --help | grep -E "(model|tensor-parallel|max-model-len)" | head -10

								# 5. CREATE MULTIPLE START SCRIPTS
								section "5. CREATING START SCRIPTS"

								# Script 1: Basic start (minimal options)
								cat > /root/start_basic.sh << 'EOF'
								#!/bin/bash
								source /opt/vllm/bin/activate
								export VLLM_API_KEY='YOUR_API_KEY_HERE'

								echo "Starting vLLM with minimal options..."
								vllm serve /models/qwen3 \
									    --host 0.0.0.0 \
									        --port 8000 \
										    --api-key $VLLM_API_KEY \
										        2>&1 | tee /root/vllm_basic.log
								EOF

								# Script 2: Tensor Parallel (most likely to work)
								cat > /root/start_tensor_parallel.sh << 'EOF'
#!/bin/bash
source /opt/vllm/bin/activate
export VLLM_API_KEY='YOUR_API_KEY_HERE'
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3

echo "Starting vLLM with tensor parallelism..."
vllm serve /models/qwen3 \
	    --tensor-parallel-size 4 \
	        --host 0.0.0.0 \
		    --port 8000 \
		        --api-key $VLLM_API_KEY \
			    --trust-remote-code \
			        2>&1 | tee /root/vllm_tensor.log
EOF

# Script 3: Optimized with FP16 KV cache (nisten's config)
cat > /root/start_optimized.sh << 'EOF'
#!/bin/bash
source /opt/vllm/bin/activate
export VLLM_API_KEY='YOUR_API_KEY_HERE'
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
export CUDA_VISIBLE_DEVICES=0,1,2,3
export VLLM_FP8_E4M3_KV_CACHE=0
export VLLM_FP8_KV_CACHE=0

echo "Starting vLLM with optimized settings (FP16 KV cache)..."
vllm serve /models/qwen3 \
	    --tensor-parallel-size 4 \
	        --max-model-len 760000 \
		    --kv-cache-dtype fp16 \
		        --host 0.0.0.0 \
			    --port 8000 \
			        --api-key $VLLM_API_KEY \
    --gpu-memory-utilization 0.90 \
    --trust-remote-code \
    2>&1 | tee /root/vllm_optimized.log
EOF

chmod +x /root/start_*.sh
echo -e "${GREEN}✓ Created 3 different start scripts${NC}"

# 6. TRY DIFFERENT APPROACHES
section "6. TESTING APPROACHES"

echo "We'll try 3 approaches in order:"
echo "1. Basic (minimal options)"
echo "2. Tensor Parallel (4 GPUs)"
echo "3. Optimized (FP16 KV cache, 760k context)"
echo ""
echo "Choose which to try:"
echo "  1) Basic first"
echo "  2) Tensor Parallel (recommended)"
echo "  3) Optimized (nisten's config)"
echo "  4) Test all (try each for 60 seconds)"
echo ""
read -p "Your choice [1-4]: " choice

case $choice in
    1)
        echo "Starting Basic configuration..."
        screen -dmS vllm_server bash -c '/root/start_basic.sh'
	        ;;
		    2)
			            echo "Starting Tensor Parallel configuration..."
				            screen -dmS vllm_server bash -c '/root/start_tensor_parallel.sh'
        ;;
    3)
        echo "Starting Optimized configuration..."
        screen -dmS vllm_server bash -c '/root/start_optimized.sh'
        ;;
    4)
        echo "Testing all configurations..."
        for script in basic tensor_parallel optimized; do
            echo -e "\n${BLUE}Testing $script configuration...${NC}"
            timeout 60 bash /root/start_${script}.sh > /root/test_${script}.log 2>&1 &
            sleep 10
            if grep -q "Uvicorn running" /root/test_${script}.log 2>/dev/null; then
                echo -e "${GREEN}✓ $script configuration works!${NC}"
                pkill -f vllm
                echo "Use: screen -dmS vllm_server bash -c '/root/start_${script}.sh'"
                break
            else
                echo -e "${RED}✗ $script configuration failed${NC}"
                tail -5 /root/test_${script}.log 2>/dev/null
                pkill -f vllm
		            fi
			            done
				            ;;
			    esac

			    # 7. MONITORING
			    section "7. MONITORING"

			    echo "To monitor the server:"
			    echo "  screen -r vllm_server    # Attach to screen"
			    echo "  tail -f /root/vllm*.log  # Watch logs"
			    echo ""
			    echo "To check if API is ready:"
			    echo "  curl http://localhost:8000/health"
			    echo ""

			    # 8. QUICK DIAGNOSTICS
			    section "8. QUICK DIAGNOSTICS"

			    echo "Checking for common issues..."

			    # Check CUDA
			    python -c "import torch; print(f'PyTorch CUDA: {torch.cuda.is_available()}')"

			    # Check disk space
			    echo ""
			    echo "Disk space:"
			    df -h / /models

			    # Check memory
			    echo ""
			    echo "Memory:"
			    free -h

			    # Check for any errors in existing logs
			    echo ""
			    echo "Recent errors (if any):"
			    grep -i error /root/vllm*.log 2>/dev/null | tail -5 || echo "No error logs found"

			    echo ""
			    echo -e "${BLUE}=== Script Complete ===${NC}"
			    echo "The server is starting in a screen session."
			    echo "Check status with: screen -ls"
			    echo "Attach with: screen -r vllm_server"
