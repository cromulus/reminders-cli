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

```
$ cd reminders-cli
$ make build-release
$ cp .build/apple/Products/Release/reminders /usr/local/bin/reminders
```

#### Building with Private API Support

For enhanced functionality including tag management, subtasks, and additional metadata, you can build with private API support:

```bash
# Build CLI with private APIs
$ make build-private
$ cp .build/apple/Products/Release/reminders /usr/local/bin/reminders

# Build API server with private APIs
$ make build-private-release
$ cp .build/apple/Products/Release/reminders-api /usr/local/bin/reminders-api

# Package with private API support
$ make package-private
```

**Important Notes for Private API Builds:**
- Requires disabling App Sandbox and Hardened Runtime
- May not be suitable for App Store distribution
- Provides access to advanced features like tags and subtasks
- Use at your own discretion as private APIs may change

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

The API server supports token-based authentication, which is optional by default but can be required for all endpoints.

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
   # Using environment variable:
   $ REMINDERS_API_TOKEN=abc123def456... reminders-api
   
   # Or using command line argument:
   $ reminders-api --token abc123def456...
   
   # To require authentication for all endpoints:
   $ reminders-api --token abc123def456... --auth-required
   ```

3. Authenticate requests using the Bearer token:
   ```bash
   $ curl -H "Authorization: Bearer abc123def456..." http://localhost:8080/lists
   ```

#### Server command-line options

```bash
$ reminders-api --help
USAGE: reminders-api [--host <host>] [--port <port>] [--token <token>] [--auth-required] [--generate-token]

OPTIONS:
  --host <host>           The hostname to bind to (default: 127.0.0.1)
  -p, --port <port>       The port to listen on (default: 8080)
  --token <token>         API authentication token (overrides REMINDERS_API_TOKEN environment variable)
  --auth-required         Require authentication for all API endpoints
  --generate-token        Generate a new API token and exit
  -h, --help              Show help information.
```

### API Endpoints

#### Core Reminders Management

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/info` | Get API status and capabilities |
| GET | `/lists` | List all reminder lists |
| GET | `/lists/:name` | Get reminders from a specific list |
| GET | `/reminders` | Get all reminders across all lists |
| POST | `/lists/:name/reminders` | Add a new reminder to a list |
| DELETE | `/lists/:listName/reminders/:id` | Delete a reminder |
| PATCH | `/lists/:listName/reminders/:id/complete` | Mark a reminder as complete |
| PATCH | `/lists/:listName/reminders/:id/uncomplete` | Mark a reminder as incomplete |
| GET | `/search` | Search for reminders with complex filtering |

#### Private API Features (Enhanced Build Only)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/private-api/status` | Check private API availability |
| GET | `/tags` | List all available tags |
| GET | `/reminders/by-tag/:tag` | Get reminders filtered by tag |
| POST | `/reminders/:uuid/tags` | Add tag to reminder |
| DELETE | `/reminders/:uuid/tags/:tag` | Remove tag from reminder |
| GET | `/reminders/:uuid/subtasks` | Get subtasks for a reminder |
| POST | `/reminders/:uuid/subtasks` | Create a new subtask |

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
    "priority": 5,
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
      "priorityLevels": [1, 5, 9],
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
      "priorityLevels": [1, 5, 9],
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
    "priority": 5,
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
    "priority": 9,
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
