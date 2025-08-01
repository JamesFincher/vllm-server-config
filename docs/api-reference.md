# vLLM API Reference for Qwen3-480B

Complete API documentation based on production testing and optimization.

## Overview

- **Base URL**: `http://localhost:8000/v1`
- **Authentication**: Bearer token via `Authorization: Bearer {api_key}`
- **Model ID**: `qwen3` (confirmed working identifier)
- **Context Window**: 200,000 tokens
- **Performance**: ~0.87s response time, ~75 tokens/second generation

## Authentication

All API endpoints require authentication via Bearer token:

```bash
Authorization: Bearer your-api-key-here
```

## Endpoints

### 1. Health Check

**Endpoint**: `GET /health`
- **Purpose**: Check server health status
- **Authentication**: Required
- **Response**: Basic health information

```bash
curl -H "Authorization: Bearer your-api-key" http://localhost:8000/health
```

### 2. List Models

**Endpoint**: `GET /v1/models`
- **Purpose**: Get available models
- **Authentication**: Required

```bash
curl -H "Authorization: Bearer your-api-key" http://localhost:8000/v1/models
```

**Response**:
```json
{
  "object": "list",
  "data": [
    {
      "id": "qwen3",
      "object": "model", 
      "created": 1754001981,
      "owned_by": "vllm",
      "root": "/models/qwen3",
      "parent": null,
      "max_model_len": 200000,
      "permission": [...]
    }
  ]
}
```

### 3. Chat Completions

**Endpoint**: `POST /v1/chat/completions`
- **Purpose**: Generate chat responses
- **Model**: Use `"qwen3"` as model identifier

#### Basic Usage

```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3",
    "messages": [
      {"role": "user", "content": "Hello, how are you?"}
    ],
    "max_tokens": 100
  }'
```

#### Advanced Parameters

```json
{
  "model": "qwen3",
  "messages": [
    {"role": "system", "content": "You are a helpful coding assistant."},
    {"role": "user", "content": "Write a Python function to calculate fibonacci numbers"}
  ],
  "max_tokens": 1000,
  "temperature": 0.7,
  "top_p": 0.95,
  "frequency_penalty": 0.0,
  "presence_penalty": 0.0,
  "stop": null,
  "stream": false
}
```

#### Response Format

```json
{
  "id": "chatcmpl-...",
  "object": "chat.completion",
  "created": 1754001981,
  "model": "qwen3",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Generated response here..."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 25,
    "completion_tokens": 66,
    "total_tokens": 91
  }
}
```

### 4. Streaming Chat Completions

Enable real-time streaming by setting `"stream": true`:

```bash
curl -N -X POST http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3",
    "messages": [{"role": "user", "content": "Count to 10"}],
    "stream": true,
    "max_tokens": 100
  }'
```

#### Streaming Response Format

```
data: {"id":"chatcmpl-...","object":"chat.completion.chunk","created":1754001981,"model":"qwen3","choices":[{"index":0,"delta":{"role":"assistant","content":"1"},"finish_reason":null}]}

data: {"id":"chatcmpl-...","object":"chat.completion.chunk","created":1754001981,"model":"qwen3","choices":[{"index":0,"delta":{"content":", 2"},"finish_reason":null}]}

data: [DONE]
```

### 5. Text Completions

**Endpoint**: `POST /v1/completions`
- **Purpose**: Generate text completions (non-chat format)

```bash
curl -X POST http://localhost:8000/v1/completions \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3",
    "prompt": "The capital of France is",
    "max_tokens": 10,
    "temperature": 0.0
  }'
```

## Performance Characteristics

### Benchmarks (Based on Production Testing)

| Metric | Value |
|--------|-------|
| Response Time (Simple) | ~0.87 seconds |
| Token Generation Speed | ~75 tokens/second |
| Context Window | 200,000 tokens |
| Concurrent Requests | Tested up to 5 concurrent |
| Maximum Single Request | 8,192 tokens tested |

### Optimization Tips

