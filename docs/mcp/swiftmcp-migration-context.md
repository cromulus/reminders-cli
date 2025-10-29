# SwiftMCP Migration Context

## Overview

This document provides comprehensive context for migrating the reminders-cli MCP server from a custom implementation using `modelcontextprotocol/swift-sdk` + Hummingbird to a complete SwiftMCP-based solution.

## Current Implementation Analysis

### Architecture

**Current Stack:**
- **Protocol SDK**: `modelcontextprotocol/swift-sdk` (v0.10.0)
- **HTTP Server**: Hummingbird (v1.8.2)
- **Custom Code**: ~660 lines of transport and protocol handling

**Components:**
1. `RemindersMCPContext` - Business logic for tools/resources (450 lines)
2. `RemindersMCPServerFactory` - Server initialization (80 lines)
3. `HTTPServerTransport` - Custom actor-based transport (70 lines)
4. `RemindersMCPHTTPHandler` - HTTP/SSE session management (420 lines)
5. `ReminderResourceNotifier` - EventKit change notifications (90 lines)

### Current Files

```
Sources/RemindersLibrary/MCP/
├── HTTP/
│   ├── HTTPServerTransport.swift          (DELETE)
│   └── RemindersMCPHTTPHandler.swift      (DELETE)
├── RemindersMCPContext.swift              (REFACTOR/KEEP)
├── RemindersMCPServerFactory.swift        (DELETE)
└── ReminderResourceNotifier.swift         (DELETE)

Sources/reminders-mcp/
└── main.swift                              (REWRITE)

Sources/reminders-api/
└── main.swift                              (REMOVE MCP ENDPOINTS)
```

### What Works Well

- ✅ Tools: lists, reminders, search all functional
- ✅ Resources: URI patterns working
- ✅ Stdio transport: Solid, works with Claude Desktop
- ✅ HTTP transport: Functional SSE implementation
- ✅ Business logic: Clean separation in `RemindersMCPContext`

### Pain Points

- ⚠️ Custom HTTP/SSE implementation maintenance burden
- ⚠️ Manual session management complexity
- ⚠️ No built-in OAuth/bearer token support
- ⚠️ Duplicate transport code between stdio/HTTP
- ⚠️ Resource notification requires custom EventKit observer

## SwiftMCP Framework

### What is SwiftMCP?

SwiftMCP is a Swift macro-based framework that provides:
- **Macro-driven server definition** via `@MCPServer`
- **Automatic tool registration** via `@MCPTool`
- **Built-in transports**: Stdio and HTTP+SSE
- **Authentication**: Bearer tokens, OAuth providers
- **Discovery**: OpenAPI spec generation
- **Transport agnostic**: Same server, multiple transports

### Key Components

**1. @MCPServer Macro**
```swift
@MCPServer
class RemindersMCPServer {
    // Server metadata extracted from documentation
    // Tool methods defined here
}
```

**2. @MCPTool Macro**
```swift
@MCPTool
func createReminder(list: String, title: String) async throws -> Reminder {
    // Implementation
}
```

**3. Built-in Transports**
```swift
// Stdio
let transport = StdioTransport(server: server)
try transport.run()

// HTTP+SSE
let transport = HTTPSSETransport(server: server, port: 8080)
transport.authorizationHandler = { token in /* validate */ }
try transport.run()
```

### SwiftMCP Dependencies

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/Cocoanetics/SwiftMCP.git", branch: "main"),
    // Uses internally:
    // - swift-log (1.6.3)
    // - swift-argument-parser (1.5.1)
    // - swift-nio (2.83.0)
]
```

### SwiftMCP vs Current Implementation

| Feature | Current (Custom) | SwiftMCP |
|---------|-----------------|----------|
| Protocol handling | Manual JSON-RPC | Built-in |
| Stdio transport | Manual readline | Built-in |
| HTTP transport | Custom Hummingbird | Built-in HTTP+SSE |
| Session management | Manual actor | Built-in |
| OAuth/Bearer auth | None | Built-in |
| OpenAPI spec | None | Auto-generated |
| Discovery endpoints | None | Built-in /.well-known/ |
| Resource notifications | Custom EventKit observer | TBD |
| Code to maintain | ~660 lines | ~300 lines |

## Migration Strategy

### Approach: Complete Rewrite

**Rationale:**
- Macro-based approach fundamentally different from handler pattern
- No gradual migration path (can't mix both architectures)
- SwiftMCP transports not compatible with `modelcontextprotocol/swift-sdk` Server type
- Clean break allows removing all custom transport code

### What Gets Replaced

**DELETE (4 files, ~660 lines):**
1. `HTTPServerTransport.swift` - Replaced by SwiftMCP's built-in
2. `RemindersMCPHTTPHandler.swift` - Session management built-in
3. `RemindersMCPServerFactory.swift` - No longer needed
4. `ReminderResourceNotifier.swift` - Need alternative approach

**REWRITE (2 files):**
1. `reminders-mcp/main.swift` - Use SwiftMCP transport setup
2. MCP server class - Convert to `@MCPServer` macro-based

**REFACTOR (1 file):**
1. `RemindersMCPContext.swift` - Extract business logic into tool methods

**MODIFY (2 files):**
1. `Package.swift` - Change dependencies
2. `reminders-api/main.swift` - Remove MCP endpoints (lines 156-167)

### What Stays the Same

- ✅ `RemindersLibrary` core (Reminders class, EventKit integration)
- ✅ Tool functionality (lists, reminders, search)
- ✅ Resource URI patterns
- ✅ JSON serialization (EKReminder+Encodable)
- ✅ REST API in `reminders-api` (completely separate)

## Technical Considerations

### Resource Notifications

**Current Approach:**
```swift
// ReminderResourceNotifier observes EKEventStore changes
NotificationCenter.default.addObserver(
    forName: .EKEventStoreChanged,
    object: store,
    queue: nil
) { _ in
    server.notify(ResourceUpdatedNotification(...))
}
```

**SwiftMCP Approach:**
Need to determine if SwiftMCP supports resource change notifications or if we need a hybrid approach.

### Async/Await Integration

**Current:**
```swift
// Using withCheckedThrowingContinuation to bridge EventKit callbacks
func fetchReminders(...) async throws -> [EKReminder] {
    return try await withCheckedThrowingContinuation { continuation in
        reminders.reminders(...) { result in
            continuation.resume(returning: result)
        }
    }
}
```

**SwiftMCP:**
`@MCPTool` methods are naturally async, so same pattern applies.

### UUID Format Handling

**Must Preserve:**
```swift
// Both formats must work:
// - "x-apple-reminder://ABC123" (internal)
// - "ABC123" (API format)

