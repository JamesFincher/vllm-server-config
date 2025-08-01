#!/bin/bash

# vLLM Performance Testing Suite
# Based on production analysis and proven benchmarks from chathistory5.md

# Configuration
API_KEY="qwen3-secret-key"
API_URL="http://localhost:8000/v1"
MODEL_ID="qwen3"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Performance expectations based on production data
EXPECTED_RESPONSE_TIME=1.0  # seconds
EXPECTED_TOKENS_PER_SEC=75
MIN_ACCEPTABLE_TOKENS_PER_SEC=50

echo "=== vLLM Performance Testing Suite ==="
echo "Based on proven production benchmarks"
echo "Expected performance: ~75 tokens/sec, <1s response time"
echo ""

# Check if API is available
check_api_availability() {
    echo -e "${BLUE}Checking API availability...${NC}"
    
    HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/health")
    MODELS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/models" -H "Authorization: Bearer $API_KEY")
    
    if [ "$MODELS_STATUS" -eq 200 ]; then
        echo -e "${GREEN}✅ API is available and responding${NC}"
        return 0
    else
        echo -e "${RED}❌ API not available (Status: $MODELS_STATUS)${NC}"
        return 1
    fi
}

# Test 1: Basic Response Time
test_basic_response_time() {
    echo -e "\n${CYAN}=== Test 1: Basic Response Time ===${NC}"
    echo "Testing simple query response time..."
    
    for i in {1..3}; do
        echo "Run $i/3:"
        
        START_TIME=$(date +%s.%N)
        
        RESPONSE=$(curl -s "$API_URL/chat/completions" \
            -H "Authorization: Bearer $API_KEY" \
            -H "Content-Type: application/json" \
            -d "{
                \"model\": \"$MODEL_ID\",
                \"messages\": [{\"role\": \"user\", \"content\": \"Hello, how are you?\"}],
                \"max_tokens\": 20
            }")
        
        END_TIME=$(date +%s.%N)
        
        if echo "$RESPONSE" | jq -e '.choices' > /dev/null 2>&1; then
            DURATION=$(echo "$END_TIME - $START_TIME" | bc)
            TOKENS=$(echo "$RESPONSE" | jq -r '.usage.completion_tokens')
            
            echo "  Duration: ${DURATION}s"
            echo "  Tokens: $TOKENS"
            
            if (( $(echo "$DURATION < $EXPECTED_RESPONSE_TIME" | bc -l) )); then
                echo -e "  ${GREEN}✅ Within expected time${NC}"
            else
                echo -e "  ${YELLOW}⚠️  Slower than expected ($EXPECTED_RESPONSE_TIME s)${NC}"
            fi
        else
            echo -e "  ${RED}❌ Request failed${NC}"
            echo "  Response: $RESPONSE"
        fi
        echo ""
    done
}

# Test 2: Token Generation Speed
test_token_generation_speed() {
    echo -e "${CYAN}=== Test 2: Token Generation Speed ===${NC}"
    echo "Testing sustained token generation with coding task..."
    
    START_TIME=$(date +%s.%N)
    
    RESPONSE=$(curl -s "$API_URL/chat/completions" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$MODEL_ID\",
            \"messages\": [{
                \"role\": \"user\", 
                \"content\": \"Write a Python function to implement quicksort algorithm with detailed comments explaining each step.\"
            }],
            \"max_tokens\": 200,
            \"temperature\": 0.7
        }")
    
    END_TIME=$(date +%s.%N)
    
    if echo "$RESPONSE" | jq -e '.choices' > /dev/null 2>&1; then
        DURATION=$(echo "$END_TIME - $START_TIME" | bc)
        PROMPT_TOKENS=$(echo "$RESPONSE" | jq -r '.usage.prompt_tokens')
        COMPLETION_TOKENS=$(echo "$RESPONSE" | jq -r '.usage.completion_tokens')
        TOTAL_TOKENS=$(echo "$RESPONSE" | jq -r '.usage.total_tokens')
        
        TOKENS_PER_SECOND=$(echo "scale=2; $COMPLETION_TOKENS / $DURATION" | bc)
        
        echo "Duration: ${DURATION}s"
        echo "Prompt tokens: $PROMPT_TOKENS"
        echo "Completion tokens: $COMPLETION_TOKENS"
        echo "Total tokens: $TOTAL_TOKENS"
        echo "Generation speed: ${TOKENS_PER_SECOND} tokens/second"
        
        if (( $(echo "$TOKENS_PER_SECOND >= $EXPECTED_TOKENS_PER_SEC" | bc -l) )); then
            echo -e "${GREEN}🚀 Excellent performance (meets/exceeds expected $EXPECTED_TOKENS_PER_SEC tokens/sec)${NC}"
        elif (( $(echo "$TOKENS_PER_SECOND >= $MIN_ACCEPTABLE_TOKENS_PER_SEC" | bc -l) )); then
            echo -e "${YELLOW}⚡ Good performance (above minimum $MIN_ACCEPTABLE_TOKENS_PER_SEC tokens/sec)${NC}"
        else
            echo -e "${RED}⚠️  Performance below acceptable threshold${NC}"
        fi
        
        echo ""
        echo "Response preview:"
        echo "$RESPONSE" | jq -r '.choices[0].message.content' | head -c 200
        echo "..."
    else
        echo -e "${RED}❌ Token generation test failed${NC}"
        echo "Response: $RESPONSE"
    fi
    echo ""
}

