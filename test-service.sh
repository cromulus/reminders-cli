#!/bin/bash

# reminders-api Service Test Script
# This script helps diagnose common issues with the reminders-api service

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Main test function
main() {
    print_status "Testing reminders-api service configuration..."
    echo
    
    # Get user information
    CURRENT_USER=$(whoami)
    USER_HOME=$(eval echo ~$CURRENT_USER)
    USER_ID=$(id -u)
    
    print_status "User: $CURRENT_USER (ID: $USER_ID)"
    print_status "Home: $USER_HOME"
    echo
    
    # Test 1: Check if service is loaded
    print_status "1. Checking if service is loaded..."
    if launchctl print "gui/$USER_ID" | grep -q "com.reminders.api"; then
        print_success "Service is loaded in GUI session"
    else
        print_error "Service is NOT loaded in GUI session"
        echo "  Run: launchctl bootstrap gui/$USER_ID ~/Library/LaunchAgents/com.reminders.api.plist"
    fi
    echo
    
    # Test 2: Check if service is running
    print_status "2. Checking if service is running..."
    if launchctl print "gui/$USER_ID" | grep -A5 "com.reminders.api" | grep -q "state = running"; then
        print_success "Service is running"
    else
        print_warning "Service is loaded but not running"
        echo "  Run: launchctl kickstart -kp gui/$USER_ID/com.reminders.api"
    fi
    echo
    
    # Test 3: Check logs
    print_status "3. Checking service logs..."
    if [[ -f "/tmp/reminders-api.out" ]]; then
        print_success "Output log exists: /tmp/reminders-api.out"
        echo "  Last 5 lines:"
        tail -5 /tmp/reminders-api.out | sed 's/^/    /'
    else
        print_warning "No output log found at /tmp/reminders-api.out"
    fi
    
    if [[ -f "/tmp/reminders-api.err" ]]; then
        print_success "Error log exists: /tmp/reminders-api.err"
        echo "  Last 5 lines:"
        tail -5 /tmp/reminders-api.err | sed 's/^/    /'
    else
        print_warning "No error log found at /tmp/reminders-api.err"
    fi
    echo
    
    # Test 4: Check if API is responding
    print_status "4. Testing API endpoint..."
    if command_exists curl; then
        # Try to get the API token from the plist
        PLIST_FILE="$USER_HOME/Library/LaunchAgents/com.reminders.api.plist"
        if [[ -f "$PLIST_FILE" ]]; then
            # Extract token from plist (this is a simple approach)
            TOKEN=$(grep -A1 "token" "$PLIST_FILE" | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
            if [[ -n "$TOKEN" ]]; then
                print_status "Testing API with token..."
                RESPONSE=$(curl -s -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8080/lists 2>/dev/null || echo "ERROR")
                if [[ "$RESPONSE" == "ERROR" ]]; then
                    print_error "API is not responding"
                    echo "  Check if service is running and port 8080 is available"
                elif [[ "$RESPONSE" == "[]" ]]; then
                    print_warning "API is responding but returns empty list"
                    echo "  This usually means TCC permissions are not granted"
                    echo "  Run: /path/to/reminders-api --help (to trigger permission prompt)"
                else
                    print_success "API is responding with data: $RESPONSE"
                fi
            else
                print_warning "Could not extract API token from plist"
            fi
        else
            print_error "Plist file not found: $PLIST_FILE"
        fi
    else
        print_warning "curl not found, cannot test API"
    fi
    echo
    
    # Test 5: Check TCC permissions
    print_status "5. Checking TCC permissions..."
    print_status "Please check System Settings → Privacy & Security → Automation"
    print_status "Look for your reminders-api binary and ensure 'Reminders' is enabled"
    echo
    
    # Test 6: Check if binary exists and is executable
    print_status "6. Checking reminders-api binary..."
    BINARY_PATH=""
    if [[ -f "$USER_HOME/.local/bin/reminders-api" ]]; then
        BINARY_PATH="$USER_HOME/.local/bin/reminders-api"
    elif command_exists reminders-api; then
        BINARY_PATH=$(which reminders-api)
    fi
    
    if [[ -n "$BINARY_PATH" ]]; then
        print_success "Binary found: $BINARY_PATH"
        if [[ -x "$BINARY_PATH" ]]; then
            print_success "Binary is executable"
        else
            print_error "Binary is not executable"
        fi
    else
        print_error "reminders-api binary not found"
        echo "  Make sure you have built and installed the reminders-api"
    fi
    echo
    
    # Summary
    print_status "=== SUMMARY ==="
    echo "If you see errors above, here are the most common fixes:"
    echo
    echo "1. Service not loaded:"
    echo "   launchctl bootstrap gui/$USER_ID ~/Library/LaunchAgents/com.reminders.api.plist"
    echo
    echo "2. Service not running:"
    echo "   launchctl kickstart -kp gui/$USER_ID/com.reminders.api"
    echo
    echo "3. Empty API response (TCC permissions):"
    echo "   $BINARY_PATH --help  # Grant permission when prompted"
    echo
    echo "4. View logs:"
    echo "   tail -f /tmp/reminders-api.out /tmp/reminders-api.err"
    echo
    echo "5. Full restart:"
    echo "   launchctl bootout gui/$USER_ID com.reminders.api"
    echo "   launchctl bootstrap gui/$USER_ID ~/Library/LaunchAgents/com.reminders.api.plist"
    echo "   launchctl kickstart -kp gui/$USER_ID/com.reminders.api"
}

# Run main function
main "$@"

