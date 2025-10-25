# MCP Server for Apple Reminders - Specification

## Overview

An MCP (Model Context Protocol) server that exposes Apple Reminders functionality to Large Language Models and MCP clients. The server provides comprehensive access to reminders data through tools and resources, supporting both local (stdio) and remote (HTTP streaming) connections.

## Goals

1. **Enable LLM Access**: Allow LLMs like Claude to read and manage user reminders through natural language
2. **Reuse Existing Code**: Leverage the existing RemindersLibrary without duplication
3. **Support Multiple Transports**: Work with both stdio (Claude Desktop) and HTTP streaming (remote clients)
4. **Maintain Safety**: Require confirmation for bulk operations affecting >10 items
5. **Expose All Features**: Include private API metadata (subtasks, URLs) when available

## Non-Goals

- WebSocket transport (simplified to stdio + HTTP streaming only)
- Real-time push notifications (polling supported via resources)
- Subtask creation (private API limitation)
- URL attachment modification (EventKit limitation)

## Success Criteria

### Core Functionality

✅ **Transport Layer**
- Stdio transport accepts JSON-RPC messages from stdin and writes to stdout
- HTTP streaming transport serves MCP over Server-Sent Events (SSE)
- Both transports support full MCP protocol including tools and resources

✅ **Tools Implementation**
- `lists` tool: get all lists, create new list, delete list
- `reminders` tool: create, get, update, delete, complete, uncomplete, list reminders
- `search` tool: complex filtering with all existing API capabilities

✅ **Resources Implementation**
- `reminders://lists` - returns all reminder lists
- `reminders://list/{name}` - returns reminders in specific list (by name or UUID)
- `reminders://uuid/{id}` - returns single reminder by UUID

✅ **Data Completeness**
- All standard reminder fields (title, notes, dueDate, priority, completion, etc.)
- Private API fields included when available (attachedUrl, mailUrl, isSubtask, parentId)
- Graceful fallback when private APIs unavailable

✅ **Safety & Error Handling**
- Bulk operations (>10 items) require explicit confirmation
- Clear, actionable error messages for LLMs
- EventKit permission handling with helpful guidance
- UUID format handling (both with and without "x-apple-reminder://" prefix)

✅ **Code Quality**
- No duplication of RemindersLibrary code
- Comprehensive test coverage (unit + integration)
- Follows existing code style from CLAUDE.md
- Clean separation of transport/tool layers

## Acceptance Criteria

### AC1: List Management

**Given** the MCP server is running with Reminders access granted
**When** a client calls the `lists` tool with operation="get"
**Then** all reminder lists are returned with names and UUIDs

**When** a client calls the `lists` tool with operation="create" and name="Shopping"
**Then** a new list "Shopping" is created and returned
**And** the list appears in subsequent get operations

**When** a client calls the `lists` tool with operation="delete" and name="Shopping"
**Then** the list is deleted
**And** an error is returned if the list doesn't exist

### AC2: Reminder Creation

**Given** a list "Work" exists
**When** a client calls the `reminders` tool with:
- operation="create"
- list="Work"
- title="Review PR"
- notes="Check the authentication changes"
- dueDate="2025-10-20T14:00:00Z"
- priority="high"

**Then** a new reminder is created with all specified fields
**And** the response includes a UUID for the reminder
**And** the reminder appears in "Work" list

### AC3: Reminder Retrieval

**Given** a reminder with UUID="ABC123" exists
**When** a client accesses resource `reminders://uuid/ABC123`
**Then** the complete reminder data is returned
**And** private API fields are included when available (attachedUrl, isSubtask, etc.)

**When** a client accesses resource `reminders://uuid/x-apple-reminder://ABC123`
**Then** the same reminder is returned (handles both UUID formats)

**When** a client accesses resource `reminders://uuid/INVALID`
**Then** a "not found" error is returned with helpful suggestion

### AC4: Reminder Updates

**Given** a reminder with UUID="ABC123" exists
**When** a client calls the `reminders` tool with:
- operation="update"
- uuid="ABC123"
- title="Updated Title"

**Then** only the title is updated
**And** other fields remain unchanged
**And** the updated reminder is returned

**When** a client calls the `reminders` tool with operation="complete" and uuid="ABC123"
**Then** the reminder is marked as completed
**And** completionDate is set to current time

### AC5: Advanced Search

**When** a client calls the `search` tool with:
- query="meeting"
- lists=["Work"]
- completed="false"
- dueBefore="2025-10-25T00:00:00Z"
- priority=["high", "medium"]
- sortBy="dueDate"
- sortOrder="asc"
- limit=20

**Then** reminders matching ALL criteria are returned
**And** results are sorted by due date ascending
**And** at most 20 results are returned

**When** a client calls search with lists=["NonExistent"]
**Then** an empty array is returned (not an error)

### AC6: Bulk Operations Safety

**Given** there are 15 incomplete reminders in the "Archive" list
**When** a client attempts to delete all reminders in "Archive"
**Then** the operation is rejected with a confirmation request
**And** the error message indicates 15 items would be affected
**And** suggests using a confirmation flag

