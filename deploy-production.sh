#!/bin/bash

# reminders-api Production Deployment Script
# This script builds and deploys the reminders-api to a remote server

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

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] <remote_host>"
    echo
    echo "Deploy reminders-api to a remote server"
    echo
    echo "Arguments:"
    echo "  remote_host    SSH hostname or user@hostname"
    echo
    echo "Options:"
    echo "  -p, --port PORT        Remote port for SSH (default: 22)"
    echo "  -k, --key KEYFILE      SSH private key file"
    echo "  -d, --dest PATH        Remote destination path (default: ~/.local/bin/)"
    echo "  -t, --token TOKEN      API token to use (will generate if not provided)"
    echo "  -h, --host HOST        API host to bind to (default: 127.0.0.1)"
    echo "  --port-api PORT        API port (default: 8080)"
    echo "  --no-build             Skip building, use existing binary"
    echo "  --no-install           Skip service installation"
    echo "  --help                 Show this help message"
    echo
    echo "Examples:"
    echo "  $0 user@server.example.com"
    echo "  $0 -k ~/.ssh/id_rsa -d /usr/local/bin/ server.example.com"
    echo "  $0 --token abc123 --no-build user@server.example.com"
}

# Default values
SSH_PORT=22
SSH_KEY=""
REMOTE_DEST="~/.local/bin/"
API_TOKEN=""
API_HOST="127.0.0.1"
API_PORT=8080
NO_BUILD=false
NO_INSTALL=false
REMOTE_HOST=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--port)
            SSH_PORT="$2"
            shift 2
            ;;
        -k|--key)
            SSH_KEY="$2"
            shift 2
            ;;
        -d|--dest)
            REMOTE_DEST="$2"
            shift 2
            ;;
        -t|--token)
            API_TOKEN="$2"
            shift 2
            ;;
        -h|--host)
            API_HOST="$2"
            shift 2
            ;;
        --port-api)
            API_PORT="$2"
            shift 2
            ;;
        --no-build)
            NO_BUILD=true
            shift
            ;;
        --no-install)
            NO_INSTALL=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            if [[ -z "$REMOTE_HOST" ]]; then
                REMOTE_HOST="$1"
            else
                print_error "Multiple remote hosts specified"
                exit 1
            fi
            shift
            ;;
    esac
done

# Check if remote host is provided
if [[ -z "$REMOTE_HOST" ]]; then
    print_error "Remote host is required"
    show_usage
    exit 1
fi

