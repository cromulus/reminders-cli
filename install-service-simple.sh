#!/bin/bash

# reminders-api Service Installation Script
# This script installs reminders-api as a startup service using a simple startup script

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

# Function to generate a secure token
generate_token() {
    if command_exists openssl; then
        openssl rand -hex 32
    elif command_exists python3; then
        python3 -c "import secrets; print(secrets.token_hex(32))"
    else
        # Fallback to a simple random string
        date +%s | shasum -a 256 | cut -d' ' -f1
    fi
}

# Function to get current user info
get_user_info() {
    CURRENT_USER=$(whoami)
    USER_HOME=$(eval echo ~$CURRENT_USER)
    echo "$CURRENT_USER|$USER_HOME"
}

# Function to find reminders-api binary
find_reminders_api() {
    local possible_paths=(
        "./.build/apple/Products/Release/reminders-api"
        "./.build/debug/reminders-api"
        "./reminders-api"
        "/usr/local/bin/reminders-api"
        "$HOME/.local/bin/reminders-api"
        "$(which reminders-api 2>/dev/null)"
    )
    
    for path in "${possible_paths[@]}"; do
        if [[ -f "$path" && -x "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

# Function to build reminders-api binary
build_reminders_api() {
    print_status "Building reminders-api..."
    
    if [[ -f "Package.swift" ]]; then
        if command_exists swift; then
            make build-api
            if [[ -f ".build/apple/Products/Release/reminders-api" ]]; then
                echo ".build/apple/Products/Release/reminders-api"
                return 0
            fi
        else
            print_error "Swift not found. Please install Xcode or Swift toolchain."
            exit 1
        fi
    else
        print_error "Package.swift not found. Please run this script from the reminders-cli directory."
        exit 1
    fi
    
    return 1
}

# Main installation function
main() {
    print_status "Starting reminders-api service installation..."
    
    # Get user information
    IFS='|' read -r CURRENT_USER USER_HOME <<< "$(get_user_info)"
    print_status "Installing for user: $CURRENT_USER"
    print_status "User home directory: [REDACTED]"
    
    # Find or build reminders-api binary
    REMINDERS_API_PATH=$(find_reminders_api)
    if [[ -z "$REMINDERS_API_PATH" ]]; then
        print_warning "reminders-api binary not found. Building production version..."
        REMINDERS_API_PATH=$(build_reminders_api)
        if [[ -z "$REMINDERS_API_PATH" ]]; then
            print_error "Failed to find or build reminders-api binary."
            print_error "Please ensure you have built the project or installed reminders-api."
            exit 1
        fi
    else
        print_success "Found existing reminders-api binary: $REMINDERS_API_PATH"
    fi
    
    # Convert to absolute path
    REMINDERS_API_PATH=$(realpath "$REMINDERS_API_PATH")
    print_success "Found reminders-api at: $REMINDERS_API_PATH"
    
    # Generate API token
    API_TOKEN=$(generate_token)
    print_success "Generated API token: $API_TOKEN"
    
    # Create logs directory
    LOGS_DIR="$USER_HOME/Library/Logs/reminders-api"
    mkdir -p "$LOGS_DIR"
    print_status "Created logs directory: $LOGS_DIR"
    
    # Create startup script
    STARTUP_SCRIPT="$USER_HOME/start-reminders-api-service.sh"
    print_status "Creating startup script: $STARTUP_SCRIPT"
    
    cat > "$STARTUP_SCRIPT" << EOF
#!/bin/bash
# Startup script for reminders-api service
# This ensures the service starts after reboots

# Kill any existing processes
pkill -f reminders-api

# Wait a moment
sleep 2

# Start the service
nohup $REMINDERS_API_PATH --auth-required --token $API_TOKEN --host 127.0.0.1 --port 8080 > /tmp/reminders-api-service.out 2> /tmp/reminders-api-service.err &

echo "Reminders API service started"
EOF

    chmod +x "$STARTUP_SCRIPT"
    print_success "Created startup script: $STARTUP_SCRIPT"
    
    # Handle TCC permissions
    print_status "Setting up TCC permissions..."
    print_warning "IMPORTANT: You need to grant Reminders access to the reminders-api binary."
    print_warning "This is required for the service to access your reminders data."
    echo
    print_status "To grant permissions:"
    echo "1. The service will attempt to start and trigger a permission prompt"
    echo "2. If no prompt appears, run this command manually:"
    echo "   $REMINDERS_API_PATH --help"
    echo "3. When prompted, click 'Allow' to grant Reminders access"
    echo "4. The service will then be able to access your reminders"
    echo
    
    # Try to trigger the permission prompt by running the binary once
    print_status "Triggering permission prompt..."
    if ! "$REMINDERS_API_PATH" --help >/dev/null 2>&1; then
        print_warning "Could not trigger permission prompt automatically."
        print_warning "Please run the following command manually and grant permission:"
        print_warning "$REMINDERS_API_PATH --help"
    else
        print_success "Permission prompt triggered successfully."
    fi
    
    echo
    read -p "Press Enter after you have granted Reminders access (or if you've already done so)..."
    
    # Start the service
    print_status "Starting reminders-api service..."
    "$STARTUP_SCRIPT"
    
    # Wait a moment for the service to start
    sleep 3
    
    # Check if service is running
    if pgrep -f "reminders-api" >/dev/null; then
        print_success "Service started successfully!"
    else
        print_warning "Service may not have started properly. Check logs:"
        print_warning "  tail -f /tmp/reminders-api-service.out /tmp/reminders-api-service.err"
    fi
    
    # Display important information
    echo
    print_success "Installation completed!"
    echo
    echo "Service Details:"
    echo "  - Binary Path: $REMINDERS_API_PATH"
    echo "  - API Endpoint: http://127.0.0.1:8080"
    echo "  - API Token: $API_TOKEN"
    echo "  - Startup Script: $STARTUP_SCRIPT"
    echo "  - Logs: /tmp/reminders-api-service.out /tmp/reminders-api-service.err"
    echo
    echo "Management Commands:"
    echo "  - Start service: $STARTUP_SCRIPT"
    echo "  - Stop service: pkill -f reminders-api"
    echo "  - Check status: pgrep -f reminders-api"
    echo "  - View logs: tail -f /tmp/reminders-api-service.out /tmp/reminders-api-service.err"
    echo
    echo "Test the API:"
    echo "  curl -H \"Authorization: Bearer $API_TOKEN\" http://127.0.0.1:8080/lists"
    echo
    echo "To start automatically after reboots:"
    echo "  1. Go to System Preferences → Users & Groups → Login Items"
    echo "  2. Click the + button"
    echo "  3. Navigate to $STARTUP_SCRIPT"
    echo "  4. Add it to login items"
    echo
    print_warning "IMPORTANT: You may need to grant Reminders access when the service first starts."
}

# Show usage if help requested
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0"
    echo
    echo "This script installs reminders-api as a startup service."
    echo "The service will start automatically when you run the startup script."
    echo
    echo "After installation, add the startup script to your login items for automatic startup after reboots."
    exit 0
fi

# Run main function
main "$@"
