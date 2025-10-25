# MCP Server Implementation Context

This document provides comprehensive context for implementing an MCP (Model Context Protocol) server for Apple Reminders. It includes SDK documentation, existing codebase integration points, code snippets, and architectural patterns.

## MCP Swift SDK Documentation

### Installation

Add the SDK to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0")
]
```

Add to target dependencies:

```swift
.target(
    name: "reminders-mcp",
    dependencies: [
        .product(name: "MCP", package: "swift-sdk"),
        "RemindersLibrary"
    ]
)
```

### Requirements

- **Swift 6.0+** (Xcode 16+)
- **macOS 10.15+** (for EventKit)
- Implements MCP specification version 2025-03-26

### Transport Options

**Stdio Transport** (local subprocess, works with Claude Desktop):
```swift
import MCP

let transport = StdioTransport()
try await client.connect(transport: transport)
```

**HTTP Transport** (remote servers with SSE):
```swift
let transport = HTTPClientTransport(
    endpoint: URL(string: "http://localhost:8080")!,
    streaming: true
)
try await client.connect(transport: transport)
```

### Server-Side Usage Pattern

While the SDK documentation shows client usage, for server implementation:

1. Create server instance with capabilities
2. Register tool handlers
3. Register resource handlers
4. Start transport listener
5. Process incoming requests and return responses

## Existing Codebase Integration Points

### RemindersLibrary Public APIs

**Core Reminders Class** (`Sources/RemindersLibrary/Reminders.swift`):

```swift
public final class Reminders {
    let store: EKEventStore

    // Permission handling
    public static func requestAccess() -> (Bool, Error?)

    // List management
    public func getCalendars() -> [EKCalendar]
    public func getListNames() -> [String]
    public func calendar(withName name: String) -> EKCalendar
    public func calendar(withUUID uuid: String) -> EKCalendar?

    // Reminder fetching
    public func reminders(
        on calendars: [EKCalendar],
        displayOptions: DisplayOptions,
        completion: @escaping (_ reminders: [EKReminder]) -> Void
    )

    // CRUD operations
    public func createReminder(
        title: String,
        notes: String?,
        calendar: EKCalendar,
        dueDateComponents: DateComponents?,
        priority: Priority
    ) -> EKReminder

    public func getReminderByUUID(_ uuid: String) -> EKReminder?
    public func deleteReminder(_ reminder: EKReminder) throws
    public func setReminderComplete(_ reminder: EKReminder, complete: Bool) throws
    public func updateReminder(_ reminder: EKReminder) throws

    // Helper methods
    public func shouldDisplay(reminder: EKReminder, displayOptions: DisplayOptions) -> Bool
}
```

**Enums and Types**:

```swift
public enum DisplayOptions: String, Decodable {
    case all
    case incomplete
    case complete
}

public enum Priority: String, ExpressibleByArgument {
    case none
    case low
    case medium
    case high

    public var value: EKReminderPriority {
        switch self {
            case .none: return .none
            case .low: return .low
            case .medium: return .medium
            case .high: return .high
        }
    }
}
```

### JSON Serialization

**EKReminder+Encodable Extension** (`Sources/RemindersLibrary/EKReminder+Encodable.swift`):

```swift
extension EKReminder: @retroactive Encodable {
    // Automatically encodes:
    // - uuid (stripped of "x-apple-reminder://" prefix)
    // - externalId (same as uuid)
    // - title, notes, isCompleted, priority
    // - list (name), listUUID
    // - dueDate, startDate, completionDate, creationDate, lastModified
    // - location, locationTitle
    // - attachedUrl, mailUrl (private API)
    // - parentId, isSubtask (private API)

    public func encode(to encoder: Encoder) throws {
        // Strips protocol prefix from UUIDs
        let externalId = self.calendarItemExternalIdentifier.replacingOccurrences(
            of: "x-apple-reminder://",
            with: ""
        )
        // ... full encoding logic
    }
}

