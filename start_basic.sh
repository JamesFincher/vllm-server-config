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
