# Reminders CLI HTTP API Documentation

## Overview

The Reminders CLI HTTP API provides programmatic access to macOS Reminders data through a RESTful interface. Built with Swift and Hummingbird, it offers comprehensive reminder management capabilities including CRUD operations, advanced search, and real-time webhook notifications.

## Getting Started

### Prerequisites
- macOS system with Reminders app
- Swift 5.5 or later
- Reminders access permission

### Installation & Setup

1. **Build the API server:**
   ```bash
   swift build --configuration release -Xswiftc -warnings-as-errors --arch arm64 --arch x86_64
   ```

2. **Generate API token:**
   ```bash
   reminders-api --generate-token
   ```

3. **Start the server:**
   ```bash
   # With environment variable
   export REMINDERS_API_TOKEN="your-token-here"
   reminders-api --host 127.0.0.1 --port 8080
   
   # Or with command line argument
   reminders-api --token "your-token-here" --host 127.0.0.1 --port 8080
   ```

### Server Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `--host` | Hostname to bind to | `127.0.0.1` |
| `--port` | Port to listen on | `8080` |
| `--token` | API authentication token | Environment variable |
| `--auth-required` | Require authentication for all endpoints | `false` |
| `--generate-token` | Generate new token and exit | - |

## Authentication

### Token-Based Authentication

The API uses Bearer token authentication. Include the token in the Authorization header:

```http
Authorization: Bearer your-api-token-here
```

### Managing Authentication

#### Configure Authentication Requirements
```http
POST /auth/settings
Content-Type: application/json
Authorization: Bearer your-token

{
  "requireAuth": true
}
```

**Response:**
```json
{
  "message": "Authentication settings updated. Required: true"
}
```

## Core API Endpoints

### Lists Management

#### Get All Lists
```http
GET /lists
```

**Response:**
```json
[
  {
    "title": "Reminders",
    "calendarIdentifier": "ABC123-DEF456",
    "type": "Local",
    "allowsContentModifications": true,
    "isSubscribed": false
  }
]
```

#### Get Reminders from Specific List
```http
GET /lists/{listName}?completed=false
```

**Parameters:**
- `listName` (path, required): Name of the list
- `completed` (query, optional): Include completed reminders (`true`/`false`)

**Response:**
```json
[
  {
    "uuid": "ABC123-DEF456-GHI789",
    "calendarItemIdentifier": "internal-id",
    "externalId": "x-apple-reminder://ABC123-DEF456-GHI789",
    "title": "Buy groceries",
    "notes": "Don't forget milk and bread",
    "dueDate": "2024-01-15T10:00:00Z",
    "isCompleted": false,
    "priority": 2,
    "listName": "Shopping",
    "listUUID": "LIST-UUID-123",
    "creationDate": "2024-01-01T09:00:00Z",
    "lastModifiedDate": "2024-01-01T09:00:00Z",
    "completionDate": null
  }
]
```

### Reminder Management

#### Get All Reminders
```http
GET /reminders?completed=false
```

**Parameters:**
- `completed` (query, optional): Include completed reminders (`true`/`false`)

#### Get Specific Reminder
```http
GET /reminders/{uuid}
```

**Parameters:**
- `uuid` (path, required): Reminder UUID

**Response:** Single reminder object (same structure as list response)

#### Create New Reminder
```http
POST /lists/{listName}/reminders
Content-Type: application/json

{
  "title": "Buy groceries",
  "notes": "Don't forget milk and bread",
  "dueDate": "2024-01-15T10:00:00Z",
  "priority": "medium"
}
```

**Parameters:**
- `listName` (path, required): Name of the target list
- `title` (required): Reminder title
- `notes` (optional): Additional notes
- `dueDate` (optional): Due date in ISO8601 format
- `priority` (optional): Priority level (`none`, `low`, `medium`, `high`)

**Response:** Created reminder object (HTTP 201)

#### Update Reminder
```http
PATCH /reminders/{uuid}
Content-Type: application/json

{
  "title": "Updated title",
  "notes": "Updated notes",
  "dueDate": "2024-01-20T14:00:00Z",
  "priority": "high",
  "isCompleted": false
}
```

**Parameters:**
- `uuid` (path, required): Reminder UUID
- All fields are optional; only provided fields will be updated

**Response:** Updated reminder object

#### Complete/Uncomplete Reminder
```http
PATCH /reminders/{uuid}/complete
PATCH /reminders/{uuid}/uncomplete
```

**Parameters:**
- `uuid` (path, required): Reminder UUID

**Response:** HTTP 200 on success

#### Delete Reminder
```http
DELETE /reminders/{uuid}
```

**Parameters:**
- `uuid` (path, required): Reminder UUID

**Response:** HTTP 204 on success

### Advanced Search

#### Search Reminders
```http
GET /search?query=groceries&completed=false&priority=high&sortBy=duedate&limit=10
```

**Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `query` | string | Text search in title/notes |
| `lists` | string | Comma-separated list names |
| `listUUIDs` | string | Comma-separated list UUIDs |
| `completed` | string | Completion status (`all`, `true`, `false`) |
| `dueBefore` | string | ISO8601 date - reminders due before |
| `dueAfter` | string | ISO8601 date - reminders due after |
| `modifiedAfter` | string | ISO8601 date - modified after |
| `createdAfter` | string | ISO8601 date - created after |
| `hasNotes` | boolean | Filter by presence of notes |
| `hasDueDate` | boolean | Filter by presence of due date |
| `priority` | string | Exact priority (`none`, `low`, `medium`, `high`) |
| `priorityMin` | integer | Minimum priority level (0-9) |
| `priorityMax` | integer | Maximum priority level (0-9) |
| `sortBy` | string | Sort field (`title`, `duedate`, `created`, `modified`, `priority`, `list`) |
| `sortOrder` | string | Sort direction (`asc`, `desc`) |
| `limit` | integer | Maximum results to return |

**Response:** Array of matching reminder objects

#### Search Examples

**Find overdue reminders:**
```http
GET /search?dueBefore=2024-01-01T00:00:00Z&completed=false
```

**High priority reminders in specific lists:**
```http
GET /search?lists=Work,Personal&priority=high&sortBy=duedate
```

**Recent reminders with notes:**
```http
GET /search?hasNotes=true&createdAfter=2024-01-01T00:00:00Z&sortBy=created&sortOrder=desc
```

## Webhook System

### Webhook Management

#### List All Webhooks
```http
GET /webhooks
```

**Response:**
```json
[
  {
    "id": "webhook-uuid-123",
    "url": "https://your-server.com/webhook",
    "name": "Task Notifications",
    "isActive": true,
    "filter": {
      "listNames": ["Work", "Personal"],
      "completed": "incomplete",
      "priorityLevels": [2, 3]
    }
  }
]
```

#### Get Specific Webhook
```http
GET /webhooks/{id}
```

#### Create Webhook
```http
POST /webhooks
Content-Type: application/json

{
  "url": "https://your-server.com/webhook",
  "name": "Task Notifications",
  "filter": {
    "listNames": ["Work", "Personal"],
    "listUUIDs": ["uuid1", "uuid2"],
    "completed": "incomplete",
    "priorityLevels": [2, 3],
    "hasQuery": "urgent"
  }
}
```

**Filter Options:**
- `listNames`: Array of list names to monitor
- `listUUIDs`: Array of list UUIDs to monitor
- `completed`: Completion status filter (`all`, `complete`, `incomplete`)
- `priorityLevels`: Array of priority levels to monitor
- `hasQuery`: Text that must be present in title/notes

#### Update Webhook
```http
PATCH /webhooks/{id}
Content-Type: application/json

{
  "url": "https://new-server.com/webhook",
  "name": "Updated Notifications",
  "isActive": false,
  "filter": {
    "listNames": ["Work"],
    "completed": "all"
  }
}
```

#### Delete Webhook
```http
DELETE /webhooks/{id}
```

#### Test Webhook
```http
POST /webhooks/{id}/test
```

**Response:**
```json
{
  "success": true,
  "message": "Test webhook sent successfully"
}
```

### Webhook Payloads

When events occur, webhooks receive POST requests with this payload structure:

```json
{
  "event": "created",
  "timestamp": "2024-01-15T10:30:00Z",
  "reminder": {
    "uuid": "ABC123-DEF456-GHI789",
    "title": "Buy groceries",
    "notes": "Don't forget milk and bread",
    "dueDate": "2024-01-15T10:00:00Z",
    "isCompleted": false,
    "priority": 2,
    "listName": "Shopping",
    "listUUID": "LIST-UUID-123",
    "creationDate": "2024-01-01T09:00:00Z",
    "lastModifiedDate": "2024-01-01T09:00:00Z",
    "completionDate": null
  }
}
```

**Event Types:**
- `created`: New reminder created
- `updated`: Reminder modified
- `deleted`: Reminder deleted
- `completed`: Reminder marked complete
- `uncompleted`: Reminder marked incomplete

## Data Models

### Reminder Object Structure

```json
{
  "uuid": "string",                    // Primary identifier (URL-safe)
  "calendarItemIdentifier": "string",  // Internal macOS identifier
  "externalId": "string",             // Full Apple reminder URL
  "title": "string",                  // Reminder title
  "notes": "string|null",             // Optional notes
  "dueDate": "string|null",           // ISO8601 date or null
  "isCompleted": "boolean",           // Completion status
  "priority": "number",               // Priority level (0-9)
  "listName": "string",               // Name of containing list
  "listUUID": "string",               // UUID of containing list
  "creationDate": "string|null",      // ISO8601 creation date
  "lastModifiedDate": "string|null",  // ISO8601 last modified
  "completionDate": "string|null"     // ISO8601 completion date
}
```

### Priority Levels

| Priority | Value | Description |
|----------|-------|-------------|
| `none` | 0 | No priority |
| `low` | 1 | Low priority |
| `medium` | 5 | Medium priority |
| `high` | 9 | High priority |

### List Object Structure

