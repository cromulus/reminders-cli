#!/bin/bash
# Startup script for reminders-api service
# This ensures the service starts after reboots

# Kill any existing processes
pkill -f reminders-api

# Wait a moment
sleep 2

# Start the service
nohup /Users/bill/.local/bin/reminders-api --auth-required --token 4977ab378cca14b7f1b6938bdffdc11962fb7edaa0bd4b5744764899a4b30791 --host 127.0.0.1 --port 8080 > /tmp/reminders-api-service.out 2> /tmp/reminders-api-service.err &

echo "Reminders API service started"
