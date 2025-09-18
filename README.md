# reminders-cli

A simple CLI for interacting with OS X reminders.

## Usage:

#### Show all lists

```
$ reminders show-lists
Soon
Eventually

# Show lists with UUIDs
$ reminders show-lists --show-u-u-i-ds
Soon [5F6D3A2B-C8E7-4591-A03F-D83E2CB27591]
Eventually [3B6C4A9D-E7F8-5192-B04E-A72F3DC38692]
```

#### Show reminders on a specific list

```
$ reminders show Soon
0 Write README
1 Ship reminders-cli

# Show reminders with UUIDs
$ reminders show Soon --show-u-u-i-ds
0 Write README [UUID: F3A0B3D8-E153-4AB9-B341-0C32A9AC6C2D]
1 Ship reminders-cli [UUID: 18F92A5D-7D64-45A8-BC2F-6D1B3217A251]

# You can also use the list UUID instead of name
$ reminders show 5F6D3A2B-C8E7-4591-A03F-D83E2CB27591
0 Write README
1 Ship reminders-cli
```

#### Complete an item on a list

```
$ reminders complete Soon 0
Completed 'Write README'
$ reminders show Soon
0 Ship reminders-cli

# You can also use UUID instead of index
$ reminders complete Soon 18F92A5D-7D64-45A8-BC2F-6D1B3217A251
Completed 'Ship reminders-cli'
```

#### Undo a completed item

```
$ reminders show Soon --only-completed
0 Write README
$ reminders uncomplete Soon 0
Uncompleted 'Write README'
$ reminders show Soon
0 Write README
```

#### Edit an item on a list

```
$ reminders edit Soon 0 Some edited text
Updated reminder 'Some edited text'
$ reminders show Soon
0 Ship reminders-cli
1 Some edited text
```

#### Delete an item on a list

```
$ reminders delete Soon 0
Completed 'Write README'
$ reminders show Soon
0 Ship reminders-cli
```

#### Add a reminder to a list

```
$ reminders add Soon Contribute to open source
$ reminders add Soon Go to the grocery store --due-date "tomorrow 9am"
$ reminders add Soon Something really important --priority high
$ reminders show Soon
0: Ship reminders-cli
1: Contribute to open source
2: Go to the grocery store (in 10 hours)
3: Something really important (priority: high)
```

#### Show reminders due on or by a date

```
$ reminders show-all --due-date today
1: Contribute to open source (in 3 hours)
$ reminders show-all --due-date today --include-overdue
0: Ship reminders-cli (2 days ago)
1: Contribute to open source (in 3 hours)
$ reminders show-all --due-date 2025-02-16
1: Contribute to open source (in 3 hours)
$ reminders show Soon --due-date today --include-overdue
0: Ship reminders-cli (2 days ago)
1: Contribute to open source (in 3 hours)
```

#### See help for more examples

```
$ reminders --help
$ reminders show -h
```

## Installation:

#### With [Homebrew](http://brew.sh/)

```
$ brew install keith/formulae/reminders-cli
```

#### From GitHub releases

