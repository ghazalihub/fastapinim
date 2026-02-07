#!/bin/bash
export PATH=$HOME/.nimble/bin:$PATH
cd nimfastapi
nim c -p:src --mm:orc --threads:on example.nim
./example run &
SERVER_PID=$!
sleep 2

# Test root
echo "Testing /"
curl -s http://localhost:8001/ | grep "Hello World"
if [ $? -eq 0 ]; then echo "Root Success"; else echo "Root Failed"; kill $SERVER_PID; exit 1; fi

# Test path and query parameter
echo "Testing /items/42?q=nim"
curl -s "http://localhost:8001/items/42?q=nim" | grep '"item_id":42' | grep '"q":"nim"'
if [ $? -eq 0 ]; then echo "Path/Query Success"; else echo "Path/Query Failed"; kill $SERVER_PID; exit 1; fi

# Test dependency injection
echo "Testing /users/jules?token=jessica"
curl -s "http://localhost:8001/users/jules?token=jessica" | grep '"user_id":"jules"' | grep '"token":"jessica"'
if [ $? -eq 0 ]; then echo "Dependency Injection Success"; else echo "Dependency Injection Failed"; kill $SERVER_PID; exit 1; fi

# Test middleware header
echo "Testing Middleware Header"
curl -v -s http://localhost:8001/ 2>&1 | grep -i "X-Process-Time"
if [ $? -eq 0 ]; then echo "Middleware Success"; else echo "Middleware Failed"; kill $SERVER_PID; exit 1; fi

# Test Background Tasks
echo "Testing /background"
curl -s http://localhost:8001/background | grep "Background task scheduled"
if [ $? -eq 0 ]; then echo "Background Tasks Success"; else echo "Background Tasks Failed"; kill $SERVER_PID; exit 1; fi
sleep 2 # Wait for background task to finish and print

# Test OpenAPI
echo "Testing /openapi.json"
curl -s http://localhost:8001/openapi.json | grep "Comprehensive NimFastAPI"
if [ $? -eq 0 ]; then echo "OpenAPI Success"; else echo "OpenAPI Failed"; kill $SERVER_PID; exit 1; fi

kill $SERVER_PID
echo "All tests passed!"
