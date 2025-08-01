# Production Scripts

These scripts are battle-tested and recommended for production deployments.

## Scripts

### `start-vllm-server.sh` ⭐ **Recommended**
Full-featured production server startup with:
- Command-line argument parsing
- Comprehensive error checking
- Logging and monitoring setup
- Screen session management
- Hardware validation

**Usage:**
```bash
./start-vllm-server.sh --api-key your-key --context-length 700000
```

### `start_700k_final.sh`
Tested configuration that achieves 700k context length:
- Tensor Parallelism: 2
- Pipeline Parallelism: 2
- FP8 KV cache for memory efficiency
- 98% GPU memory utilization

### `start_pipeline.sh`
Pipeline parallelism configuration for maximum context length.

### `start_qwen3.sh`
Basic startup script based on the original working configuration.

## Configuration Notes

All production scripts use the optimized configuration discovered through testing:
- **Context Length**: 700,000 tokens (maximum stable)
- **Parallelism**: TP=2, PP=2 (optimal for 4x H200 GPUs)
- **Memory**: 98% GPU utilization with FP8 KV cache
- **Startup Time**: 5-10 minutes for model loading