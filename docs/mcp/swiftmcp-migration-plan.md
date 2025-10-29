# SwiftMCP Migration Implementation Plan

## Overview

Step-by-step implementation plan for migrating reminders-cli MCP server to SwiftMCP framework.

## Prerequisites

- [x] Feature branch created: `swiftmcp-migration`
- [x] Merged `reminders-hassio-todo` branch
- [x] Current build verified working
- [x] Context document created
- [x] Specification document created

## Phase 1: Update Dependencies (15 minutes)

### Task 1.1: Modify Package.swift

**File:** `Package.swift`

**Changes:**
1. Add SwiftMCP dependency
2. Remove modelcontextprotocol/swift-sdk dependency
3. Update reminders-mcp target dependencies
4. Keep RemindersLibrary dependencies for API

**Actions:**
```swift
// REMOVE:
.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0"),

// ADD:
.package(url: "https://github.com/Cocoanetics/SwiftMCP.git", branch: "main"),
```

```swift
// UPDATE reminders-mcp target:
.executableTarget(
    name: "reminders-mcp",
    dependencies: [
        .product(name: "SwiftMCP", package: "SwiftMCP"),  // CHANGED
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        "RemindersLibrary"
    ]
),
```

```swift
// UPDATE RemindersLibrary target:
.target(
    name: "RemindersLibrary",
    dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Hummingbird", package: "hummingbird"),
        // REMOVE: .product(name: "MCP", package: "swift-sdk"),
    ]
),
```

**Validation:**
```bash
swift package resolve
swift package show-dependencies
```

### Task 1.2: Initial Build Test

**Command:**
```bash
swift build --target reminders-mcp
```