**Given** there are 5 incomplete reminders in the "Quick Tasks" list
**When** a client attempts to complete all reminders in "Quick Tasks"
**Then** all 5 reminders are completed immediately (< 10 threshold)

### AC7: Transport Compatibility

**Given** the server is started with stdio transport
**When** a client sends a JSON-RPC request via stdin
**Then** a JSON-RPC response is written to stdout
**And** the response follows MCP protocol format

**Given** the server is started with HTTP streaming transport on port 8080
**When** a client connects to `http://localhost:8080/mcp`
**Then** an SSE connection is established
**And** MCP messages are sent/received via SSE events

### AC8: Error Handling

**Given** Reminders access has not been granted
**When** any tool or resource is accessed
**Then** an error is returned with code -32001
**And** the message explains permission is required
**And** data includes instructions for granting access in System Preferences

**Given** a client requests a non-existent reminder UUID
**When** resource `reminders://uuid/INVALID` is accessed
**Then** an error with code -32002 is returned
**And** the message indicates "Reminder not found"
**And** data includes the invalid identifier

**Given** a client sends malformed JSON
**When** the server attempts to parse the request
**Then** an error with code -32700 is returned
**And** the message indicates parse error

### AC9: Private API Integration

**Given** the server is built with private API support
**When** a reminder with URL attachment is retrieved
**Then** the `attachedUrl` field contains the URL
**And** the response indicates private API data is included

**Given** the server is built without private API support
**When** a reminder is retrieved
**Then** only public EventKit fields are included
**And** `attachedUrl`, `mailUrl`, `parentId` are null

### AC10: Resource URI Patterns

**When** a client accesses `reminders://lists`
**Then** all lists are returned with full metadata

**When** a client accesses `reminders://list/Work`
**Then** all reminders in "Work" list are returned

**When** a client accesses `reminders://list/{UUID}`
**Then** reminders in the list with that UUID are returned
**And** list is resolved by UUID, not name

## Performance Requirements

| Operation | Target | Max Acceptable |
|-----------|--------|----------------|
| Get single reminder | < 200ms | < 500ms |
| List all reminders in a list | < 300ms | < 1s |
| Search with filters | < 1s | < 2s |
| Create reminder | < 300ms | < 500ms |
| Update reminder | < 200ms | < 500ms |
| Delete reminder | < 200ms | < 500ms |

**Note**: Performance may degrade with very large datasets (>5,000 reminders)

## Security Requirements

1. **macOS Permissions**: Must request and verify Reminders access before any operations
2. **No Credential Storage**: No API tokens or passwords (local trust model)
3. **Sandbox Compatible**: Works with macOS sandbox (no unauthorized file access)
4. **Audit Trail**: Log all mutating operations (create, update, delete)
5. **Bulk Operation Confirmation**: Prevent accidental mass deletion (>10 items)

## Compatibility Requirements

- **macOS**: 10.15+ (Catalina or later)
- **Swift**: 6.0+
- **Xcode**: 16+
- **MCP Protocol**: 2025-03-26 specification
- **MCP SDK**: 0.10.0+

## Data Schemas

### Tool Input Schemas

**lists tool**:
```json
{
  "operation": "get" | "create" | "delete",
  "name": "string (required for create/delete)"
}
```

**reminders tool**:
```json
{
  "operation": "create" | "get" | "update" | "delete" | "complete" | "uncomplete" | "list",
  "list": "string (name or UUID, required for create/list)",
  "uuid": "string (required for get/update/delete/complete/uncomplete)",
  "title": "string (required for create, optional for update)",
  "notes": "string (optional)",
  "dueDate": "ISO8601 string (optional)",
  "priority": "none" | "low" | "medium" | "high" (optional)",
  "isCompleted": "boolean (optional for update)"
}
```

**search tool**:
```json
{
  "query": "string (text search in title/notes)",
  "lists": ["array of list names or UUIDs"],
  "excludeLists": ["array to exclude"],
  "completed": "all" | "true" | "false",
  "priority": ["none", "low", "medium", "high"] | "any",
  "dueBefore": "ISO8601 string",
  "dueAfter": "ISO8601 string",
  "modifiedAfter": "ISO8601 string",
  "createdAfter": "ISO8601 string",
  "hasNotes": "boolean",
  "hasDueDate": "boolean",
  "sortBy": "title" | "dueDate" | "created" | "modified" | "priority" | "list",
  "sortOrder": "asc" | "desc",
  "limit": "integer"
}
```

### Output Schema (Reminder)

```json
{
  "uuid": "ABC123",
  "externalId": "ABC123",
  "title": "Review PR",
  "notes": "Check the authentication changes",
  "dueDate": "2025-10-20T14:00:00Z",
  "isCompleted": false,
  "priority": 3,
  "list": "Work",
  "listUUID": "DEF456",
  "creationDate": "2025-10-15T10:30:00Z",
  "lastModified": "2025-10-15T10:30:00Z",
  "completionDate": null,
  "attachedUrl": "https://example.com/pr/123",
  "mailUrl": null,
  "parentId": null,
  "isSubtask": false
}
```