Download the latest release from
[here](https://github.com/keith/reminders-cli/releases)

```
$ tar -zxvf reminders.tar.gz
$ mv reminders /usr/local/bin
$ rm reminders.tar.gz
```

#### Building manually

This requires a recent Xcode installation.

```bash
# Build the CLI
$ cd reminders-cli
$ make build-release
$ cp .build/apple/Products/Release/reminders /usr/local/bin/reminders

# Build the API server
$ make build-api
$ cp .build/apple/Products/Release/reminders-api /usr/local/bin/reminders-api
```

#### Production Builds

For production deployments, use the optimized release builds:

```bash
# Build both CLI and API for production
$ make build-release build-api

# Create production packages
$ make package      # Creates reminders.tar.gz
$ make package-api  # Creates reminders-api.tar.gz
```

The production builds include:
- Universal binaries (ARM64 + x86_64)
- Optimized performance
- Debug symbols for troubleshooting
- All dependencies statically linked

## REST API Server

This project includes a REST API server that allows you to interact with your reminders via HTTP requests. This is useful for building web applications, integrating with other services, or automating reminders management.

### Installation and Setup

#### Build the API server

```bash
# Build with Swift Package Manager
$ swift build
$ ./.build/debug/reminders-api

# Or build a release version
$ make build-release
$ ./.build/apple/Products/Release/reminders-api

# Or package for distribution
$ make package-api
$ ./reminders-api
```

The server runs on `localhost:8080` by default. The first time you run it, you'll need to grant permission to access your reminders, just like with the CLI.

### Authentication

The API server supports **optional token-based authentication** by default, which can be configured as required or completely disabled.

#### Setting up authentication

1. Generate a token:
   ```bash
   $ reminders-api --generate-token
   Generated API token: abc123def456...
   Use this token as the REMINDERS_API_TOKEN environment variable or --token option
   Example: REMINDERS_API_TOKEN=abc123def456... reminders-api
   Example: reminders-api --token abc123def456...
   ```

2. Start the server with the token:
   ```bash
   # Default: authentication optional
   $ reminders-api
   
   # Using environment variable:
   $ REMINDERS_API_TOKEN=abc123def456... reminders-api
   
   # Or using command line argument:
   $ reminders-api --token abc123def456...
   
   # To require authentication for all endpoints:
   $ reminders-api --token abc123def456... --auth-required
   
   # To explicitly disable authentication:
   $ reminders-api --no-auth
   
   # Enable debug logging:
   $ reminders-api --log-level DEBUG
   ```

3. Authenticate requests using the Bearer token:
   ```bash
   $ curl -H "Authorization: Bearer abc123def456..." http://localhost:8080/lists
   ```

#### Server command-line options

```bash
$ reminders-api --help
USAGE: reminders-api [--host <host>] [--port <port>] [--token <token>] [--auth-required] [--no-auth] [--log-level <level>] [--generate-token]

OPTIONS:
  --host <host>           The hostname to bind to (default: 127.0.0.1)
  -p, --port <port>       The port to listen on (default: 8080)
  --token <token>         API authentication token (overrides REMINDERS_API_TOKEN environment variable)
  --auth-required         Require authentication for all API endpoints
  --no-auth               Explicitly disable authentication (overrides config file)
  --log-level <level>     Set log level: DEBUG, INFO, WARN, ERROR (default: INFO)
  --generate-token        Generate a new API token and exit
  -h, --help              Show help information.
```

#### Environment Variables

- `REMINDERS_API_TOKEN`: API authentication token
- `LOG_LEVEL`: Log level (DEBUG, INFO, WARN, ERROR)

### API Endpoints

#### Reminders Management

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/lists` | List all reminder lists |
| GET | `/lists/:name` | Get reminders from a specific list |
| GET | `/reminders` | Get all reminders across all lists |
| POST | `/lists/:name/reminders` | Add a new reminder to a list |
| DELETE | `/lists/:listName/reminders/:id` | Delete a reminder |
| PATCH | `/lists/:listName/reminders/:id/complete` | Mark a reminder as complete |
| PATCH | `/lists/:listName/reminders/:id/uncomplete` | Mark a reminder as incomplete |
| GET | `/search` | Search for reminders with complex filtering |

#### Webhooks

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/webhooks` | List all webhook configurations |
| GET | `/webhooks/:id` | Get a specific webhook configuration |
| POST | `/webhooks` | Create a new webhook |
| PATCH | `/webhooks/:id` | Update a webhook configuration |
| DELETE | `/webhooks/:id` | Delete a webhook configuration |
| POST | `/webhooks/:id/test` | Test a webhook by sending a test event |

### Query Parameters

- For GET requests to `/lists/:name` and `/reminders`:
  - `completed=true` - Include completed items in the results (by default, only incomplete items are returned)

### Request and Response Examples

#### GET /lists

Request:
```bash
curl http://localhost:8080/lists
```

Response:
```json
[
  "Work",
  "Personal",
  "Shopping",
  "Soon"
]
```

#### GET /lists/:name

Request:
```bash
# Get incomplete reminders from a list
curl http://localhost:8080/lists/Soon

# Include completed reminders
curl "http://localhost:8080/lists/Soon?completed=true"
```

Response:
```json
[
  {
    "creationDate": "2025-03-10T14:30:00Z",
    "dueDate": "2025-03-15T09:00:00Z",
    "id": "F3A0B3D8-E153-4AB9-B341-0C32A9AC6C2D",
    "isCompleted": false,
    "lastModifiedDate": "2025-03-10T14:30:00Z",
    "listName": "Soon",
    "notes": "Important deadline",
    "priority": 2,
    "title": "Finish project proposal"
  },
  {
    "creationDate": "2025-03-09T10:15:00Z",
    "dueDate": "2025-03-12T17:00:00Z",
    "id": "18F92A5D-7D64-45A8-BC2F-6D1B3217A251",
    "isCompleted": false,
    "lastModifiedDate": "2025-03-09T10:15:00Z",
    "listName": "Soon",
    "notes": null,
    "priority": 0,
    "title": "Buy groceries"
  }
]
```

#### GET /reminders

Request:
```bash
# Get all incomplete reminders across all lists
curl http://localhost:8080/reminders

# Get all reminders, including completed ones
curl "http://localhost:8080/reminders?completed=true"
```

### Webhook Support

The API server includes webhook support, which allows you to receive real-time notifications when reminders are created, updated, completed, uncompleted, or deleted. This is especially useful for integrating with external systems or building automation workflows.

#### How Webhooks Work

1. You register a webhook URL and specify filter criteria
2. When reminders change, the API server checks if the changed reminder matches your filter criteria
3. If it matches, the server sends a POST request to your webhook URL with details about the change

#### Webhook Payload

Webhooks deliver a JSON payload with the following structure:

```json
{
  "event": "created",
  "timestamp": "2025-03-11T15:30:45Z",
  "reminder": {
    "uuid": "F3A0B3D8-E153-4AB9-B341-0C32A9AC6C2D",
    "title": "Buy groceries",
    "notes": "Milk, eggs, bread",
    "dueDate": "2025-03-12T17:00:00Z",
    "isCompleted": false,
    "priority": 0,
    "listName": "Shopping",
    "listUUID": "5F6D3A2B-C8E7-4591-A03F-D83E2CB27591",
    "creationDate": "2025-03-11T15:30:45Z",
    "lastModifiedDate": "2025-03-11T15:30:45Z",
    "completionDate": null
  }
}
```

The `event` field can be one of:
- `created` - A new reminder was created
- `updated` - An existing reminder was modified
- `deleted` - A reminder was deleted
- `completed` - A reminder was marked as complete
- `uncompleted` - A reminder was marked as incomplete

#### Webhook Filtering

You can filter which reminders trigger webhooks using these criteria:
- `listNames` - Only reminders from specific lists (by name)
- `listUUIDs` - Only reminders from specific lists (by UUID)
- `completed` - Filter by completion status (all/complete/incomplete)
- `priorityLevels` - Only reminders with specific priority levels
- `hasQuery` - Only reminders with title or notes containing specific text

#### Creating a Webhook

Request:
```bash
curl -X POST http://localhost:8080/webhooks \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://your-webhook-endpoint.com/webhook",
    "name": "High priority work reminders",
    "filter": {
      "listNames": ["Work"],
      "priorityLevels": [1, 2, 3],
      "completed": "incomplete"
    }
  }'
```

Response:
```json
{
  "id": "6D3E8F2A-7B15-4C92-A5D8-1E9F4B7C3A6D",
  "url": "https://your-webhook-endpoint.com/webhook",
  "name": "High priority work reminders",
  "isActive": true,
  "filter": {
    "listNames": ["Work"],
    "priorityLevels": [1, 5, 9],
    "completed": "incomplete",
    "listUUIDs": null,
    "hasQuery": null
  }
}
```

#### Testing a Webhook

Request:
```bash
curl -X POST http://localhost:8080/webhooks/6D3E8F2A-7B15-4C92-A5D8-1E9F4B7C3A6D/test
```

Response:
```json
{
  "success": true,
  "message": "Test webhook sent successfully"
}
```

#### Listing Webhooks

Request:
```bash
curl http://localhost:8080/webhooks
```

Response:
```json
[
  {
    "id": "6D3E8F2A-7B15-4C92-A5D8-1E9F4B7C3A6D",
    "url": "https://your-webhook-endpoint.com/webhook",
    "name": "High priority work reminders",
    "isActive": true,
    "filter": {
      "listNames": ["Work"],
      "priorityLevels": [1, 2, 3],
      "completed": "incomplete",
      "listUUIDs": null,
      "hasQuery": null
    }
  },
  {
    "id": "8F2C4A1E-9D3B-5F7G-H6J8-K9L0M1N2O3P4",
    "url": "https://another-endpoint.com/hooks/reminders",
    "name": "Shopping list changes",
    "isActive": true,
    "filter": {
      "listNames": ["Shopping"],
      "priorityLevels": null,
      "completed": "all",
      "listUUIDs": null,
      "hasQuery": null
    }
  }
]
```

#### Updating a Webhook

Request:
```bash
curl -X PATCH http://localhost:8080/webhooks/6D3E8F2A-7B15-4C92-A5D8-1E9F4B7C3A6D \
  -H "Content-Type: application/json" \
  -d '{
    "isActive": false,
    "name": "High priority work reminders (paused)"
  }'
```

Response:
```json
{
  "id": "6D3E8F2A-7B15-4C92-A5D8-1E9F4B7C3A6D",
  "url": "https://your-webhook-endpoint.com/webhook",
  "name": "High priority work reminders (paused)",
  "isActive": false,
  "filter": {
    "listNames": ["Work"],
    "priorityLevels": [1, 5, 9],
    "completed": "incomplete",
    "listUUIDs": null,
    "hasQuery": null
  }
}
```

#### Deleting a Webhook

Request:
```bash
curl -X DELETE http://localhost:8080/webhooks/6D3E8F2A-7B15-4C92-A5D8-1E9F4B7C3A6D
```

Response:
HTTP 204 No Content
```

#### GET /reminders Example Response

```json
[
  {
    "creationDate": "2025-03-10T14:30:00Z",
    "dueDate": "2025-03-15T09:00:00Z",
    "id": "F3A0B3D8-E153-4AB9-B341-0C32A9AC6C2D",
    "isCompleted": false,
    "lastModifiedDate": "2025-03-10T14:30:00Z",
    "listName": "Soon",
    "notes": "Important deadline",
    "priority": 2,
    "title": "Finish project proposal"
  },
  {
    "creationDate": "2025-03-08T11:20:00Z",
    "dueDate": "2025-03-11T13:00:00Z",
    "id": "C4D92F3E-8A7B-4C97-B6F1-2E5D9F87A3E1",
    "isCompleted": false,
    "lastModifiedDate": "2025-03-08T11:20:00Z",
    "listName": "Work",
    "notes": null,
    "priority": 3,
    "title": "Team meeting"
  }
]
```

#### POST /lists/:name/reminders

Request:
```bash
curl -X POST http://localhost:8080/lists/Soon/reminders \
  -H "Content-Type: application/json" \
  -d '{
    "title": "API reminder",
    "notes": "Created via REST API",
    "dueDate": "2025-03-11T09:00:00Z",
    "priority": "high"
  }'