extension EKCalendar: @retroactive Encodable {
    // Encodes: title, uuid, allowsContentModifications, type, source, isPrimary
}
```

### UUID Format Handling

**Critical Pattern** - Reminders have UUIDs in two formats:

1. **Internal format**: `"x-apple-reminder://ABC123"`
2. **API format**: `"ABC123"` (prefix stripped)

**Handling code** (`Reminders.swift:698-753`):

```swift
func getReminder(from reminders: [EKReminder], at indexOrUUID: String) -> EKReminder? {
    // Try numeric index first
    if let index = Int(indexOrUUID) {
        return reminders[safe: index]
    }

    // Handle UUID with or without prefix
    let prefix = "x-apple-reminder://"
    let fullUUID = indexOrUUID.hasPrefix(prefix) ? indexOrUUID : "\(prefix)\(indexOrUUID)"

    // Try calendarItemExternalIdentifier
    if let reminder = reminders.first(where: { $0.calendarItemExternalIdentifier == fullUUID }) {
        return reminder
    }

    // For backward compatibility
    if let reminder = reminders.first(where: { $0.calendarItemExternalIdentifier == indexOrUUID }) {
        return reminder
    }

    // Try calendarItemIdentifier
    return reminders.first(where: { $0.calendarItemIdentifier == indexOrUUID })
}
```

### Async/Sync Bridging Pattern

**DispatchSemaphore Pattern** (used throughout codebase):

```swift
// Example from Reminders.showAllReminders
func showAllReminders(...) {
    let semaphore = DispatchSemaphore(value: 0)

    self.reminders(on: self.getCalendars(), displayOptions: displayOptions) { reminders in
        // Process reminders...
        semaphore.signal()
    }

    semaphore.wait()
}
```

**For MCP async/await integration**:

```swift
// Convert EventKit callback to async
func getRemindersAsync(
    on calendars: [EKCalendar],
    displayOptions: DisplayOptions
) async throws -> [EKReminder] {
    return try await withCheckedThrowingContinuation { continuation in
        reminders(on: calendars, displayOptions: displayOptions) { reminders in
            continuation.resume(returning: reminders)
        }
    }
}
```

### WebhookManager Change Detection Pattern

**EventKit Notification Observer** (`Sources/RemindersLibrary/WebhookManager.swift:234-249`):

```swift
// Register for EventKit change notifications
NotificationCenter.default.addObserver(
    self,
    selector: #selector(reminderStoreChanged),
    name: NSNotification.Name.EKEventStoreChanged,
    object: remindersService.store
)

@objc private func reminderStoreChanged(_ notification: Notification) {
    // Fetch all reminders to check for changes
    remindersService.reminders(on: remindersService.getCalendars(), displayOptions: .all) { reminders in
        self.processChangedReminders(reminders: reminders)
    }
}
```

**Change Detection Logic** (`WebhookManager.swift:376-448`):
- Maintains `previousReminders` dictionary by UUID
- Compares current vs previous to detect: created, updated, deleted, completed, uncompleted
- Uses `lastModifiedDate` to detect updates
- Dispatches filtered webhooks based on `WebhookFilter`

### Search Implementation from REST API

**Search Parameters** (`Sources/reminders-api/main.swift:912-931`):

```swift
struct SearchParameters {
    var lists: [String]?  // Names or UUIDs
    var excludeLists: [String]?
    var calendars: [String]?
    var excludeCalendars: [String]?
    var query: String?  // Text search in title/notes
    var completed: DisplayOptions
    var dueBefore: Date?
    var dueAfter: Date?
    var modifiedAfter: Date?
    var createdAfter: Date?
    var hasNotes: Bool?
    var hasDueDate: Bool?
    var priorities: [Priority]?
    var priorityMin: Int?
    var priorityMax: Int?
    var sortBy: String?  // title, dueDate, created, modified, priority, list
    var sortOrder: String?  // asc, desc
    var limit: Int?
}
```

**Filter Resolution** (`reminders-api/main.swift:1020-1029`):

```swift
// Resolve calendar by name or UUID
func resolveCalendar(identifier: String, remindersService: Reminders) -> EKCalendar? {
    // First try as UUID
    if let calendar = remindersService.calendar(withUUID: identifier) {
        return calendar
    }

    // Then try as name
    return remindersService.calendar(withName: identifier)
}
```

**Search Execution** (`reminders-api/main.swift:1032-1262`):
- Resolves calendars from lists/names/UUIDs
- Applies exclude filters
- Fetches all reminders from selected calendars
- Filters by: completion, text query, dates, notes, priority
- Sorts by specified field
- Applies limit

### Private API Access

**Extension Pattern** (`Sources/RemindersLibrary/EKReminder+PrivateAPI.swift` - not shown but referenced):

```swift
extension EKReminder {
    var isSubtask: Bool {
        // Uses private API via reflection
        return self.value(forKey: "isSubtask") as? Bool ?? false
    }

