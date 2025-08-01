#!/bin/bash

# vLLM Troubleshooting Script
# Based on production deployment analysis and proven fixes

# Configuration from chat history analysis
API_KEY="qwen3-secret-key"
API_URL="http://localhost:8000/v1"
MODEL_ID="qwen3"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=== vLLM Troubleshooting Script ==="
echo "Based on production deployment analysis"
echo ""

# Function to test API endpoint
test_api_endpoint() {
    local endpoint="$1"
    local description="$2"
    
    echo -e "${BLUE}Testing: $description${NC}"
    echo "Endpoint: $endpoint"
    
    RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" "$API_URL$endpoint" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json")
    
    HTTP_STATUS=$(echo "$RESPONSE" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    BODY=$(echo "$RESPONSE" | sed -e 's/HTTPSTATUS\:.*//g')
    
    if [ "$HTTP_STATUS" -eq 200 ]; then
        echo -e "${GREEN}✅ Success (HTTP $HTTP_STATUS)${NC}"
        if [ "$endpoint" = "/models" ]; then
            echo "Available models:"
            echo "$BODY" | jq -r '.data[].id' | sed 's/^/  - /'
        fi
    else
        echo -e "${RED}❌ Failed (HTTP $HTTP_STATUS)${NC}"
        echo "Response: $BODY"
    fi
    echo ""
}

# 1. Check tunnel and connectivity
echo -e "${BLUE}1. Checking SSH tunnel and connectivity...${NC}"
if pgrep -f "ssh.*8000:localhost:8000" > /dev/null; then
    echo -e "${GREEN}✅ SSH tunnel is running${NC}"
else
    echo -e "${RED}❌ SSH tunnel not running${NC}"
    echo "Fix: Run './connect.sh start' or equivalent tunnel command"
    exit 1
fi

# Test basic connectivity
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/health")
echo "Health endpoint status: $HEALTH_STATUS"
echo ""

# 2. Test API endpoints
test_api_endpoint "/models" "List available models"

# 3. Test chat completion with proven working settings
echo -e "${BLUE}3. Testing chat completion (proven working format)...${NC}"
CHAT_RESPONSE=$(curl -s "$API_URL/chat/completions" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"$MODEL_ID\",
      \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}],
      \"max_tokens\": 10
    }")

if echo "$CHAT_RESPONSE" | jq -e '.choices' > /dev/null 2>&1; then
    CONTENT=$(echo "$CHAT_RESPONSE" | jq -r '.choices[0].message.content')
    echo -e "${GREEN}✅ Chat completion working!${NC}"
    echo "Response: $CONTENT"
    
    # Extract usage stats
    PROMPT_TOKENS=$(echo "$CHAT_RESPONSE" | jq -r '.usage.prompt_tokens // "N/A"')
    COMPLETION_TOKENS=$(echo "$CHAT_RESPONSE" | jq -r '.usage.completion_tokens // "N/A"')
    echo "Usage: $PROMPT_TOKENS prompt + $COMPLETION_TOKENS completion tokens"
else
    echo -e "${RED}❌ Chat completion failed${NC}"
    echo "Response: $CHAT_RESPONSE"
fi
echo ""

# 4. CRUSH configuration check
echo -e "${BLUE}4. Checking CRUSH configuration...${NC}"
CRUSH_CONFIGS=(
    "$HOME/.config/crush/config.json"
    "$HOME/Library/Application Support/crush/config.json"
    "./.crush/config.json"
)

FOUND_CONFIG=false
for config in "${CRUSH_CONFIGS[@]}"; do
    if [ -f "$config" ]; then
        echo -e "${GREEN}✅ Found config: $config${NC}"
        
        # Check if it has the correct model ID
        if jq -e ".providers[].models[] | select(.id == \"$MODEL_ID\")" "$config" > /dev/null 2>&1; then
            echo -e "${GREEN}  ✅ Contains correct model ID: $MODEL_ID${NC}"
        else
            echo -e "${YELLOW}  ⚠️  Model ID might be incorrect${NC}"
            echo "  Expected: $MODEL_ID"
            echo "  Found: $(jq -r '.providers[].models[].id' "$config" 2>/dev/null || echo 'N/A')"
        fi
        FOUND_CONFIG=true
        break
    fi
done