```

Response:
```json
{
  "creationDate": "2025-03-10T15:05:23Z",
  "dueDate": "2025-03-11T09:00:00Z",
  "id": "D1E8F7C6-5A4B-3C2D-9E8F-7A6B5C4D3E2F",
  "isCompleted": false,
  "lastModifiedDate": "2025-03-10T15:05:23Z",
  "listName": "Soon",
  "notes": "Created via REST API",
  "priority": 5,
  "title": "API reminder"
}
```

#### DELETE /lists/:listName/reminders/:id

Request:
```bash
curl -X DELETE http://localhost:8080/lists/Soon/reminders/D1E8F7C6-5A4B-3C2D-9E8F-7A6B5C4D3E2F
```

Response:
- Status code 204 No Content

#### PATCH /lists/:listName/reminders/:id/complete

Request:
```bash
curl -X PATCH http://localhost:8080/lists/Soon/reminders/F3A0B3D8-E153-4AB9-B341-0C32A9AC6C2D/complete
```

Response:
- Status code 200 OK

#### PATCH /lists/:listName/reminders/:id/uncomplete

Request:
```bash
curl -X PATCH http://localhost:8080/lists/Soon/reminders/F3A0B3D8-E153-4AB9-B341-0C32A9AC6C2D/uncomplete
```

Response:
- Status code 200 OK

### Using with curl

```bash
# Get all reminder lists
curl http://localhost:8080/lists

