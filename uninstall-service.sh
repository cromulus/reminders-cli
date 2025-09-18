#!/bin/bash

# reminders-api Service Uninstallation Script
# This script removes the reminders-api LaunchAgent service

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

# Main uninstallation function
main() {
    print_status "Starting reminders-api service uninstallation..."
    
    # Get user information
    CURRENT_USER=$(whoami)
    USER_HOME=$(eval echo ~$CURRENT_USER)
    PLIST_FILE="$USER_HOME/Library/LaunchAgents/com.billcromie.reminders-cli.api.plist"
    LOGS_DIR="$USER_HOME/Library/Logs/reminders-api"
    
    print_status "Uninstalling for user: $CURRENT_USER"
    
    # Get user ID for GUI session
    USER_ID=$(id -u)
    
    # Check if service is running
    if launchctl print "gui/$USER_ID" | grep -q "com.billcromie.reminders-cli.api"; then
        print_status "Stopping the service..."
        launchctl bootout "gui/$USER_ID" com.billcromie.reminders-cli.api 2>/dev/null || true
        print_success "Service stopped"
    else
        print_warning "Service is not currently running"
    fi
    
    # Remove plist file
    if [[ -f "$PLIST_FILE" ]]; then
        rm -f "$PLIST_FILE"
        print_success "Removed plist file: $PLIST_FILE"
    else
        print_warning "Plist file not found: $PLIST_FILE"
    fi
    
    # Ask about removing logs
    if [[ -d "$LOGS_DIR" ]]; then
        echo
        read -p "Do you want to remove the logs directory ($LOGS_DIR)? [y/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$LOGS_DIR"
            print_success "Removed logs directory: $LOGS_DIR"
        else
            print_status "Keeping logs directory: $LOGS_DIR"
        fi
    fi
    
    # Verify removal
    if ! launchctl print "gui/$USER_ID" | grep -q "com.billcromie.reminders-cli.api"; then
        print_success "Service successfully uninstalled!"
    else
        print_warning "Service may still be running. Try restarting your system."
    fi
    
    echo
    print_success "Uninstallation completed!"
    echo
    echo "The reminders-api service has been removed from your system."
    echo "If you want to reinstall it, run: ./install-service.sh"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "This script should not be run as root."
    print_error "Please run as a regular user to uninstall the service from your user context."
    exit 1
fi

# Run main function
main "$@"