func resolveUUID(_ input: String) -> String {
    let prefix = "x-apple-reminder://"
    return input.hasPrefix(prefix) ? input : "\(prefix)\(input)"
}
```

### Error Handling

**Current:**
```swift
enum RemindersMCPError: Error {
    case listNotFound(String)
    case reminderNotFound(String)

    var mcpError: MCPError { /* mapping */ }
}
```

**SwiftMCP:**
Tool methods can throw, but need to verify error serialization format.

## Implementation Examples

### Before: Handler Pattern

```swift
// Current approach
class ListsTool: MCPToolHandler {
    func handle(_ input: [String: Any]) async throws -> Any {
        guard let operation = input["operation"] as? String else {
            throw MCPError.invalidParams
        }
        // ... manual parsing
    }
}
```

### After: Macro Pattern

```swift
@MCPServer
class RemindersMCPServer {
    private let reminders: Reminders

    init() {
        self.reminders = Reminders()
    }

    /// Get all reminder lists
    @MCPTool
    func getLists() async throws -> ListsResponse {
        let calendars = reminders.getCalendars()
        return ListsResponse(lists: calendars)
    }

    /// Create a new reminder list
    /// - Parameter name: Name of the list to create
    @MCPTool
    func createList(name: String) async throws -> ListResponse {
        // Implementation
    }
}
```

### Transport Setup

**Before:**
```swift
// reminders-mcp/main.swift (old)
let (server, notifier) = await RemindersMCPServerFactory.makeServer(...)
let transport = StdioTransport()
try await server.start(transport: transport)
```

**After:**
```swift
// reminders-mcp/main.swift (new)
let server = RemindersMCPServer()

switch transportType {
case .stdio:
    let transport = StdioTransport(server: server)
    try transport.run()
case .http:
    let transport = HTTPSSETransport(server: server, port: port)
    try transport.run()
}
```

## Testing Strategy

### Unit Tests
- Test each `@MCPTool` method in isolation
- Mock `Reminders` service
- Verify input validation
- Verify error handling

### Integration Tests
- Test complete request/response cycles
- Test both stdio and HTTP transports
- Verify tool invocations work end-to-end
- Test resource access

### Manual Tests
- Claude Desktop integration (stdio)
- HTTP client testing (curl, Postman)
- Home Assistant integration (uses REST API, should be unaffected)

## Risk Assessment

### Low Risk
- ✅ REST API unaffected (separate from MCP)
- ✅ Core business logic reusable
- ✅ SwiftMCP is mature, community-maintained
- ✅ Can keep old implementation in git history

### Medium Risk
- ⚠️ Resource notification mechanism may need custom solution
- ⚠️ Documentation/examples for SwiftMCP limited
- ⚠️ Learning curve for macro-based approach

### Mitigation
- Create feature branch (done: `swiftmcp-migration`)
- Keep old code in git history for reference
- Implement incrementally: stdio first, then HTTP
- Comprehensive testing before merging to main

## Success Criteria

### Functional
- [ ] All three tools work (lists, reminders, search)
- [ ] Resource URIs resolve correctly
- [ ] Stdio transport works with Claude Desktop
- [ ] HTTP transport works with test clients
- [ ] Error messages are clear and helpful

### Non-Functional
- [ ] Code reduction: ~360 fewer lines
- [ ] Build time: Similar or better
- [ ] Performance: Similar or better
- [ ] Maintainability: Significantly better (no custom transport)

### Quality
- [ ] All tests pass
- [ ] No regressions in REST API
- [ ] Home Assistant integration unaffected
- [ ] Documentation updated

## References

- **SwiftMCP GitHub**: https://github.com/Cocoanetics/SwiftMCP
- **SwiftMCP Introduction**: https://www.cocoanetics.com/2025/03/introducing-swiftmcp/
- **MCP Specification**: https://spec.modelcontextprotocol.io/
- **Current Implementation**: See `docs/mcp/context.md`

## Next Steps

1. Create specification document (success criteria, acceptance tests)
2. Create implementation plan (step-by-step tasks)
3. Execute migration
4. Test thoroughly
5. Update documentation
6. Merge to main