# Function to build the production binary
build_production() {
    print_status "Building production reminders-api..."
    
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

# Function to generate API token
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

# Function to create SSH command
ssh_cmd() {
    local cmd="$1"
    local ssh_args=""
    
    if [[ -n "$SSH_KEY" ]]; then
        ssh_args="-i $SSH_KEY"
    fi
    
    if [[ "$SSH_PORT" != "22" ]]; then
        ssh_args="$ssh_args -p $SSH_PORT"
    fi
    
    ssh $ssh_args "$REMOTE_HOST" "$cmd"
}

# Function to copy file to remote
scp_cmd() {
    local local_file="$1"
    local remote_file="$2"
    local scp_args=""
    
    if [[ -n "$SSH_KEY" ]]; then
        scp_args="-i $SSH_KEY"
    fi
    
    if [[ "$SSH_PORT" != "22" ]]; then
        scp_args="$scp_args -P $SSH_PORT"
    fi
    
    scp $scp_args "$local_file" "$REMOTE_HOST:$remote_file"
}

# Main deployment function
main() {
    print_status "Starting production deployment to $REMOTE_HOST..."
    
    # Build the binary if needed
    if [[ "$NO_BUILD" == "false" ]]; then
        BINARY_PATH=$(build_production)
        if [[ -z "$BINARY_PATH" ]]; then
            print_error "Failed to build reminders-api binary"
            exit 1
        fi
        print_success "Built reminders-api binary: $BINARY_PATH"
    else
        # Find existing binary
        BINARY_PATH=$(find .build/apple/Products/Release/reminders-api 2>/dev/null || echo "")
        if [[ -z "$BINARY_PATH" || ! -f "$BINARY_PATH" ]]; then
            print_error "No existing binary found. Use --no-build=false to build one."
            exit 1
        fi
        print_success "Using existing binary: $BINARY_PATH"
    fi
    
    # Generate API token if not provided
    if [[ -z "$API_TOKEN" ]]; then
        API_TOKEN=$(generate_token)
        print_success "Generated API token: $API_TOKEN"
    else
        print_success "Using provided API token"
    fi
    
    # Test SSH connection
    print_status "Testing SSH connection..."
    if ! ssh_cmd "echo 'SSH connection successful'"; then
        print_error "Failed to connect to $REMOTE_HOST"
        exit 1
    fi
    print_success "SSH connection successful"
    
    # Create remote directory
    print_status "Creating remote directory..."
    ssh_cmd "mkdir -p $REMOTE_DEST"
    
    # Copy binary to remote
    print_status "Copying binary to remote server..."
    REMOTE_BINARY_PATH="$REMOTE_DEST/reminders-api"
    if [[ "$REMOTE_DEST" == *"/" ]]; then
        REMOTE_BINARY_PATH="${REMOTE_DEST}reminders-api"
    fi
    
    scp_cmd "$BINARY_PATH" "$REMOTE_BINARY_PATH"
    print_success "Binary copied to $REMOTE_HOST:$REMOTE_BINARY_PATH"
    
    # Make binary executable
    print_status "Making binary executable..."
    ssh_cmd "chmod +x $REMOTE_BINARY_PATH"
    
    # Install service if requested
    if [[ "$NO_INSTALL" == "false" ]]; then
        print_status "Installing service on remote server..."
        
        # Copy install script to remote
        scp_cmd "install-service.sh" "/tmp/install-service.sh"
        ssh_cmd "chmod +x /tmp/install-service.sh"
        
        # Create a temporary plist with the correct values
        ssh_cmd "cat > /tmp/reminders-api-deploy.plist << 'EOF'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>com.reminders.api</string>

    <key>ProgramArguments</key>
    <array>
        <string>$REMOTE_BINARY_PATH</string>
        <string>--auth-required</string>
        <string>--token</string>
        <string>$API_TOKEN</string>
        <string>--host</string>
        <string>$API_HOST</string>
        <string>--port</string>
        <string>$API_PORT</string>
    </array>

    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>

    <key>WorkingDirectory</key>
    <string>~</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>~</string>
        <key>USER</key>
        <string>\$(whoami)</string>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>LANG</key>
        <string>en_US.UTF-8</string>
    </dict>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/tmp/reminders-api.out</string>

    <key>StandardErrorPath</key>
    <string>/tmp/reminders-api.err</string>

    <key>com.apple.security.app-sandbox</key>
    <false/>
    
    <key>com.apple.security.automation.apple-events</key>
    <true/>

    <key>NSRemindersUsageDescription</key>
    <string>This app needs access to Reminders to provide API access to your todos.</string>
</dict>
</plist>
EOF"
        
        # Install the service
        ssh_cmd "cp /tmp/reminders-api-deploy.plist ~/Library/LaunchAgents/com.reminders.api.plist"
        ssh_cmd "launchctl bootout gui/\$(id -u) com.reminders.api 2>/dev/null || true"
        ssh_cmd "launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.reminders.api.plist"
        ssh_cmd "launchctl enable gui/\$(id -u)/com.reminders.api"
        ssh_cmd "launchctl kickstart -kp gui/\$(id -u)/com.reminders.api"
        
        print_success "Service installed and started"
    fi
    
    # Display deployment summary
    echo
    print_success "Deployment completed successfully!"
    echo
    echo "Deployment Summary:"
    echo "  - Remote Host: $REMOTE_HOST"
    echo "  - Binary Path: $REMOTE_BINARY_PATH"
    echo "  - API Endpoint: http://$API_HOST:$API_PORT"
    echo "  - API Token: $API_TOKEN"
    echo
    echo "Test the deployment:"
    echo "  curl -H \"Authorization: Bearer $API_TOKEN\" http://$API_HOST:$API_PORT/lists"
    echo
    echo "View logs:"
    echo "  ssh $REMOTE_HOST 'tail -f /tmp/reminders-api.out /tmp/reminders-api.err'"
    echo
    echo "Manage service:"
    echo "  ssh $REMOTE_HOST 'launchctl print gui/\$(id -u) | grep reminders'"
    echo "  ssh $REMOTE_HOST 'launchctl bootout gui/\$(id -u) com.reminders.api'"
    echo "  ssh $REMOTE_HOST 'launchctl kickstart -kp gui/\$(id -u)/com.reminders.api'"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "This script should not be run as root."
    print_error "Please run as a regular user."
    exit 1
fi

# Run main function
main "$@"
