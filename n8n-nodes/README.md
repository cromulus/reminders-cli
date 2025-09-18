# n8n Reminders API Nodes

This package provides n8n nodes for interacting with the macOS Reminders API, enabling you to create, manage, and search reminders directly from your n8n workflows.

## Features

### Core Nodes

- **Reminders**: Create, read, update, and delete reminders
- **Search Reminders**: Advanced search and filtering capabilities
- **Webhook Manager**: Manage webhook configurations for real-time notifications
- **Reminders Trigger**: Trigger workflows when reminder events occur

### Key Capabilities

- ✅ Full CRUD operations for reminders
- ✅ Advanced search with multiple filters
- ✅ Real-time webhook notifications
- ✅ Support for subtasks and URL attachments
- ✅ Priority management
- ✅ List management
- ✅ AI tool definitions for n8n AI features

## Installation

### Prerequisites

1. **macOS System**: This package requires a macOS system with the Reminders app
2. **Reminders API Server**: You need to have the reminders-api server running
3. **n8n Instance**: A running n8n instance (self-hosted or cloud)

### Install the Reminders API Server

First, set up the reminders-api server:

```bash
# Clone and build the reminders-api
git clone <your-reminders-api-repo>
cd reminders-api
make build-api

# Generate an API token
./.build/apple/Products/Release/reminders-api --generate-token

# Start the server
./.build/apple/Products/Release/reminders-api --token "your-token-here"
```

### Install the n8n Nodes

#### Option 1: Local Development Installation

1. **Clone this repository**:
   ```bash
   git clone <this-repo>
   cd n8n-nodes-reminders-api
   ```

2. **Install dependencies**:
   ```bash
   npm install
   ```

3. **Build the package**:
   ```bash
   npm run build
   ```

4. **Link to your n8n instance**:
   ```bash
   # For self-hosted n8n
   npm link
   cd /path/to/your/n8n/instance
   npm link n8n-nodes-reminders-api
   ```

#### Option 2: Package Installation

1. **Create a tarball**:
   ```bash
   npm pack
   ```

2. **Install in your n8n instance**:
   ```bash
   cd /path/to/your/n8n/instance
   npm install /path/to/n8n-nodes-reminders-api-1.0.0.tgz
   ```

#### Option 3: Direct Copy Installation

1. **Build the package**:
   ```bash
   npm run build
   ```

2. **Copy to n8n nodes directory**:
   ```bash
   # Copy the dist folder to your n8n nodes directory
   cp -r dist /path/to/your/n8n/instance/nodes/
   ```

## Configuration

### 1. Set up Credentials

In your n8n instance:

1. Go to **Credentials** → **Add Credential**
2. Search for **Reminders API**
3. Configure:
   - **API Base URL**: `http://localhost:8080` (or your server URL)
   - **API Token**: Your generated API token
   - **Authentication Required**: `true` if you want to require auth

### 2. Create Your First Workflow

1. **Create a new workflow**
2. **Add a Reminders node**
3. **Configure the operation** (e.g., "Create")
4. **Set the parameters**:
   - List Name: "Shopping"
   - Title: "Buy groceries"
   - Notes: "Don't forget milk and bread"
   - Priority: "Medium"

## Usage Examples

### Basic Reminder Management

```javascript
// Create a reminder
{
  "operation": "create",
  "listName": "Work",
  "title": "Review project proposal",
  "notes": "Check budget and timeline",
  "dueDate": "2024-01-15T10:00:00Z",
  "priority": "high"
}

// Search for reminders
{
  "operation": "search",
  "query": "project",
  "lists": "Work,Personal",
  "priority": "high",
  "completed": "false"
}
```

### Advanced Search

```javascript
// Find overdue reminders
{
  "operation": "findOverdue"
}

// Find subtasks
{
  "operation": "findSubtasks"
}

// Find reminders with URL attachments
{
  "operation": "findUrlAttachments"
}
```

### Webhook Management

```javascript
// Create a webhook
{
  "operation": "create",
  "webhookUrl": "https://your-server.com/webhook",
  "webhookName": "Task Notifications",
  "listNames": "Work,Personal",
  "completed": "incomplete",
  "priorityLevels": "2,3"
}
```

## AI Integration

This package includes AI tool definitions that can be used with n8n's AI features:

- `create_reminder`: Create reminders via AI
- `search_reminders`: Search reminders with natural language
- `update_reminder`: Update reminders via AI
- `complete_reminder`: Mark reminders complete via AI
- `find_overdue_reminders`: Find overdue reminders via AI

### Using AI Tools

1. **Enable AI in your n8n instance**
2. **Import the AI tools** from `ai-tools/reminders-tools.json`
3. **Use in AI nodes** like "AI Transform" or "AI Agent"

## API Reference

### Reminders Node Operations

| Operation | Description | Parameters |
|-----------|-------------|------------|
| Create | Create a new reminder | listName, title, notes, dueDate, priority |
| Get | Get a specific reminder | reminderUuid |
| Get All | Get all reminders | includeCompleted |
| Update | Update an existing reminder | reminderUuid, title, notes, dueDate, priority, isCompleted |
| Delete | Delete a reminder | reminderUuid |
| Complete | Mark reminder as complete | reminderUuid |
| Uncomplete | Mark reminder as incomplete | reminderUuid |

### Search Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| query | string | Text search in title/notes |
| lists | string | Comma-separated list names |
| completed | string | Completion status filter |
| priority | string | Priority level filter |
| dueBefore | string | Due date before filter |
| dueAfter | string | Due date after filter |
| sortBy | string | Sort field |
| limit | number | Maximum results |

## Troubleshooting

### Common Issues

1. **"Authentication required" error**:
   - Ensure your API token is correct
   - Check that the reminders-api server is running
   - Verify the base URL is correct

2. **"List not found" error**:
   - Check the exact list name (case-sensitive)
   - Use the "Get All Lists" operation to see available lists

3. **Webhook not triggering**:
   - Verify the webhook URL is accessible
   - Check webhook configuration and filters
   - Test the webhook using the "Test" operation

### Debug Mode

Enable debug logging in the reminders-api server:

```bash
./reminders-api --log-level DEBUG --token "your-token"
```

## Development

### Building from Source

```bash
# Install dependencies
npm install

# Build the package
npm run build

# Run linting
npm run lint

# Format code
npm run format
```

### Project Structure

```
n8n-nodes-reminders-api/
├── credentials/
│   └── RemindersApi.credentials.ts
├── nodes/
│   ├── Reminders/
│   ├── SearchReminders/
│   ├── WebhookManager/
│   └── RemindersTrigger/
├── ai-tools/
│   └── reminders-tools.json
├── package.json
├── tsconfig.json
└── README.md
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Support

- **Issues**: Report bugs and request features on GitHub
- **Documentation**: Check the API documentation for detailed endpoint information
- **Community**: Join the n8n community for support and discussions

## Changelog

### v1.0.0
- Initial release
- Core reminder CRUD operations
- Advanced search capabilities
- Webhook management
- AI tool definitions
- Real-time trigger support
