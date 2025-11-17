#!/bin/bash

# reminders-api Service Installation Script
# This script installs the reminders-api as a macOS LaunchAgent service

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

# Usage helper
usage() {
    cat <<'EOF'
Usage: ./install-service.sh [options]

Options:
  --token <value>     Use the provided API token instead of generating a new one.
  --reuse-token       Reuse the token from an existing LaunchAgent plist (if present).
  --host <value>      Host interface for reminders-api (default: 127.0.0.1).
  --port <value>      Port for reminders-api (default: 8080).
  -h, --help          Show this help message.

By default a fresh token is generated each run. Supplying --token overrides all other token behavior,
and --reuse-token falls back to generating a new token if none can be read.
EOF
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

extract_existing_token() {
    local plist_path="$1"
    [[ -f "$plist_path" ]] || return 1

    if ! command_exists plutil || ! command_exists python3; then
        return 1
    fi

    local token
    token=$(plutil -extract ProgramArguments json -o - "$plist_path" 2>/dev/null | python3 - <<'PY'
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for idx, value in enumerate(data):
    if value == "--token" and idx + 1 < len(data):
        print(data[idx + 1])
        sys.exit(0)
sys.exit(1)
PY
) || return 1

    if [[ -n "$token" ]]; then
        echo "$token"
        return 0
    fi

    return 1
}

# CLI options / defaults
USER_SUPPLIED_TOKEN=""
REUSE_TOKEN=false
SERVICE_HOST="127.0.0.1"
SERVICE_PORT="8080"

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

# Function to build reminders-api if not found
build_reminders_api() {
    print_status "Building reminders-api..."
    
    if [[ -f "Package.swift" ]]; then
        if command_exists swift; then
            swift build --configuration release
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
    print_status "User home directory: $USER_HOME"
    
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
    
    # Create LaunchAgents directory if it doesn't exist and determine plist path
    LAUNCH_AGENTS_DIR="$USER_HOME/Library/LaunchAgents"
    mkdir -p "$LAUNCH_AGENTS_DIR"
    PLIST_FILE="$LAUNCH_AGENTS_DIR/com.billcromie.reminders-cli.api.plist"

    if $REUSE_TOKEN && [[ ! -f "$PLIST_FILE" ]]; then
        print_warning "--reuse-token was specified but no existing LaunchAgent plist was found; generating a new token."
    fi

    # Generate or reuse API token
    local token_source=""
    if [[ -n "$USER_SUPPLIED_TOKEN" ]]; then
        API_TOKEN="$USER_SUPPLIED_TOKEN"
        token_source="provided via --token"
    elif $REUSE_TOKEN && [[ -f "$PLIST_FILE" ]]; then
        if API_TOKEN=$(extract_existing_token "$PLIST_FILE"); then
            token_source="reused token from existing plist"
        else
            print_warning "Unable to extract token from existing plist; generating a new one."
        fi
    fi

    if [[ -z "$API_TOKEN" ]]; then
        API_TOKEN=$(generate_token)
        token_source="generated new token"
    fi

    print_success "API token (${token_source}): $API_TOKEN"
    
    # Create logs directory
    LOGS_DIR="$USER_HOME/Library/Logs/reminders-api"
    mkdir -p "$LOGS_DIR"
    print_status "Created logs directory: $LOGS_DIR"
    
    # Generate plist content with proper TCC configuration
    cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.billcromie.reminders-cli.api</string>

    <key>ProgramArguments</key>
    <array>
        <string>$REMINDERS_API_PATH</string>
        <string>--auth-required</string>
        <string>--token</string>
        <string>$API_TOKEN</string>
        <string>--host</string>
        <string>$SERVICE_HOST</string>
        <string>--port</string>
        <string>$SERVICE_PORT</string>
    </array>

    <!-- CRITICAL: Run in GUI session for TCC permissions -->
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>

    <!-- CRITICAL: Set working directory -->
    <key>WorkingDirectory</key>
    <string>$USER_HOME</string>

    <!-- CRITICAL: Set environment variables with proper PATH -->
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>$USER_HOME</string>
        <key>USER</key>
        <string>$CURRENT_USER</string>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>LANG</key>
        <string>en_US.UTF-8</string>
    </dict>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <!-- CRITICAL: Logs in /tmp for easy debugging -->
    <key>StandardOutPath</key>
    <string>/tmp/reminders-api.out</string>

    <key>StandardErrorPath</key>
    <string>/tmp/reminders-api.err</string>

    <!-- CRITICAL: Security entitlements for EventKit access -->
    <key>com.apple.security.app-sandbox</key>
    <false/>
    
    <key>com.apple.security.automation.apple-events</key>
    <true/>

    <key>NSRemindersUsageDescription</key>
    <string>This app needs access to Reminders to provide API access to your todos.</string>
</dict>
</plist>
EOF

    print_success "Created plist file: $PLIST_FILE"
    
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
    if ! $REMINDERS_API_PATH --help >/dev/null 2>&1; then
        print_warning "Could not trigger permission prompt automatically."
        print_warning "Please run the following command manually and grant permission:"
        print_warning "$REMINDERS_API_PATH --help"
    else
        print_success "Permission prompt triggered successfully."
    fi
    
    echo
    read -p "Press Enter after you have granted Reminders access (or if you've already done so)..."
    
    # Load the service using proper GUI session commands
    print_status "Loading the service into GUI session..."
    
    # Get the current user ID
    USER_ID=$(id -u)
    
    # Bootout any existing service
    launchctl bootout "gui/$USER_ID" com.billcromie.reminders-cli.api 2>/dev/null || true
    
    # Bootstrap the service into the GUI session
    launchctl bootstrap "gui/$USER_ID" "$PLIST_FILE"
    
    # Enable the service
    launchctl enable "gui/$USER_ID/com.billcromie.reminders-cli.api"
    
    # Kickstart the service
    launchctl kickstart -kp "gui/$USER_ID/com.billcromie.reminders-cli.api"
    
    # Wait a moment for the service to start
    sleep 3
    
    # Check if service is running
    if launchctl print "gui/$USER_ID" | grep -q "com.billcromie.reminders-cli.api"; then
        print_success "Service loaded successfully into GUI session!"
    else
        print_warning "Service may not have loaded properly. Check logs for details."
    fi
    
    # Display important information
    echo
    print_success "Installation completed!"
    echo
    echo "Service Details:"
    echo "  - Service Name: com.billcromie.reminders-cli.api"
    echo "  - API Endpoint: http://$SERVICE_HOST:$SERVICE_PORT"
    echo "  - API Token: $API_TOKEN"
    echo "  - Logs Directory: $LOGS_DIR"
    echo
    echo "Management Commands:"
    echo "  - Check status: launchctl print gui/\$(id -u) | grep reminders"
    echo "  - View logs: tail -f /tmp/reminders-api.out /tmp/reminders-api.err"
    echo "  - Stop service: launchctl bootout gui/\$(id -u) com.billcromie.reminders-cli.api"
    echo "  - Start service: launchctl kickstart -kp gui/\$(id -u)/com.billcromie.reminders-cli.api"
    echo "  - Restart service: launchctl bootout gui/\$(id -u) com.billcromie.reminders-cli.api && launchctl bootstrap gui/\$(id -u) $PLIST_FILE"
    echo
    echo "Test the API:"
    echo "  curl -H \"Authorization: Bearer $API_TOKEN\" http://$SERVICE_HOST:$SERVICE_PORT/lists"
    echo
    print_warning "IMPORTANT: You may need to grant Reminders access when the service first starts."
    print_warning "Check the logs if you encounter permission issues."
}

# Parse command-line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --token)
            shift
            if [[ -z "$1" ]]; then
                print_error "--token requires a value"
                usage
                exit 1
            fi
            USER_SUPPLIED_TOKEN="$1"
            ;;
        --reuse-token)
            REUSE_TOKEN=true
            ;;
        --host)
            shift
            if [[ -z "$1" ]]; then
                print_error "--host requires a value"
                usage
                exit 1
            fi
            SERVICE_HOST="$1"
            ;;
        --port)
            shift
            if [[ -z "$1" ]]; then
                print_error "--port requires a value"
                usage
                exit 1
            fi
            if [[ ! "$1" =~ ^[0-9]+$ ]]; then
                print_error "--port must be numeric"
                exit 1
            fi
            SERVICE_PORT="$1"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "This script should not be run as root."
    print_error "Please run as a regular user to install the service in your user context."
    exit 1
fi

# Run main function
main "$@"