### Resource URI Patterns

- `reminders://lists` - All lists
- `reminders://list/<name-or-uuid>` - Reminders in list
- `reminders://uuid/<uuid>` - Single reminder

## Testing Requirements

### Unit Tests

- [ ] Each tool handler with mock data
- [ ] UUID format handling (with/without prefix)
- [ ] Search filter combinations
- [ ] Error cases (permission denied, not found, invalid input)
- [ ] Resource URI parsing
- [ ] JSON encoding/decoding
- [ ] Bulk operation threshold detection

### Integration Tests

- [ ] Full stdio request/response cycle
- [ ] HTTP streaming connection and message exchange
- [ ] Multi-tool sequences (create → update → delete)
- [ ] Search with various filter combinations
- [ ] Resource access patterns
- [ ] EventKit permission flow
- [ ] Private API field inclusion

### Manual Test Scenarios

1. **Claude Desktop Integration**
   - Configure MCP server in Claude Desktop
   - Ask Claude to create a reminder
   - Ask Claude to search for reminders
   - Verify responses are appropriate

2. **HTTP Streaming Client**
   - Connect remote client via SSE
   - Send multiple tool requests
   - Verify connection stays alive
   - Test reconnection handling

3. **Bulk Operations**
   - Attempt to delete >10 reminders
   - Verify confirmation is requested
   - Attempt to complete <10 reminders
   - Verify no confirmation needed

4. **Error Scenarios**
   - Revoke Reminders permission
   - Verify helpful error message
   - Request non-existent reminder
   - Verify not-found handling

## Documentation Requirements

### Required Documentation

- [ ] Installation guide (Package.swift setup)
- [ ] Quick start guide (stdio with Claude Desktop)
- [ ] Transport configuration (stdio vs HTTP streaming)
- [ ] Tool reference (all parameters and examples)
- [ ] Resource URI reference
- [ ] Error code reference
- [ ] Troubleshooting guide
- [ ] Architecture overview

### Example Usage

**Example 1: List all reminders due today**
```
User: "What reminders do I have due today?"
LLM → search tool:
{
  "dueAfter": "2025-10-16T00:00:00Z",
  "dueBefore": "2025-10-16T23:59:59Z",
  "completed": "false",
  "sortBy": "dueDate"
}
LLM ← result: [3 reminders with details]
LLM → User: "You have 3 reminders due today: ..."
```

**Example 2: Create a reminder**
```
User: "Remind me to call John tomorrow at 2pm"
LLM → reminders tool:
{
  "operation": "create",
  "list": "Reminders",
  "title": "Call John",
  "dueDate": "2025-10-17T14:00:00Z",
  "priority": "medium"
}
LLM ← result: {uuid: "XYZ789", ...}
LLM → User: "I've created a reminder to call John tomorrow at 2pm"
```

**Example 3: Search with filters**
```
User: "Show me all high-priority work items that aren't done"
LLM → search tool:
{
  "lists": ["Work"],
  "completed": "false",
  "priority": ["high"],
  "sortBy": "dueDate",
  "sortOrder": "asc"
}
LLM ← result: [5 matching reminders]
LLM → User: "Here are your 5 high-priority work items: ..."
```

## Deployment Considerations

### Build Configurations

**Development Build** (with private API):
```bash
swift build --configuration debug -Xswiftc -DPRIVATE_REMINDERS_ENABLED
```

**Production Build** (EventKit only):
```bash
swift build --configuration release
```

### Running the Server

**Stdio mode** (for Claude Desktop):
```bash
./reminders-mcp --transport stdio
```

**HTTP streaming mode**:
```bash
./reminders-mcp --transport http --port 8080
```

### Claude Desktop Configuration

Add to `claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "reminders": {
      "command": "/path/to/reminders-mcp",
      "args": ["--transport", "stdio"]
    }
  }
}
```

## Future Enhancements (Out of Scope)

- Subtask creation support (requires private API write access)
- URL attachment modification (EventKit limitation)
- Real-time push notifications (vs polling via resources)
- Recurring reminder management
- Reminder sharing/collaboration
- Attachment file management
- Location-based reminders
- Voice input integration

## Success Metrics

### Quantitative Metrics

- Test coverage: >80% line coverage, 100% critical path
- Performance: 95% of operations meet target latency
- Error rate: <1% of well-formed requests fail
- Claude Desktop compatibility: Works without configuration issues

### Qualitative Metrics

- Error messages are clear and actionable for LLMs
- API is intuitive for LLM tool calling
- Code is maintainable and follows project conventions
- Documentation is comprehensive and accurate

## Sign-Off Criteria

This specification is complete when:

- [x] All acceptance criteria have test coverage
- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] Manual testing checklist completed
- [ ] Documentation is complete and accurate
- [ ] Code review approval received
- [ ] Successfully tested with Claude Desktop
- [ ] Performance requirements met
- [ ] No critical or high-severity bugs