# Test 3: Large Context Handling
test_large_context() {
    echo -e "${CYAN}=== Test 3: Large Context Handling ===${NC}"
    echo "Testing with larger context input..."
    
    # Create a large prompt (simulate analyzing code)
    LARGE_CONTEXT="You are a senior software engineer reviewing the following Python code for a web application. Please provide a detailed analysis including potential bugs, performance improvements, security issues, and best practices.\n\n"
    LARGE_CONTEXT+="def process_user_data(user_input):\n"
    LARGE_CONTEXT+="    import os, subprocess, json\n"
    LARGE_CONTEXT+="    data = json.loads(user_input)\n"
    LARGE_CONTEXT+="    command = f'echo {data[\"name\"]} >> users.txt'\n"
    LARGE_CONTEXT+="    subprocess.run(command, shell=True)\n"
    LARGE_CONTEXT+="    with open('/tmp/user_data.json', 'w') as f:\n"
    LARGE_CONTEXT+="        json.dump(data, f)\n"
    LARGE_CONTEXT+="    return {'status': 'success', 'user': data['name']}\n\n"
    LARGE_CONTEXT+="class UserManager:\n"
    LARGE_CONTEXT+="    def __init__(self):\n"
    LARGE_CONTEXT+="        self.users = []\n"
    LARGE_CONTEXT+="        self.db_connection = None\n"
    LARGE_CONTEXT+="    \n"
    LARGE_CONTEXT+="    def add_user(self, username, password):\n"
    LARGE_CONTEXT+="        query = f'INSERT INTO users (username, password) VALUES (\"{username}\", \"{password}\")'\n"
    LARGE_CONTEXT+="        self.db_connection.execute(query)\n"
    LARGE_CONTEXT+="        return True\n\n"
    LARGE_CONTEXT+="Please provide a comprehensive review with specific recommendations."
    
    START_TIME=$(date +%s.%N)
    
    RESPONSE=$(curl -s "$API_URL/chat/completions" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$MODEL_ID\",
            \"messages\": [{\"role\": \"user\", \"content\": \"$LARGE_CONTEXT\"}],
            \"max_tokens\": 300,
            \"temperature\": 0.5
        }")
    
    END_TIME=$(date +%s.%N)
    
    if echo "$RESPONSE" | jq -e '.choices' > /dev/null 2>&1; then
        DURATION=$(echo "$END_TIME - $START_TIME" | bc)
        PROMPT_TOKENS=$(echo "$RESPONSE" | jq -r '.usage.prompt_tokens')
        COMPLETION_TOKENS=$(echo "$RESPONSE" | jq -r '.usage.completion_tokens')
        
        TOKENS_PER_SECOND=$(echo "scale=2; $COMPLETION_TOKENS / $DURATION" | bc)
        
        echo "Large context test results:"
        echo "Duration: ${DURATION}s"
        echo "Prompt tokens: $PROMPT_TOKENS"
        echo "Completion tokens: $COMPLETION_TOKENS"
        echo "Generation speed: ${TOKENS_PER_SECOND} tokens/second"
        
        if [ "$PROMPT_TOKENS" -gt 500 ]; then
            echo -e "${GREEN}✅ Successfully handled large context ($PROMPT_TOKENS tokens)${NC}"
        else
            echo -e "${YELLOW}⚠️  Context may not have been as large as expected${NC}"
        fi
        
        echo ""
        echo "Response preview:"
        echo "$RESPONSE" | jq -r '.choices[0].message.content' | head -c 300
        echo "..."
    else
        echo -e "${RED}❌ Large context test failed${NC}"
        echo "Response: $RESPONSE"
    fi
    echo ""
}