if [ "$FOUND_CONFIG" = false ]; then
    echo -e "${RED}❌ No CRUSH config found${NC}"
    echo "Creating working configuration..."
    
    mkdir -p "$HOME/.config/crush"
    cat > "$HOME/.config/crush/config.json" << EOF
{
  "\$schema": "https://charm.land/crush.json",
  "providers": {
    "vllm-local": {
      "type": "openai",
      "base_url": "$API_URL",
      "api_key": "$API_KEY",
      "models": [
        {
          "id": "$MODEL_ID",
          "name": "Qwen3-480B Local (200k context)",
          "context_window": 200000,
          "default_max_tokens": 8192,
          "cost_per_1m_in": 0,
          "cost_per_1m_out": 0
        }
      ]
    }
  },
  "default_provider": "vllm-local",
  "default_model": "$MODEL_ID",
  "options": {
    "debug": false
  }
}
EOF
    echo -e "${GREEN}✅ Created working CRUSH configuration${NC}"
fi
echo ""

# 5. Performance test
echo -e "${BLUE}5. Running performance test...${NC}"
START_TIME=$(date +%s.%N)

PERF_RESPONSE=$(curl -s "$API_URL/chat/completions" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"$MODEL_ID\",
      \"messages\": [{\"role\": \"user\", \"content\": \"Write a simple Python function to calculate fibonacci numbers.\"}],
      \"max_tokens\": 100
    }")

END_TIME=$(date +%s.%N)

if echo "$PERF_RESPONSE" | jq -e '.choices' > /dev/null 2>&1; then
    DURATION=$(echo "$END_TIME - $START_TIME" | bc)
    COMPLETION_TOKENS=$(echo "$PERF_RESPONSE" | jq -r '.usage.completion_tokens')
    TOKENS_PER_SECOND=$(echo "scale=2; $COMPLETION_TOKENS / $DURATION" | bc)
    
    echo -e "${GREEN}✅ Performance test successful${NC}"
    echo "Duration: ${DURATION}s"
    echo "Tokens generated: $COMPLETION_TOKENS"
    echo "Speed: ${TOKENS_PER_SECOND} tokens/second"
    
    # Compare to expected performance
    EXPECTED_SPEED=75
    if (( $(echo "$TOKENS_PER_SECOND > $EXPECTED_SPEED" | bc -l) )); then
        echo -e "${GREEN}🚀 Excellent performance (above expected $EXPECTED_SPEED tokens/sec)${NC}"
    elif (( $(echo "$TOKENS_PER_SECOND > 50" | bc -l) )); then
        echo -e "${YELLOW}⚡ Good performance (above 50 tokens/sec)${NC}"
    else
        echo -e "${YELLOW}⚠️  Performance below expected (target: 75+ tokens/sec)${NC}"
    fi
else
    echo -e "${RED}❌ Performance test failed${NC}"
    echo "Response: $PERF_RESPONSE"
fi
echo ""

# 6. Common issue checks
echo -e "${BLUE}6. Checking for common issues...${NC}"

# Check for model name issues
echo "Checking model name format..."
if [ "$MODEL_ID" = "qwen3" ]; then
    echo -e "${GREEN}✅ Using correct simplified model name${NC}"
else
    echo -e "${YELLOW}⚠️  Consider using 'qwen3' as model ID${NC}"
fi

# Check environment variables
echo "Checking environment variables..."
ENV_VARS_OK=true
if [ -z "$VLLM_API_KEY" ] && [ -z "$OPENAI_API_KEY" ]; then
    echo -e "${YELLOW}⚠️  No API key environment variables set${NC}"
    echo "Consider setting: export OPENAI_API_KEY='$API_KEY'"
    ENV_VARS_OK=false
fi

if [ "$ENV_VARS_OK" = true ]; then
    echo -e "${GREEN}✅ Environment variables look good${NC}"
fi
echo ""

# 7. Summary and recommendations
echo -e "${BLUE}=== Summary and Recommendations ===${NC}"
echo ""
echo "Based on production analysis, your setup should:"
echo "• Use model ID: 'qwen3'"
echo "• API endpoint: 'http://localhost:8000/v1'"
echo "• Expected performance: ~75 tokens/second, <1s response time"
echo "• Max stable context: 200k tokens (700k with FP8 optimization)"
echo ""

echo "If CRUSH still has issues:"
echo "1. Try environment variables:"
echo "   export OPENAI_API_KEY='$API_KEY'"
echo "   export OPENAI_API_BASE='$API_URL'"
echo "   crush"
echo ""
echo "2. Check CRUSH logs:"
echo "   crush logs --tail 100"
echo ""
echo "3. Run CRUSH with debug:"
echo "   crush --debug"
echo ""

echo -e "${GREEN}Troubleshooting complete!${NC}"