```json
{
  "title": "string",                  // List display name
  "calendarIdentifier": "string",     // Unique list identifier
  "type": "string",                   // List type (e.g., "Local")
  "allowsContentModifications": "boolean",
  "isSubscribed": "boolean"
}
```

## Error Handling

### Standard HTTP Status Codes

| Status | Description |
|--------|-------------|
| 200 | OK - Request successful |
| 201 | Created - Resource created successfully |
| 204 | No Content - Request successful, no response body |
| 400 | Bad Request - Invalid request parameters |
| 401 | Unauthorized - Invalid or missing authentication |
| 404 | Not Found - Requested resource not found |
| 500 | Internal Server Error - Server error occurred |

### Error Response Format

```json
{
  "error": "Error message description",
  "status": 400
}
```

### Common Error Scenarios

**Authentication Required:**
```json
{
  "error": "Authentication required",
  "status": 401
}
```

**Invalid Reminder UUID:**
```json
{
  "error": "Reminder not found",
  "status": 404
}
```

**Invalid List Name:**
```json
{
  "error": "List 'InvalidList' not found",
  "status": 404
}
```

## Legacy Endpoints (Deprecated)

These endpoints are maintained for backward compatibility but should not be used in new implementations:

```http
DELETE /lists/{listName}/reminders/{id}
PATCH /lists/{listName}/reminders/{id}/complete
PATCH /lists/{listName}/reminders/{id}/uncomplete
```

Use the UUID-based endpoints instead:
```http
DELETE /reminders/{uuid}
PATCH /reminders/{uuid}/complete
PATCH /reminders/{uuid}/uncomplete
```

## Rate Limiting & Performance

- No explicit rate limiting implemented
- Webhook delivery timeout: 5 seconds
- Search operations support pagination via `limit` parameter
- Concurrent webhook deliveries supported
- EventKit notifications processed asynchronously

## Security Considerations

- API tokens should be treated as secrets
- HTTPS recommended for production deployments
- CORS enabled for web applications
- Webhook URLs should use HTTPS
- No rate limiting - implement at reverse proxy level if needed

## Integration Examples

### cURL Examples

**Create a reminder:**
```bash
curl -X POST "http://localhost:8080/lists/Shopping/reminders" \
  -H "Authorization: Bearer your-token" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Buy groceries",
    "notes": "Milk, bread, eggs",
    "dueDate": "2024-01-15T10:00:00Z",
    "priority": "medium"
  }'
```

**Search for overdue reminders:**
```bash
curl "http://localhost:8080/search?dueBefore=2024-01-01T00:00:00Z&completed=false" \
  -H "Authorization: Bearer your-token"
```

### JavaScript Example

```javascript
const API_BASE = 'http://localhost:8080';
const API_TOKEN = 'your-token-here';

async function createReminder(listName, title, options = {}) {
  const response = await fetch(`${API_BASE}/lists/${encodeURIComponent(listName)}/reminders`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${API_TOKEN}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      title,
      ...options
    })
  });
  
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
  }
  
  return response.json();
}

// Usage
createReminder('Shopping', 'Buy groceries', {
  notes: 'Milk, bread, eggs',
  dueDate: '2024-01-15T10:00:00Z',
  priority: 'medium'
}).then(reminder => {
  console.log('Created reminder:', reminder.uuid);
});
```

### Python Example

```python
import requests
import json

class RemindersAPI:
    def __init__(self, base_url="http://localhost:8080", token=None):
        self.base_url = base_url
        self.token = token
        self.session = requests.Session()
        if token:
            self.session.headers.update({
                'Authorization': f'Bearer {token}',
                'Content-Type': 'application/json'
            })
    
    def create_reminder(self, list_name, title, **kwargs):
        data = {'title': title}
        data.update(kwargs)
        
        response = self.session.post(
            f"{self.base_url}/lists/{list_name}/reminders",
            json=data
        )
        response.raise_for_status()
        return response.json()
    
    def search_reminders(self, **filters):
        response = self.session.get(
            f"{self.base_url}/search",
            params=filters
        )
        response.raise_for_status()
        return response.json()

# Usage
api = RemindersAPI(token="your-token-here")

# Create reminder
reminder = api.create_reminder(
    "Shopping",
    "Buy groceries",
    notes="Milk, bread, eggs",
    dueDate="2024-01-15T10:00:00Z",
    priority="medium"
)

# Search reminders
results = api.search_reminders(
    query="groceries",
    completed="false",
    sortBy="duedate"
)
```

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure Reminders access is granted to the application
2. **Token Authentication**: Verify token is correctly set and valid
3. **List Not Found**: Check exact list name spelling and case sensitivity
4. **Webhook Delivery Failures**: Ensure webhook URL is accessible and returns 2xx status
5. **Date Format Issues**: Use ISO8601 format for all dates

### Debug Mode

Start server with verbose logging:
```bash
REMINDERS_API_DEBUG=1 reminders-api --token your-token
```

### Testing Webhooks

Use tools like ngrok for local webhook testing:
```bash
ngrok http 3000
# Use the ngrok URL as your webhook endpoint
```