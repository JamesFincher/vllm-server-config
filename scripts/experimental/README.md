# Experimental Scripts

These scripts represent various configurations tested during development. They may work for specific hardware setups or use cases but are not recommended for production.

## Configuration Variants

### Memory-Focused Scripts
- `start_basic.sh` - Minimal configuration for lower memory systems
- `start_fp8_kv.sh` - Aggressive FP8 quantization (may reduce quality)
- `start_optimized.sh` - Memory-optimized with FP16 KV cache

### High-Performance Variants
- `start_nisten_v0.sh` - Based on nisten's v0 engine configuration
- `start_nisten_pool.sh` - Pool-based memory management
- `start_working.sh` - Auto KV cache with tensor parallelism

### Alternative Configurations
- `start_now.sh` - Quick startup with auto settings
- `start_vllm.sh` - Expert parallelism configuration
- `start_vllm_optimized.sh` - NCCL-optimized for H200 GPUs

### Development Scripts
- `start.sh`, `start2.sh` - Early development versions
- `vllm_launcher.sh`, `vllm_server.sh` - Launcher variations
- Single-letter scripts (`p.sh`, `s.sh`, etc.) - Quick test configurations

## Testing Results Summary

| Script | Context Length | Memory Usage | Stability | Notes |
|--------|----------------|--------------|-----------|-------|
| `start_basic.sh` | ~32k | Low | ⭐⭐⭐ | Good for testing |
| `start_fp8_kv.sh` | ~421k | Medium | ⭐⭐ | Quality tradeoffs |
| `start_optimized.sh` | ~200k | Medium-High | ⭐⭐ | FP16 KV cache |
| `start_working.sh` | ~760k | High | ⭐ | Unstable at max |
| **Production** | **700k** | **High** | **⭐⭐⭐** | **Recommended** |

## Usage Warning

⚠️ **These scripts are for experimentation only**

- May not work on all hardware configurations
- Some configurations trade quality for memory efficiency
- Use production scripts for stable deployments
- Test thoroughly before using in production environments

## Development Notes

These scripts helped identify the optimal configuration through iterative testing:
1. Started with basic tensor parallelism (TP=4)
2. Added FP8 KV cache quantization for memory
3. Discovered pipeline parallelism benefits
4. Found optimal TP=2, PP=2 configuration
5. Settled on 700k as maximum stable context length