**Expected:** Build fails (expected - we haven't updated code yet)

---

## Phase 2: Create New MCP Server (3-4 hours)

### Task 2.1: Create Server Class File

**File:** `Sources/RemindersLibrary/MCP/RemindersMCPServer.swift` (NEW)

**Structure:**
```swift
import Foundation
import EventKit
import SwiftMCP

@MCPServer
public class RemindersMCPServer {
    private let reminders: Reminders
    private let verbose: Bool

    public init(verbose: Bool = false) {
        self.reminders = Reminders()
        self.verbose = verbose
    }

    // Lists tool methods
    // Reminders tool methods
    // Search tool method
    // Helper methods
}
```

### Task 2.2: Implement Lists Tool Methods

**Add to RemindersMCPServer:**

```swift
/// Get all reminder lists
@MCPTool("lists_get", "Get all reminder lists")
public func getLists() async throws -> ListsResponse {
    let calendars = reminders.getCalendars()
    return ListsResponse(lists: calendars)
}

/// Create a new reminder list
/// - Parameter name: Name of the new list
/// - Parameter source: Optional source name
@MCPTool("lists_create", "Create a new reminder list")
public func createList(name: String, source: String? = nil) async throws -> ListResponse {
    // Check if exists
    let existing = reminders.getCalendars()
    guard !existing.contains(where: { $0.title == name }) else {
        throw RemindersMCPError.listAlreadyExists(name)
    }

    // Create list
    reminders.newList(with: name, source: source)

    // Return created list
    guard let calendar = reminders.getCalendars().first(where: { $0.title == name }) else {
        throw RemindersMCPError.storeFailure("Failed to create list")
    }

    return ListResponse(list: calendar)
}

/// Delete a reminder list
/// - Parameter identifier: Name or UUID of list to delete
@MCPTool("lists_delete", "Delete a reminder list")
public func deleteList(identifier: String) async throws -> SuccessResponse {
    let calendar = try resolveCalendar(identifier)
    guard calendar.allowsContentModifications else {
        throw RemindersMCPError.listReadOnly(identifier)
    }

    try reminders.store.removeCalendar(calendar, commit: true)
    return SuccessResponse(success: true)
}
```

### Task 2.3: Implement Reminders Tool Methods

**Add to RemindersMCPServer:**

```swift
/// Create a new reminder
/// - Parameters:
///   - list: List name or UUID
///   - title: Reminder title
///   - notes: Optional notes
///   - dueDate: Optional ISO8601 due date
///   - priority: Priority level (none, low, medium, high)
@MCPTool("reminders_create", "Create a new reminder")
public func createReminder(
    list: String,
    title: String,
    notes: String? = nil,
    dueDate: String? = nil,
    priority: String = "none"
) async throws -> ReminderResponse {
    let calendar = try resolveCalendar(list)
    let priorityEnum = Priority(rawValue: priority) ?? .none

    var dueDateComponents: DateComponents? = nil
    if let dueDateStr = dueDate {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dueDateStr) {
            dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: date
            )
        }
    }

    let reminder = reminders.createReminder(
        title: title,
        notes: notes,
        calendar: calendar,
        dueDateComponents: dueDateComponents,
        priority: priorityEnum
    )

    return ReminderResponse(reminder: reminder)
}

/// Get a reminder by UUID
/// - Parameter uuid: Reminder UUID (with or without x-apple-reminder:// prefix)
@MCPTool("reminders_get", "Get a reminder by UUID")
public func getReminder(uuid: String) async throws -> ReminderResponse {
    let reminder = try resolveReminder(uuid: uuid)
    return ReminderResponse(reminder: reminder)
}

/// Update a reminder
/// - Parameters:
///   - uuid: Reminder UUID
///   - title: New title (optional)
///   - notes: New notes (optional)
///   - dueDate: New due date (optional)
///   - priority: New priority (optional)
///   - isCompleted: Completion status (optional)
@MCPTool("reminders_update", "Update a reminder")
public func updateReminder(
    uuid: String,
    title: String? = nil,
    notes: String? = nil,
    dueDate: String? = nil,
    priority: String? = nil,
    isCompleted: Bool? = nil
) async throws -> ReminderResponse {
    let reminder = try resolveReminder(uuid: uuid)

    if let title { reminder.title = title }
    if let notes { reminder.notes = notes }
    if let isCompleted { reminder.isCompleted = isCompleted }

    if let priorityStr = priority, let priorityEnum = Priority(rawValue: priorityStr) {
        reminder.priority = Int(priorityEnum.value.rawValue)
    }

    if let dueDateStr = dueDate {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dueDateStr) {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: date
            )
        }
    }

    try reminders.updateReminder(reminder)
    return ReminderResponse(reminder: reminder)
}

/// Delete a reminder
/// - Parameter uuid: Reminder UUID
@MCPTool("reminders_delete", "Delete a reminder")
public func deleteReminder(uuid: String) async throws -> SuccessResponse {
    let reminder = try resolveReminder(uuid: uuid)
    try reminders.deleteReminder(reminder)
    return SuccessResponse(success: true)
}

/// Mark a reminder as complete
/// - Parameter uuid: Reminder UUID
@MCPTool("reminders_complete", "Mark a reminder as complete")
public func completeReminder(uuid: String) async throws -> ReminderResponse {
    let reminder = try resolveReminder(uuid: uuid)
    try reminders.setReminderComplete(reminder, complete: true)
    return ReminderResponse(reminder: reminder)
}

/// Mark a reminder as incomplete
/// - Parameter uuid: Reminder UUID
@MCPTool("reminders_uncomplete", "Mark a reminder as incomplete")
public func uncompleteReminder(uuid: String) async throws -> ReminderResponse {
    let reminder = try resolveReminder(uuid: uuid)
    try reminders.setReminderComplete(reminder, complete: false)
    return ReminderResponse(reminder: reminder)
}

/// List reminders in a list
/// - Parameters:
///   - list: List name or UUID
///   - includeCompleted: Include completed reminders
@MCPTool("reminders_list", "List reminders in a list")
public func listReminders(
    list: String,
    includeCompleted: Bool = false
) async throws -> RemindersResponse {
    let calendar = try resolveCalendar(list)
    let displayOptions: DisplayOptions = includeCompleted ? .all : .incomplete

    return try await withCheckedThrowingContinuation { continuation in
        reminders.reminders(on: [calendar], displayOptions: displayOptions) { reminders in
            continuation.resume(returning: RemindersResponse(reminders: reminders))
        }
    }
}
```

### Task 2.4: Implement Search Tool Method

**Add to RemindersMCPServer:**

```swift
/// Search reminders with filters
/// - Parameters:
///   - query: Text search in title/notes
///   - lists: Filter by list names/UUIDs
///   - completed: Filter by completion status
///   - priority: Filter by priority levels
///   - dueBefore: Filter by due date before
///   - dueAfter: Filter by due date after
///   - hasNotes: Filter by presence of notes
///   - hasDueDate: Filter by presence of due date
///   - sortBy: Sort field (title, dueDate, priority)
///   - sortOrder: Sort order (asc, desc)
///   - limit: Maximum results
@MCPTool("search", "Search reminders with filters")
public func searchReminders(
    query: String? = nil,
    lists: [String]? = nil,
    completed: String? = nil,
    priority: [String]? = nil,
    dueBefore: String? = nil,
    dueAfter: String? = nil,
    hasNotes: Bool? = nil,
    hasDueDate: Bool? = nil,
    sortBy: String? = nil,
    sortOrder: String? = nil,
    limit: Int? = nil
) async throws -> SearchResponse {
    // Implementation reuses logic from RemindersMCPContext
    // (Full implementation details in actual code)

    // Parse parameters
    // Resolve calendars
    // Fetch and filter reminders
    // Sort and limit results

    return SearchResponse(reminders: filtered, count: filtered.count)
}
```

### Task 2.5: Add Helper Methods

**Add to RemindersMCPServer:**

```swift
// MARK: - Helper Methods

private func resolveCalendar(_ identifier: String) throws -> EKCalendar {
    // Try UUID first
    if let calendar = reminders.getCalendars().first(where: { $0.calendarIdentifier == identifier }) {
        return calendar
    }

    // Try name (case-insensitive)
    if let calendar = reminders.getCalendars().first(where: {
        $0.title.compare(identifier, options: .caseInsensitive) == .orderedSame
    }) {
        return calendar
    }

    throw RemindersMCPError.listNotFound(identifier)
}

private func resolveReminder(uuid: String) throws -> EKReminder {
    // Handle both UUID formats
    let cleanUUID = uuid.replacingOccurrences(of: "x-apple-reminder://", with: "")

    guard let reminder = reminders.getReminderByUUID(cleanUUID) else {
        throw RemindersMCPError.reminderNotFound(uuid)
    }

    return reminder
}

private func log(_ message: String) {
    guard verbose else { return }
    fputs("[RemindersMCPServer] \(message)\n", stderr)
}
```

### Task 2.6: Define Response Types

**Add to RemindersMCPServer.swift:**

```swift
// MARK: - Response Types

public struct ListsResponse: Codable {
    public let lists: [EKCalendar]
}

public struct ListResponse: Codable {
    public let list: EKCalendar
}

public struct ReminderResponse: Codable {
    public let reminder: EKReminder
}

public struct RemindersResponse: Codable {
    public let reminders: [EKReminder]
}

public struct SearchResponse: Codable {
    public let reminders: [EKReminder]
    public let count: Int
}

public struct SuccessResponse: Codable {
    public let success: Bool
}
```

### Task 2.7: Define Error Types

**Add to RemindersMCPServer.swift:**

```swift
// MARK: - Error Types

enum RemindersMCPError: Error, LocalizedError {
    case listNotFound(String)
    case listAlreadyExists(String)
    case listReadOnly(String)
    case reminderNotFound(String)
    case storeFailure(String)
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .listNotFound(let id):
            return "List not found: \(id)"
        case .listAlreadyExists(let name):
            return "List '\(name)' already exists"
        case .listReadOnly(let id):
            return "List '\(id)' is read-only"
        case .reminderNotFound(let uuid):
            return "Reminder not found: \(uuid)"
        case .storeFailure(let message):
            return "Store operation failed: \(message)"
        case .permissionDenied:
            return "Reminders access denied. Grant access in System Preferences > Privacy & Security > Reminders"
        }
    }
}
```

**Validation:**
```bash
swift build --target RemindersLibrary
```

---

## Phase 3: Update Entry Point (30 minutes)

### Task 3.1: Rewrite reminders-mcp/main.swift

**File:** `Sources/reminders-mcp/main.swift`

**Replace entire contents:**

```swift
import ArgumentParser
import Foundation
import RemindersLibrary
import SwiftMCP

@main
struct RemindersMCP: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "reminders-mcp",
        abstract: "MCP server for Apple Reminders",
        discussion: "Provides MCP protocol access to your macOS Reminders data."
    )

    enum TransportKind: String, ExpressibleByArgument {
        case stdio
        case http
    }

    @Option(name: [.customLong("transport")], help: "Transport type (stdio or http)")
    var transport: TransportKind = .stdio

    @Option(name: [.customShort("p"), .customLong("port")], help: "Port for HTTP transport")
    var port: Int = 8090

    @Option(name: [.customLong("host")], help: "Hostname for HTTP transport")
    var hostname: String = "127.0.0.1"

    @Flag(name: [.customLong("verbose")], help: "Enable verbose logging")
    var verbose: Bool = false

    func run() async throws {
        print("Requesting Reminders access...")
        let (granted, error) = Reminders.requestAccess()

        guard granted else {
            print("Error: Reminders access denied")
            if let error {
                print("Error: \(error.localizedDescription)")
            }
            print("Grant access in System Preferences > Privacy & Security > Reminders")
            Foundation.exit(1)
        }

        print("Reminders access granted")

        // Create MCP server
        let server = RemindersMCPServer(verbose: verbose)

        // Start appropriate transport
        switch transport {
        case .stdio:
            print("Starting MCP server with stdio transport...")
            let transport = StdioTransport(server: server)
            try transport.run()

        case .http:
            print("Starting MCP server with HTTP transport on \(hostname):\(port)...")
            let transport = HTTPSSETransport(server: server, port: port)
            try transport.run()
        }
    }
}
```

**Validation:**
```bash
swift build --target reminders-mcp
```

---

## Phase 4: Delete Old Files (5 minutes)

### Task 4.1: Remove Custom Transport Files

**Delete these files:**
```bash
rm Sources/RemindersLibrary/MCP/HTTP/HTTPServerTransport.swift
rm Sources/RemindersLibrary/MCP/HTTP/RemindersMCPHTTPHandler.swift
rm Sources/RemindersLibrary/MCP/RemindersMCPServerFactory.swift
rm Sources/RemindersLibrary/MCP/ReminderResourceNotifier.swift
```

**Validation:**
```bash
# Verify files deleted
ls Sources/RemindersLibrary/MCP/HTTP/
ls Sources/RemindersLibrary/MCP/
```

### Task 4.2: Remove MCP Directory if Empty

**Check:**
```bash
# If HTTP directory is empty:
rmdir Sources/RemindersLibrary/MCP/HTTP/
```

---

## Phase 5: Update REST API (15 minutes)

### Task 5.1: Remove MCP Endpoints from reminders-api

**File:** `Sources/reminders-api/main.swift`

**Remove lines 156-167:**
```swift
// DELETE:
// MCP Routes
app.router.post("mcp") { request in
    try await mcpHandler.handlePost(request)
}

app.router.get("mcp") { request in
    try await mcpHandler.handleStream(request)
}

app.router.delete("mcp") { request in
    try await mcpHandler.handleDelete(request)
}
```

**Remove line 103:**
```swift
// DELETE:
let mcpHandler = RemindersMCPHTTPHandler(reminders: remindersService)
```

**Remove import if only used for MCP:**
```swift
// Check if MCP is still imported, if only used for MCP handler:
// Consider removing: import MCP
```

**Validation:**
```bash
swift build --target reminders-api
```

---

## Phase 6: Build & Test (1-2 hours)

### Task 6.1: Full Build

**Commands:**
```bash
swift package clean
swift package resolve
swift build
```

**Expected:** All targets build successfully

### Task 6.2: Test Stdio Transport

**Start server:**
```bash
./.build/debug/reminders-mcp --transport stdio --verbose
```

**Test input (in another terminal):**
```json
{"jsonrpc":"2.0","id":1,"method":"tools/list"}
```

**Expected:** JSON response with list of tools

### Task 6.3: Test HTTP Transport

**Start server:**
```bash
./.build/debug/reminders-mcp --transport http --port 8090 --verbose
```

**Test with curl:**
```bash
curl -N http://localhost:8090/sse
```

**Expected:** SSE connection established

### Task 6.4: Test Tools

**Test lists GET:**
```json
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"lists_get","arguments":{}}}
```

**Test reminder CREATE:**
```json
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"reminders_create","arguments":{"list":"Reminders","title":"Test Reminder"}}}
```

### Task 6.5: Test REST API

**Start API server:**
```bash
./.build/debug/reminders-api --port 8080
```

**Test endpoint:**
```bash
curl http://localhost:8080/lists
```

**Expected:** REST API works unchanged

---

## Phase 7: Documentation (30 minutes)

### Task 7.1: Update CLAUDE.md

**File:** `CLAUDE.md`

**Update MCP Server section:**

```markdown
## MCP Server
The Model Context Protocol (MCP) server provides programmatic access to Reminders for LLMs and other MCP clients, powered by SwiftMCP.

### Build & Run Commands:
- Build MCP server: `swift build --product reminders-mcp`
- Run with stdio transport: `./.build/debug/reminders-mcp --transport stdio`
- Run with HTTP transport: `./.build/debug/reminders-mcp --transport http --port 8090`
- Enable verbose logging: `./.build/debug/reminders-mcp --verbose`

### Transport Options:
- **stdio**: JSON-RPC over stdin/stdout (recommended for Claude Desktop)
- **http**: HTTP+SSE streaming transport for remote clients

### Available Tools:
1. **lists_get**: Get all reminder lists
2. **lists_create**: Create a new list
3. **lists_delete**: Delete a list
4. **reminders_create**: Create a new reminder
5. **reminders_get**: Get reminder by UUID
6. **reminders_update**: Update a reminder
7. **reminders_delete**: Delete a reminder
8. **reminders_complete**: Mark reminder as complete
9. **reminders_uncomplete**: Mark reminder as incomplete
10. **reminders_list**: List reminders in a list
11. **search**: Advanced reminder search with filtering

### Claude Desktop Configuration:
```json
{
  "mcpServers": {
    "reminders": {
      "command": "/path/to/.build/debug/reminders-mcp",
      "args": ["--transport", "stdio"]
    }
  }
}
```

### HTTP Transport Features:
- Server-Sent Events (SSE) for streaming
- Session management
- Bearer token authentication (optional)
- OpenAPI spec generation (optional)

### Migration Notes:
- Migrated from modelcontextprotocol/swift-sdk to SwiftMCP
- Zero custom transport code - all handled by SwiftMCP framework
- Same functionality, better maintainability
```

### Task 7.2: Create Migration Summary

**File:** `docs/mcp/swiftmcp-migration-summary.md` (NEW)

**Contents:**
- What changed
- Why we migrated
- Benefits gained
- Breaking changes (if any)
- Before/after comparison

---

## Phase 8: Commit & Test (30 minutes)

### Task 8.1: Commit Changes

**Commands:**
```bash
git status
git add .
git commit -m "Migrate MCP server to SwiftMCP framework

- Replace modelcontextprotocol/swift-sdk with SwiftMCP
- Rewrite MCP server using @MCPServer and @MCPTool macros
- Delete custom HTTP transport implementation (~660 lines)
- Remove MCP endpoints from REST API
- Update documentation

Benefits:
- Reduced code by ~360 lines
- Zero custom transport maintenance
- Built-in OAuth/bearer token support
- OpenAPI spec generation
- Both stdio and HTTP handled by mature library"
```

### Task 8.2: Final Validation

**Checklist:**
- [ ] `swift build` succeeds
- [ ] Stdio transport works
- [ ] HTTP transport works
- [ ] Can create/read/update/delete reminders
- [ ] Search works
- [ ] REST API unaffected
- [ ] Claude Desktop integration works
- [ ] Documentation updated

---

## Rollback Procedure

If issues arise:

```bash
# Rollback to pre-migration state
git reset --hard rest_api_list_uuids

# Or revert specific commits
git revert HEAD~N  # N = number of migration commits
```

---

## Timeline

- Phase 1: 15 minutes (dependencies)
- Phase 2: 3-4 hours (new server)
- Phase 3: 30 minutes (entry point)
- Phase 4: 5 minutes (delete old)
- Phase 5: 15 minutes (update API)
- Phase 6: 1-2 hours (testing)
- Phase 7: 30 minutes (docs)
- Phase 8: 30 minutes (commit)

**Total: 7-11 hours**

---

## Next Steps After Completion

1. Merge to main branch
2. Test with Home Assistant integration
3. Consider adding OAuth for HTTP transport
4. Consider enabling OpenAPI spec generation
5. Monitor for any issues in production use