# Create a new reminder
curl -X POST http://localhost:8080/lists/Soon/reminders \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Web reminder",
    "notes": "Created from web app",
    "dueDate": "2025-03-15T10:00:00Z",
    "priority": "medium"
  }'

# Mark a reminder as complete
curl -X PATCH http://localhost:8080/lists/Soon/reminders/F3A0B3D8-E153-4AB9-B341-0C32A9AC6C2D/complete
```

## Running as a macOS Service

The reminders-api can be installed as a startup service to run automatically in the background. This is useful for:

- Running the API server automatically on system startup
- Keeping the server running even when you're not logged in
- Integrating with other automation tools and services

### Quick Installation

The easiest way to install the service is using the provided installation script:

```bash
# Make sure you're in the reminders-cli directory
cd reminders-cli

# Run the installation script
./install-service-simple.sh
```

This script will:
- Find or build the reminders-api binary
- Generate a secure API token
- Create a startup script
- Set up proper TCC permissions
- Start the service

### Testing Your Installation

After installation, test the API to verify everything is working:

```bash
# Test the API (replace TOKEN with your actual token)
curl -H "Authorization: Bearer YOUR_TOKEN" http://127.0.0.1:8080/lists

# Check if the service is running
pgrep -f reminders-api

# View service logs
tail -f /tmp/reminders-api-service.out /tmp/reminders-api-service.err
```

### Manual Installation

If you prefer to install manually or need to customize the configuration:

1. **Build the API server:**
   ```bash
   swift build --configuration release
   ```

2. **Generate an API token:**
   ```bash
   ./.build/apple/Products/Release/reminders-api --generate-token
   ```

3. **Create a startup script:**
   ```bash
   cat > ~/start-reminders-api-service.sh << 'EOF'
   #!/bin/bash
   # Startup script for reminders-api service
   
   # Kill any existing processes
   pkill -f reminders-api
   
   # Wait a moment
   sleep 2
   
   # Start the service
   nohup /path/to/reminders-api --auth-required --token YOUR_TOKEN --host 127.0.0.1 --port 8080 > /tmp/reminders-api-service.out 2> /tmp/reminders-api-service.err &
   
   echo "Reminders API service started"
   EOF
   
   chmod +x ~/start-reminders-api-service.sh
   ```

4. **Start the service:**
   ```bash
   ~/start-reminders-api-service.sh
   ```

### Service Management

Once installed, you can manage the service using these commands:

```bash
# Start the service
~/start-reminders-api-service.sh