1. **Temperature Settings**:
   - `0.0-0.3`: Deterministic, good for code generation
   - `0.7-0.9`: Creative, good for writing tasks
   - `1.0+`: Highly creative but potentially inconsistent

2. **Token Limits**:
   - Keep `max_tokens` reasonable (1000-4000 for most uses)
   - Higher token counts increase response time linearly
   - Monitor `usage` object for actual consumption

3. **Context Management**:
   - Full 200k context available but affects performance
   - Consider conversation truncation for long chats
   - Use system messages efficiently

## Error Handling

### Common HTTP Status Codes

- `200`: Success
- `400`: Bad Request (invalid parameters)
- `401`: Unauthorized (missing/invalid API key)
- `422`: Validation Error (parameter validation failed)
- `500`: Internal Server Error

### Error Response Format

```json
{
  "error": {
    "message": "Invalid request: model parameter is required",
    "type": "invalid_request_error",
    "code": null
  }
}
```

### Common Issues & Solutions

1. **401 Unauthorized**
   - Check API key in Authorization header
   - Ensure Bearer token format: `Bearer your-api-key`

2. **400 Bad Request with model name**
   - Use `"qwen3"` not `"/models/qwen3"`
   - Verify model name exactly matches available models

3. **Context length exceeded**
   - Reduce input length or max_tokens
   - Maximum context is 200,000 tokens total

## Client Integration Examples

### CRUSH CLI Configuration

```json
{
  "$schema": "https://charm.land/crush.json",
  "providers": {
    "vllm": {
      "type": "openai",
      "base_url": "http://localhost:8000/v1",
      "api_key": "your-api-key",
      "models": [
        {
          "id": "qwen3",
          "name": "Qwen3-480B Local",
          "context_window": 200000,
          "default_max_tokens": 8192
        }
      ]
    }
  },
  "default_provider": "vllm",
  "default_model": "qwen3"
}
```

### Python OpenAI Client

```python
from openai import OpenAI

client = OpenAI(
    api_key="your-api-key",
    base_url="http://localhost:8000/v1"
)

response = client.chat.completions.create(
    model="qwen3",
    messages=[
        {"role": "user", "content": "Write a Python function"}
    ],
    max_tokens=500
)

print(response.choices[0].message.content)
```

### JavaScript/Node.js

```javascript
import OpenAI from 'openai';

const openai = new OpenAI({
  apiKey: 'your-api-key',
  baseURL: 'http://localhost:8000/v1',
});

const completion = await openai.chat.completions.create({
  messages: [{ role: 'user', content: 'Hello!' }],
  model: 'qwen3',
  max_tokens: 100,
});

console.log(completion.choices[0].message.content);
```

## Monitoring & Debugging

### Health Monitoring

```bash
# Check server status
curl -H "Authorization: Bearer your-api-key" http://localhost:8000/health

# Monitor response times
time curl -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -X POST http://localhost:8000/v1/chat/completions \
  -d '{"model":"qwen3","messages":[{"role":"user","content":"test"}],"max_tokens":10}'
```

### Performance Testing

```bash
# Token generation speed test
START=$(date +%s.%N)
RESPONSE=$(curl -s -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -X POST http://localhost:8000/v1/chat/completions \
  -d '{
    "model": "qwen3",
    "messages": [{"role": "user", "content": "Write a detailed explanation of machine learning"}],
    "max_tokens": 1000
  }')
END=$(date +%s.%N)
DURATION=$(echo "$END - $START" | bc)
TOKENS=$(echo "$RESPONSE" | jq -r '.usage.completion_tokens')
echo "Generated $TOKENS tokens in ${DURATION}s ($(echo "scale=2; $TOKENS / $DURATION" | bc) tokens/sec)"
```

## Rate Limits & Quotas

- **No enforced rate limits** (local deployment)
- **Concurrent requests**: Limited by GPU memory
- **Context length**: Hard limit at 200,000 tokens
- **Response time**: Scales with token count and complexity

## Security Notes

- API runs locally (no external network exposure by default)
- API key provides full access to model
- No built-in request logging (privacy by design)
- Consider firewall rules if exposing beyond localhost