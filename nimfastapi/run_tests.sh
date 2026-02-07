#!/bin/bash
export PATH=$HOME/.nimble/bin:$PATH
cd nimfastapi
nim c -p:src --mm:orc --threads:on example.nim
./example run &
SERVER_PID=$!
sleep 2

# Test root
echo "Testing /"
curl -s http://localhost:8001/ | grep "Welcome to NimFastAPI"
if [ $? -eq 0 ]; then echo "Root Success"; else echo "Root Failed"; kill $SERVER_PID; exit 1; fi

# Test object decoding from body
echo "Testing POST /items"
curl -s -X POST http://localhost:8001/items -H "Content-Type: application/json" -d '{"name": "test-item", "price": 10.5, "is_offer": true}' | grep '"name":"test-item"' | grep '"status":"created"'
if [ $? -eq 0 ]; then echo "Object Decoding Success"; else echo "Object Decoding Failed"; kill $SERVER_PID; exit 1; fi

# Test DI and security (Failure)
echo "Testing DI/Security Failure"
curl -s http://localhost:8001/users/1 | grep "Invalid API Key"
if [ $? -eq 0 ]; then echo "Security Failure Test Success"; else echo "Security Failure Test Failed"; kill $SERVER_PID; exit 1; fi

# Test DI and security (Success)
echo "Testing DI/Security Success"
curl -s http://localhost:8001/users/123 -H "X-API-Key: secret-token" | grep '"user_id":123' | grep '"authorized_by":"secret-token"'
if [ $? -eq 0 ]; then echo "Security Success Test Success"; else echo "Security Success Test Failed"; kill $SERVER_PID; exit 1; fi

# Test Exceptions
echo "Testing Exception Handling"
curl -s http://localhost:8001/error | grep "I am a teapot"
if [ $? -eq 0 ]; then echo "Exception Handling Success"; else echo "Exception Handling Failed"; kill $SERVER_PID; exit 1; fi

# Test Background Tasks
echo "Testing Background Tasks"
curl -s -X POST http://localhost:8001/send-notification/test@example.com | grep "Notification scheduled"
if [ $? -eq 0 ]; then echo "Background Tasks Success"; else echo "Background Tasks Failed"; kill $SERVER_PID; exit 1; fi
sleep 1

kill $SERVER_PID
echo "All comprehensive tests passed!"