# Stop the service
pkill -f reminders-api

# Check if the service is running
pgrep -f reminders-api

# View service logs
tail -f /tmp/reminders-api-service.out /tmp/reminders-api-service.err
```

### Automatic Startup After Reboots

To make the service start automatically after reboots:

1. **Go to System Preferences** → **Users & Groups** → **Login Items**
2. **Click the + button**
3. **Navigate to your startup script** (`~/start-reminders-api-service.sh`)
4. **Add it to login items**

The service will now start automatically when you log in.

### Troubleshooting Service Issues

#### The Classic TCC Permissions Problem

If the service returns empty lists or fails to start, you're likely encountering the **TCC (Transparency, Consent, and Control) permissions trap**. This is a common macOS issue where services can't access protected resources like Reminders.

**Root Cause:** When you run `reminders-api` in Terminal, macOS grants Reminders access to Terminal.app. But when running as a LaunchAgent, the service runs as the binary itself, which doesn't have permission to control Reminders.

#### Quick Diagnosis

1. **Check if the service is running:**
   ```bash
   launchctl print gui/$(id -u) | grep reminders
   ```

2. **Check the logs:**
   ```bash
   tail -f /tmp/reminders-api.out /tmp/reminders-api.err
   ```

3. **Test the API:**
   ```bash
   curl -H "Authorization: Bearer YOUR_TOKEN" http://127.0.0.1:8080/lists
   ```

#### Fix TCC Permissions

**Method 1: Grant Permission to the Binary (Recommended)**

1. **Stop the service:**
   ```bash
   launchctl bootout gui/$(id -u) com.reminders.api
   ```

2. **Run the binary directly to trigger permission prompt:**
   ```bash
   /path/to/reminders-api --help
   ```

3. **When macOS prompts "reminders-api wants to control Reminders", click "Allow"**

4. **Restart the service:**
   ```bash
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.reminders.api.plist
   launchctl kickstart -kp gui/$(id -u)/com.reminders.api
   ```

**Method 2: Reset and Re-grant Permissions**

If permissions get confused:

1. **Reset TCC permissions:**
   ```bash
   tccutil reset AppleEvents
   ```

2. **Follow Method 1 above**

#### Verify Permissions

Check that your binary has the correct permissions:

1. **Open System Settings → Privacy & Security → Automation**
2. **Look for your reminders-api binary in the list**
3. **Ensure "Reminders" is toggled ON**

#### Common Issues and Solutions

**Issue: Service starts but returns empty lists `[]`**
- **Cause:** TCC permissions not granted to the binary
- **Solution:** Follow Method 1 above

**Issue: Service fails to start (status shows `-`)**
- **Cause:** Service not loaded into GUI session
- **Solution:** Use proper GUI session commands:
  ```bash
  launchctl bootout gui/$(id -u) com.reminders.api
  launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.reminders.api.plist
  ```

**Issue: "Permission denied" errors**
- **Cause:** Service running in wrong context
- **Solution:** Ensure plist has `LimitLoadToSessionType: Aqua`

**Issue: Service starts then immediately crashes**
- **Cause:** Missing environment variables or working directory
- **Solution:** Check plist has proper `EnvironmentVariables` and `WorkingDirectory`

#### Advanced Troubleshooting

**Check service status in detail:**
```bash
launchctl print gui/$(id -u)/com.reminders.api
```

**View system logs:**
```bash
log show --last 10m --predicate 'process == "reminders-api"' --info --style syslog
```

**Test EventKit access manually:**
```bash
# This should trigger a permission prompt if not already granted
/path/to/reminders-api --help
```

**Reset all TCC permissions (nuclear option):**
```bash
sudo tccutil reset All
# Then re-grant all permissions as needed
```

### Service Configuration

The service is configured to:
- Run on `127.0.0.1:8080` by default
- Require authentication with a token
- Run in the foreground to maintain user session access
- Log output to `~/Library/Logs/reminders-api/`
- Automatically start on system boot
- Restart automatically if it crashes

You can modify these settings by editing the plist file and reloading the service.

### Production Deployment

For deploying to remote servers, use the production deployment script:

```bash
# Deploy to a remote server
./deploy-production.sh user@server.example.com