    var attachedUrl: URL? {
        // Private API for URL attachments
        return self.value(forKey: "attachedURL") as? URL
    }

    var mailUrl: URL? {
        // Private API for mail links
        return self.value(forKey: "mailURL") as? URL
    }

    var parentId: String? {
        // Private API for parent reminder ID
        return self.value(forKey: "parentIdentifier") as? String
    }
}
```

**Conditional Compilation**:
- Debug builds include private API support by default
- Release builds use EventKit only
- Graceful fallback when private frameworks unavailable

### Configuration Management

**Application Support Directory Pattern**:

```swift
let appSupportURL = FileManager.default.urls(
    for: .applicationSupportDirectory,
    in: .userDomainMask
).first!

let remindersDirectory = appSupportURL.appendingPathComponent(
    "reminders-cli",
    isDirectory: true
)

// Create directory if needed
try? FileManager.default.createDirectory(
    at: remindersDirectory,
    withIntermediateDirectories: true
)

// Configuration files:
// - webhooks.json
// - auth_config.json
// - (future) mcp_config.json
```

## REST API Patterns to Reuse

### Hummingbird HTTP Server Setup

**From `reminders-api/main.swift:97-153`**:

```swift
func startServer(hostname: String, port: Int, token: String?, requireAuth: Bool) {
    let remindersService = Reminders()

    let app = HBApplication(configuration: .init(
        address: .hostname(hostname, port: port),
        serverName: "RemindersAPI"
    ))

    // JSON encoder
    let jsonEncoder = JSONEncoder()
    jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    app.encoder = jsonEncoder

    // CORS middleware
    app.middleware.add(
        HBCORSMiddleware(
            allowOrigin: .all,
            allowHeaders: ["Content-Type", "Authorization"],
            allowMethods: [.GET, .POST, .PUT, .DELETE, .PATCH]
        )
    )

    // Route handlers...

    try! app.start()
    app.wait()
}
```

### Async Helper Pattern

**From `reminders-api/main.swift:799-835`**:

```swift
// Convert callback-based to async
func fetchReminders(
    from listName: String,
    displayOptions: DisplayOptions,
    remindersService: Reminders
) async throws -> [EKReminder] {
    return try await withCheckedThrowingContinuation { continuation in
        let calendar = remindersService.calendar(withName: listName)

        remindersService.reminders(on: [calendar], displayOptions: displayOptions) { reminders in
            continuation.resume(returning: reminders)
        }
    }
}

func fetchAllReminders(
    displayOptions: DisplayOptions,
    remindersService: Reminders
) async throws -> [EKReminder] {
    return try await withCheckedThrowingContinuation { continuation in
        let calendars = remindersService.getCalendars()

        remindersService.reminders(on: calendars, displayOptions: displayOptions) { reminders in
            continuation.resume(returning: reminders)
        }
    }
}
```

## Error Handling Patterns

### REST API Error Responses

```swift
// From reminders-api
throw HBHTTPError(.badRequest, message: "Missing list name")
throw HBHTTPError(.notFound, message: "Reminder not found")
throw HBHTTPError(.unauthorized, message: "Authentication required")
throw HBHTTPError(.internalServerError, message: error.localizedDescription)
```

### CLI Error Handling

```swift
// From CLI commands
print("Error: You need to grant reminders access")
print("No reminder at index \(index) on \(listName)")
exit(1)
```

### For MCP Server

Errors should be LLM-friendly:

```swift
struct MCPError: Error, Codable {
    let code: Int
    let message: String
    let data: [String: String]?

    static func permissionDenied() -> MCPError {
        MCPError(
            code: -32001,
            message: "Reminders access denied",
            data: [
                "suggestion": "Grant access in System Preferences > Privacy & Security > Reminders",
                "recoverable": "true"
            ]
        )
    }