# Test 4: Concurrent Requests
test_concurrent_requests() {
    echo -e "${CYAN}=== Test 4: Concurrent Request Handling ===${NC}"
    echo "Testing 3 concurrent requests..."
    
    # Create background jobs for concurrent requests
    for i in {1..3}; do
        (
            START_TIME=$(date +%s.%N)
            RESPONSE=$(curl -s "$API_URL/chat/completions" \
                -H "Authorization: Bearer $API_KEY" \
                -H "Content-Type: application/json" \
                -d "{
                    \"model\": \"$MODEL_ID\",
                    \"messages\": [{\"role\": \"user\", \"content\": \"Request $i: Write a brief explanation of HTTP status codes.\"}],
                    \"max_tokens\": 50
                }")
            END_TIME=$(date +%s.%N)
            
            DURATION=$(echo "$END_TIME - $START_TIME" | bc)
            if echo "$RESPONSE" | jq -e '.choices' > /dev/null 2>&1; then
                TOKENS=$(echo "$RESPONSE" | jq -r '.usage.completion_tokens')
                echo "Request $i: ${DURATION}s, $TOKENS tokens"
            else
                echo "Request $i: FAILED"
            fi
        ) &
    done
    
    # Wait for all background jobs
    wait
    echo -e "${GREEN}✅ Concurrent request test completed${NC}"
    echo ""
}

# Test 5: Streaming Performance
test_streaming() {
    echo -e "${CYAN}=== Test 5: Streaming Performance ===${NC}"
    echo "Testing streaming response..."
    
    echo "Streaming response preview:"
    curl -N "$API_URL/chat/completions" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "'"$MODEL_ID"'",
            "messages": [{"role": "user", "content": "Count from 1 to 10 with brief explanations."}],
            "stream": true,
            "max_tokens": 100
        }' 2>/dev/null | head -20
    
    echo -e "\n${GREEN}✅ Streaming test completed${NC}"
    echo ""
}

# Test 6: Error Handling
test_error_handling() {
    echo -e "${CYAN}=== Test 6: Error Handling ===${NC}"
    echo "Testing API error responses..."
    
    # Test with invalid model
    echo "Testing invalid model name..."
    RESPONSE=$(curl -s "$API_URL/chat/completions" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "invalid-model",
            "messages": [{"role": "user", "content": "Hello"}],
            "max_tokens": 10
        }')
    
    if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
        ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error.message // .error')
        echo -e "${GREEN}✅ Proper error handling: $ERROR_MSG${NC}"
    else
        echo -e "${YELLOW}⚠️  Unexpected response to invalid model${NC}"
    fi
    
    # Test with too many tokens
    echo ""
    echo "Testing token limit..."
    RESPONSE=$(curl -s "$API_URL/chat/completions" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$MODEL_ID\",
            \"messages\": [{\"role\": \"user\", \"content\": \"Write a very long essay.\"}],
            \"max_tokens\": 999999
        }")
    
    if echo "$RESPONSE" | jq -e '.choices' > /dev/null 2>&1; then
        ACTUAL_TOKENS=$(echo "$RESPONSE" | jq -r '.usage.completion_tokens')
        echo -e "${GREEN}✅ Token limit handled properly (generated: $ACTUAL_TOKENS tokens)${NC}"
    elif echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Token limit error handled properly${NC}"
    else
        echo -e "${YELLOW}⚠️  Unexpected response to high token request${NC}"
    fi
    echo ""
}

# Main execution
main() {
    if ! check_api_availability; then
        echo "API not available. Please start vLLM server first."
        exit 1
    fi
    
    echo -e "${BLUE}Starting comprehensive performance test suite...${NC}"
    echo "This will take several minutes to complete."
    echo ""
    
    test_basic_response_time
    test_token_generation_speed
    test_large_context
    test_concurrent_requests
    test_streaming
    test_error_handling
    
    echo -e "${GREEN}=== Performance Test Suite Completed ===${NC}"
    echo ""
    echo "Summary:"
    echo "• Expected performance: ~75 tokens/sec, <1s response time"
    echo "• Test results should be compared against these benchmarks"
    echo "• Any significant deviations may indicate configuration issues"
    echo ""
    echo "For troubleshooting, run: ./scripts/troubleshoot-vllm.sh"
}

# Run tests
main "$@"