# Deploy with custom settings
./deploy-production.sh \
  --token "your-api-token" \
  --host "0.0.0.0" \
  --port-api 8080 \
  --dest "/usr/local/bin/" \
  user@server.example.com

# Deploy without building (use existing binary)
./deploy-production.sh --no-build user@server.example.com

# Deploy binary only (skip service installation)
./deploy-production.sh --no-install user@server.example.com
```

The deployment script will:
- Build the production binary (unless `--no-build` is used)
- Copy the binary to the remote server
- Install and configure the LaunchAgent service
- Set up proper TCC permissions
- Start the service automatically

#### Deployment Options

- `--port PORT`: SSH port (default: 22)
- `--key KEYFILE`: SSH private key file
- `--dest PATH`: Remote destination path (default: ~/.local/bin/)
- `--token TOKEN`: API token (will generate if not provided)
- `--host HOST`: API host to bind to (default: 127.0.0.1)
- `--port-api PORT`: API port (default: 8080)
- `--no-build`: Skip building, use existing binary
- `--no-install`: Skip service installation

#### Post-Deployment

After deployment, test the service:

```bash
# Test the API
curl -H "Authorization: Bearer YOUR_TOKEN" http://server.example.com:8080/lists

# Check service status
ssh user@server.example.com 'launchctl print gui/$(id -u) | grep reminders'

# View logs
ssh user@server.example.com 'tail -f /tmp/reminders-api.out /tmp/reminders-api.err'
```

### Uninstalling the Service

To remove the service completely:

```bash
# Run the uninstall script
./uninstall-service.sh
```

The uninstall script will:
- Stop the running service
- Remove the plist file
- Optionally remove log files
- Clean up the service configuration

### Manual Uninstallation

If you prefer to uninstall manually:

```bash
# Stop the service
launchctl unload ~/Library/LaunchAgents/com.reminders.api.plist

# Remove the plist file
rm ~/Library/LaunchAgents/com.reminders.api.plist

# Optionally remove logs
rm -rf ~/Library/Logs/reminders-api/
```