    static func notFound(type: String, identifier: String) -> MCPError {
        MCPError(
            code: -32002,
            message: "\(type) not found",
            data: [
                "identifier": identifier,
                "suggestion": "Check that the \(type) exists and you have access to it"
            ]
        )
    }
}
```

## Code Style Guidelines

From `CLAUDE.md`:

- **Formatting**: 4-space indentation, opening braces on same line
- **Naming**: camelCase for variables/functions, PascalCase for types
- **Types**: Use structs for implementations, mark as private when appropriate
- **Imports**: Foundation first, then other modules
- **Error Handling**: Use descriptive error types
- **Extensions**: Prefer extensions for utility functions
- **Testing**: Use XCTUnwrap for handling optionals in tests

## Key Files Reference

### Existing Files to Reference

- `Sources/RemindersLibrary/Reminders.swift` - Core reminders service
- `Sources/RemindersLibrary/WebhookManager.swift` - Change detection patterns
- `Sources/RemindersLibrary/EKReminder+Encodable.swift` - JSON serialization
- `Sources/reminders-api/main.swift` - HTTP server patterns, search implementation
- `Package.swift` - Dependency and target configuration

### New Files to Create

- `Sources/reminders-mcp/main.swift` - MCP server entry point
- `Sources/RemindersLibrary/MCPServer.swift` - Core MCP server logic
- `Sources/RemindersLibrary/MCPTransport+Stdio.swift` - Stdio transport
- `Sources/RemindersLibrary/MCPTransport+HTTP.swift` - HTTP streaming transport
- `Sources/RemindersLibrary/MCPTools/ListsTool.swift` - Lists tool handler
- `Sources/RemindersLibrary/MCPTools/RemindersTool.swift` - Reminders tool handler
- `Sources/RemindersLibrary/MCPTools/SearchTool.swift` - Search tool handler
- `Sources/RemindersLibrary/MCPResources.swift` - Resource URI handlers
- `Tests/RemindersTests/MCPServerTests.swift` - Unit tests
- `Tests/RemindersTests/MCPIntegrationTests.swift` - Integration tests

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│         MCP Client (Claude Desktop, etc.)        │
└───────────────────┬─────────────────────────────┘
                    │
         ┌──────────┴──────────┐
         │                     │
    ┌────▼────┐         ┌─────▼─────┐
    │  Stdio  │         │   HTTP    │
    │Transport│         │ Streaming │
    └────┬────┘         └─────┬─────┘
         │                     │
         └──────────┬──────────┘
                    │
            ┌───────▼────────┐
            │   MCPServer    │
            │  (capabilities,│
            │   routing)     │
            └───────┬────────┘
                    │
        ┌───────────┼───────────┐
        │           │           │
    ┌───▼───┐   ┌──▼──┐   ┌────▼────┐
    │ Lists │   │Remin│   │ Search  │
    │ Tool  │   │ders │   │  Tool   │
    │       │   │Tool │   │         │
    └───┬───┘   └──┬──┘   └────┬────┘
        │          │           │
        └──────────┼───────────┘
                   │
         ┌─────────▼─────────┐
         │  RemindersLibrary │
         │   (shared core)   │
         └─────────┬─────────┘
                   │
         ┌─────────▼─────────┐
         │  EventKit / EKEventStore │
         │  (macOS Reminders DB)    │
         └──────────────────────────┘
```

## Performance Considerations

### Targets
- Single operations: < 500ms
- Search operations: < 2s
- List operations: < 200ms

### Optimization Strategies
- Reuse EventKit store instance
- Cache calendar metadata
- Limit search result sets (default 100, max 1000)
- Use display options to filter at EventKit level
- Avoid fetching completed reminders unless requested

### EventKit Limitations
- Fetch operations are callback-based (async wrapper needed)
- Not thread-safe (single shared store instance)
- Can be slow with large datasets (10,000+ reminders)
- No native pagination support

## Testing Strategy

### Unit Test Coverage
- Each tool handler with mock EventKit data
- UUID format handling (with/without prefix)
- Search filter combinations
- Error cases (permission denied, not found, etc.)
- Resource URI parsing

### Integration Test Coverage
- Full request/response cycle via stdio
- HTTP streaming connection
- Multi-tool sequences
- Change notification handling
- Bulk operation confirmation

### Manual Testing Checklist
- Claude Desktop integration
- Real EventKit operations
- Private API fields included
- Performance under load
- Error message clarity

## References

- MCP Swift SDK: https://github.com/modelcontextprotocol/swift-sdk
- MCP Specification: https://spec.modelcontextprotocol.io/
- EventKit Documentation: https://developer.apple.com/documentation/eventkit
- Swift Concurrency: https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html
