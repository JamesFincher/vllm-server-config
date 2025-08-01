# vLLM Qwen3-480B API Reference

## Table of Contents
1. [API Overview](#api-overview)
2. [Authentication](#authentication)
3. [Base URLs and Endpoints](#base-urls-and-endpoints)
4. [Chat Completions API](#chat-completions-api)
5. [Models API](#models-api)
6. [Health Check](#health-check)
7. [Request/Response Examples](#requestresponse-examples)
8. [Error Handling](#error-handling)
9. [Rate Limiting](#rate-limiting)
10. [Best Practices](#best-practices)
11. [SDK Examples](#sdk-examples)
12. [Performance Optimization](#performance-optimization)

---

## API Overview

The vLLM server provides an OpenAI-compatible REST API for interacting with the Qwen3-480B model. This allows you to use existing OpenAI client libraries and tools with minimal modifications.

### Key Features
- **OpenAI Compatibility**: Drop-in replacement for OpenAI API
- **700k Context Window**: Process extremely long documents
- **Streaming Support**: Real-time response streaming
- **Batch Processing**: Handle multiple requests efficiently
- **High Performance**: Optimized for 4x H200 GPU setup

### API Specifications
- **Protocol**: HTTP/HTTPS REST API
- **Data Format**: JSON
- **Authentication**: Bearer Token
- **Default Port**: 8000
- **Max Context**: 700,000 tokens
- **Supported Models**: qwen3 (Qwen3-Coder-480B-A35B-Instruct-FP8)

---

## Authentication

All API requests require authentication using a Bearer token in the Authorization header.

### Setting Up Authentication

```bash
# Set your API key
export VLLM_API_KEY="your-secret-api-key-here"

# Use in requests
curl -H "Authorization: Bearer $VLLM_API_KEY" ...
```

### Authentication Header Format

```http
Authorization: Bearer your-secret-api-key-here
```

### Security Best Practices

1. **Never hardcode API keys** in your source code
2. **Use environment variables** to store keys
3. **Rotate keys regularly** in production
4. **Use HTTPS** in production environments
5. **Restrict access** by IP if possible

---

## Base URLs and Endpoints

### Default Configuration
- **Base URL**: `http://localhost:8000`
- **API Version**: `v1`
- **Full Base URL**: `http://localhost:8000/v1`

### Available Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/v1/chat/completions` | POST | Chat completions (primary endpoint) |
| `/v1/models` | GET | List available models |
| `/health` | GET | Server health check |
| `/v1/completions` | POST | Text completions (legacy) |

---

## Chat Completions API

The primary endpoint for interacting with the Qwen3 model.

### Endpoint
```
POST /v1/chat/completions
```

### Request Headers
```http
Content-Type: application/json
Authorization: Bearer your-api-key-here
```

### Request Body Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `model` | string | Yes | - | Model identifier (use "qwen3") |
| `messages` | array | Yes | - | List of message objects |
| `max_tokens` | integer | No | 2048 | Maximum tokens to generate |
| `temperature` | float | No | 0.7 | Sampling temperature (0.0-2.0) |
| `top_p` | float | No | 1.0 | Nucleus sampling parameter |
| `n` | integer | No | 1 | Number of completions to generate |
| `stream` | boolean | No | false | Enable streaming responses |
| `stop` | string/array | No | null | Stop sequences |
| `presence_penalty` | float | No | 0.0 | Presence penalty (-2.0 to 2.0) |
| `frequency_penalty` | float | No | 0.0 | Frequency penalty (-2.0 to 2.0) |
| `user` | string | No | null | User identifier for tracking |

### Message Object Structure

```json
{
  "role": "system|user|assistant",
  "content": "message content here"
}
```

### Basic Request Example

```json
{
  "model": "qwen3",
  "messages": [
    {
      "role": "system",
      "content": "You are a helpful AI assistant."
    },
    {
      "role": "user",
      "content": "Explain quantum computing in simple terms."
    }
  ],
  "max_tokens": 500,
  "temperature": 0.7
}
```

### Response Format

```json
{
  "id": "chatcmpl-123456789",
  "object": "chat.completion",
  "created": 1677652288,
  "model": "qwen3",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Quantum computing is a revolutionary approach to computation..."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 15,
    "completion_tokens": 142,
    "total_tokens": 157
  }
}
```

### Streaming Response Format

When `stream: true` is set, responses are sent as Server-Sent Events:

```
data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1677652288,"model":"qwen3","choices":[{"index":0,"delta":{"content":"Quantum"},"finish_reason":null}]}

data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1677652288,"model":"qwen3","choices":[{"index":0,"delta":{"content":" computing"},"finish_reason":null}]}

data: [DONE]
```

---

## Models API

List available models on the server.

### Endpoint
```
GET /v1/models
```

### Request Example
```bash
curl -H "Authorization: Bearer $VLLM_API_KEY" \
     http://localhost:8000/v1/models
```

### Response Format
```json
{
  "object": "list",
  "data": [
    {
      "id": "qwen3",
      "object": "model",
      "created": 1677610602,
      "owned_by": "vllm",
      "permission": [],
      "root": "qwen3",
      "parent": null
    }
  ]
}
```

---

## Health Check

Check server status and availability.

### Endpoint
```
GET /health
```

### Request Example
```bash
curl http://localhost:8000/health
```

### Response Format
```json
{
  "status": "ok"
}
```

---

## Request/Response Examples

### Example 1: Simple Chat

**Request:**
```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -d '{
    "model": "qwen3",
    "messages": [
      {"role": "user", "content": "Hello, how are you?"}
    ],
    "max_tokens": 100
  }'
```

**Response:**
```json
{
  "id": "chatcmpl-abc123",
  "object": "chat.completion",
  "created": 1677652288,
  "model": "qwen3",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Hello! I'm doing well, thank you for asking. I'm an AI assistant powered by the Qwen3 model, and I'm here to help you with any questions or tasks you might have. How can I assist you today?"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 7,
    "completion_tokens": 38,
    "total_tokens": 45
  }
}
```

### Example 2: Code Generation

**Request:**
```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -d '{
    "model": "qwen3",
    "messages": [
      {
        "role": "system", 
        "content": "You are an expert Python programmer."
      },
      {
        "role": "user", 
        "content": "Write a Python function to calculate the factorial of a number using recursion."
      }
    ],
    "max_tokens": 300,
    "temperature": 0.1
  }'
```

**Response:**
```json
{
  "id": "chatcmpl-def456",
  "object": "chat.completion",
  "created": 1677652350,
  "model": "qwen3",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Here's a Python function to calculate the factorial of a number using recursion:\n\n```python\ndef factorial(n):\n    \"\"\"\n    Calculate the factorial of a number using recursion.\n    \n    Args:\n        n (int): A non-negative integer\n    \n    Returns:\n        int: The factorial of n\n    \n    Raises:\n        ValueError: If n is negative\n    \"\"\"\n    if n < 0:\n        raise ValueError(\"Factorial is not defined for negative numbers\")\n    elif n == 0 or n == 1:\n        return 1\n    else:\n        return n * factorial(n - 1)\n\n# Example usage:\nprint(factorial(5))  # Output: 120\nprint(factorial(0))  # Output: 1\n```\n\nThis function works by:\n1. Handling the base cases (n=0 or n=1) which return 1\n2. For any other positive number, it returns n multiplied by the factorial of (n-1)\n3. Including error handling for negative inputs"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 25,
    "completion_tokens": 198,
    "total_tokens": 223
  }
}
```

### Example 3: Long Document Analysis

**Request:**
```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -d '{
    "model": "qwen3",
    "messages": [
      {
        "role": "user",
        "content": "Please analyze this research paper and provide a summary of key findings:\n\n[VERY LONG DOCUMENT TEXT - up to 500k tokens]"
      }
    ],
    "max_tokens": 2000,
    "temperature": 0.3
  }'
```

### Example 4: Streaming Response

**Request:**
```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -d '{
    "model": "qwen3",
    "messages": [
      {"role": "user", "content": "Write a detailed explanation of machine learning."}
    ],
    "max_tokens": 1000,
    "stream": true
  }'
```

**Streaming Response:**
```
data: {"id":"chatcmpl-stream1","object":"chat.completion.chunk","created":1677652288,"model":"qwen3","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}

data: {"id":"chatcmpl-stream1","object":"chat.completion.chunk","created":1677652288,"model":"qwen3","choices":[{"index":0,"delta":{"content":"Machine"},"finish_reason":null}]}

data: {"id":"chatcmpl-stream1","object":"chat.completion.chunk","created":1677652288,"model":"qwen3","choices":[{"index":0,"delta":{"content":" learning"},"finish_reason":null}]}

data: {"id":"chatcmpl-stream1","object":"chat.completion.chunk","created":1677652288,"model":"qwen3","choices":[{"index":0,"delta":{"content":" is"},"finish_reason":null}]}

...

data: [DONE]
```

---

## Error Handling

### Error Response Format

```json
{
  "error": {
    "message": "Error description",
    "type": "error_type",
    "param": "parameter_name",
    "code": "error_code"
  }
}
```

### Common Error Codes

| HTTP Code | Error Type | Description | Solution |
|-----------|------------|-------------|----------|
| 400 | `invalid_request_error` | Malformed request | Check request format |
| 401 | `authentication_error` | Invalid API key | Verify API key |
| 403 | `permission_error` | Access denied | Check permissions |
| 404 | `not_found_error` | Endpoint not found | Check URL |
| 429 | `rate_limit_error` | Too many requests | Implement backoff |
| 500 | `internal_server_error` | Server error | Contact support |
| 503 | `service_unavailable` | Server overloaded | Retry later |

### Error Handling Examples

**Authentication Error:**
```json
{
  "error": {
    "message": "Incorrect API key provided",
    "type": "authentication_error",
    "param": null,
    "code": "invalid_api_key"
  }
}
```

**Request Too Large:**
```json
{
  "error": {
    "message": "Request exceeds maximum context length of 700000 tokens",
    "type": "invalid_request_error",
    "param": "messages",
    "code": "context_length_exceeded"
  }
}
```

**Rate Limit:**
```json
{
  "error": {
    "message": "Rate limit exceeded",
    "type": "rate_limit_error",
    "param": null,
    "code": "rate_limit_exceeded"
  }
}
```

---

## Rate Limiting

### Default Limits

| Resource | Limit | Window |
|----------|-------|--------|
| Requests per minute | 60 | 60 seconds |
| Tokens per minute | 100,000 | 60 seconds |
| Concurrent requests | 10 | - |

### Rate Limit Headers

```http
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 45
X-RateLimit-Reset: 1677652400
```

### Handling Rate Limits

```python
import time
import requests

def make_request_with_backoff(url, data, headers, max_retries=3):
    for attempt in range(max_retries):
        response = requests.post(url, json=data, headers=headers)
        
        if response.status_code == 429:
            # Rate limited
            retry_after = int(response.headers.get('Retry-After', 60))
            print(f"Rate limited. Waiting {retry_after} seconds...")
            time.sleep(retry_after)
            continue
        
        return response
    
    raise Exception("Max retries exceeded")
```

---

## Best Practices

### 1. Request Optimization

**Use Appropriate Max Tokens:**
```python
# For short responses
"max_tokens": 100

# For detailed explanations
"max_tokens": 1000

# For very long outputs
"max_tokens": 4000
```

**Optimize Temperature:**
```python
# For factual, consistent responses
"temperature": 0.1

# For balanced creativity
"temperature": 0.7

# For creative writing
"temperature": 1.0
```

### 2. Context Management

**Efficient Context Usage:**
```python
# Keep context focused and relevant
messages = [
    {"role": "system", "content": "Brief, focused system prompt"},
    {"role": "user", "content": "Specific question"}
]

# Avoid unnecessary context
# Instead of including entire documents, summarize key points
```

**Long Document Processing:**
```python
def process_long_document(document, question):
    # Split very long documents into chunks
    chunk_size = 100000  # tokens
    chunks = split_document(document, chunk_size)
    
    summaries = []
    for chunk in chunks:
        response = chat_completion({
            "messages": [
                {"role": "user", "content": f"Summarize: {chunk}"}
            ],
            "max_tokens": 500
        })
        summaries.append(response["choices"][0]["message"]["content"])
    
    # Final analysis on summaries
    final_response = chat_completion({
        "messages": [
            {"role": "user", "content": f"Based on these summaries: {summaries}, answer: {question}"}
        ]
    })
    
    return final_response
```

### 3. Error Handling

**Robust Error Handling:**
```python
import requests
import json
import time

def robust_chat_completion(messages, **kwargs):
    max_retries = 3
    base_delay = 1
    
    for attempt in range(max_retries):
        try:
            response = requests.post(
                "http://localhost:8000/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": "qwen3",
                    "messages": messages,
                    **kwargs
                },
                timeout=300  # 5 minute timeout
            )
            
            if response.status_code == 200:
                return response.json()
            elif response.status_code == 429:
                # Rate limited
                delay = base_delay * (2 ** attempt)
                time.sleep(delay)
                continue
            else:
                # Other error
                error_data = response.json()
                raise Exception(f"API Error: {error_data}")
                
        except requests.exceptions.Timeout:
            if attempt == max_retries - 1:
                raise Exception("Request timed out after all retries")
            time.sleep(base_delay * (2 ** attempt))
            
        except requests.exceptions.ConnectionError:
            if attempt == max_retries - 1:
                raise Exception("Could not connect to server")
            time.sleep(base_delay * (2 ** attempt))
    
    raise Exception("Max retries exceeded")
```

### 4. Performance Optimization

**Batch Processing:**
```python
async def process_multiple_requests(request_list):
    import asyncio
    import aiohttp
    
    async def make_request(session, data):
        async with session.post(
            "http://localhost:8000/v1/chat/completions",
            json=data,
            headers={"Authorization": f"Bearer {api_key}"}
        ) as response:
            return await response.json()
    
    async with aiohttp.ClientSession() as session:
        tasks = [make_request(session, req) for req in request_list]
        results = await asyncio.gather(*tasks)
        return results
```

**Streaming for Long Responses:**
```python
def stream_chat_completion(messages, **kwargs):
    response = requests.post(
        "http://localhost:8000/v1/chat/completions",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        },
        json={
            "model": "qwen3",
            "messages": messages,
            "stream": True,
            **kwargs
        },
        stream=True
    )
    
    for line in response.iter_lines():
        if line:
            line = line.decode('utf-8')
            if line.startswith('data: '):
                data = line[6:]  # Remove 'data: ' prefix
                if data != '[DONE]':
                    try:
                        chunk = json.loads(data)
                        content = chunk['choices'][0]['delta'].get('content', '')
                        if content:
                            yield content
                    except json.JSONDecodeError:
                        pass
```

---

## SDK Examples

### Python OpenAI Client

```python
import openai

# Configure client for local vLLM server
client = openai.OpenAI(
    api_key="your-api-key-here",
    base_url="http://localhost:8000/v1"
)

# Basic chat completion
response = client.chat.completions.create(
    model="qwen3",
    messages=[
        {"role": "user", "content": "Hello, world!"}
    ],
    max_tokens=100
)

print(response.choices[0].message.content)

# Streaming response
stream = client.chat.completions.create(
    model="qwen3",
    messages=[
        {"role": "user", "content": "Write a short story"}
    ],
    max_tokens=1000,
    stream=True
)

for chunk in stream:
    if chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="")
```

### JavaScript/Node.js

```javascript
import OpenAI from 'openai';

const openai = new OpenAI({
  apiKey: 'your-api-key-here',
  baseURL: 'http://localhost:8000/v1',
});

async function chatCompletion() {
  const response = await openai.chat.completions.create({
    model: 'qwen3',
    messages: [
      { role: 'user', content: 'Explain quantum computing' }
    ],
    max_tokens: 500,
  });
  
  console.log(response.choices[0].message.content);
}

// Streaming example
async function streamCompletion() {
  const stream = await openai.chat.completions.create({
    model: 'qwen3',
    messages: [
      { role: 'user', content: 'Write a poem about AI' }
    ],
    max_tokens: 1000,
    stream: true,
  });
  
  for await (const chunk of stream) {
    const content = chunk.choices[0]?.delta?.content || '';
    process.stdout.write(content);
  }
}
```

### cURL Examples

```bash
# Basic completion
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 100
  }'

# With system message
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3",
    "messages": [
      {"role": "system", "content": "You are a helpful coding assistant."},
      {"role": "user", "content": "Write a Python hello world program"}
    ],
    "max_tokens": 200,
    "temperature": 0.1
  }'

# Streaming response
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3",
    "messages": [{"role": "user", "content": "Count to 10"}],
    "max_tokens": 100,
    "stream": true
  }'
```

---

## Performance Optimization

### Request Optimization

**Optimize for Speed:**
```json
{
  "model": "qwen3",
  "messages": [...],
  "max_tokens": 500,
  "temperature": 0.1,
  "top_p": 0.9,
  "stream": true
}
```

**Optimize for Quality:**
```json
{
  "model": "qwen3",
  "messages": [...],
  "max_tokens": 1000,
  "temperature": 0.7,
  "top_p": 0.95,
  "presence_penalty": 0.1
}
```

### Monitoring Performance

```python
import time
import requests

def benchmark_request(messages, max_tokens=100):
    start_time = time.time()
    
    response = requests.post(
        "http://localhost:8000/v1/chat/completions",
        headers={"Authorization": f"Bearer {api_key}"},
        json={
            "model": "qwen3",
            "messages": messages,
            "max_tokens": max_tokens
        }
    )
    
    end_time = time.time()
    
    if response.status_code == 200:
        data = response.json()
        tokens = data["usage"]["total_tokens"]
        duration = end_time - start_time
        tokens_per_second = tokens / duration
        
        print(f"Tokens: {tokens}")
        print(f"Duration: {duration:.2f}s")
        print(f"Speed: {tokens_per_second:.2f} tokens/s")
        
        return data
    else:
        print(f"Error: {response.text}")
        return None
```

### Best Practices Summary

1. **Use streaming** for long responses
2. **Set appropriate max_tokens** to avoid unnecessary computation
3. **Implement proper error handling** with retries
4. **Monitor performance** and adjust parameters
5. **Use batch processing** for multiple requests
6. **Keep context focused** and relevant
7. **Handle rate limits** gracefully
8. **Use environment variables** for API keys
9. **Implement timeouts** for reliability
10. **Cache responses** when appropriate

---

This API reference provides comprehensive information for integrating with the vLLM Qwen3-480B server. The OpenAI-compatible interface makes it easy to migrate existing applications or integrate with existing tools and libraries.