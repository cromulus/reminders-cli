# MCP Server Implementation Plan

This document provides a detailed, step-by-step implementation plan for building the MCP server for Apple Reminders. Follow the phases in order for incremental, testable progress.

## Prerequisites

- [ ] Read `context.md` thoroughly
- [ ] Review `specification.md` acceptance criteria
- [ ] Ensure Swift 6.0+ and Xcode 16+ installed
- [ ] Verify reminders-cli builds successfully
- [ ] Run existing tests: `swift test`

## Phase 1: Project Setup & Dependencies

**Goal**: Add MCP SDK and create new executable target

**Estimated Time**: 2 hours

### Task 1.1: Update Package.swift

**File**: `Package.swift`

**Actions**:
1. Add MCP SDK to dependencies array:
```swift
dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "1.3.1")),
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", .upToNextMinor(from: "1.8.2")),
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0"),  // NEW
],
```

2. Add new executable product:
```swift
products: [
    .executable(name: "reminders", targets: ["reminders"]),
    .executable(name: "reminders-api", targets: ["reminders-api"]),
    .executable(name: "reminders-mcp", targets: ["reminders-mcp"]),  // NEW
],
```

3. Create new executable target:
```swift
.executableTarget(
    name: "reminders-mcp",
    dependencies: [
        .product(name: "MCP", package: "swift-sdk"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        "RemindersLibrary"
    ]
),
```

**Validation**:
```bash
swift package resolve
swift build --target reminders-mcp
```

### Task 1.2: Create Entry Point

**File**: `Sources/reminders-mcp/main.swift`

**Content**:
```swift
import ArgumentParser
import Foundation
import RemindersLibrary
import MCP

@main
struct RemindersM CP: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "reminders-mcp",
        abstract: "MCP server for Apple Reminders",
        discussion: "Provides MCP protocol access to your macOS Reminders data."
    )

    @Option(name: [.customLong("transport")], help: "Transport type (stdio or http)")
    var transport: String = "stdio"

    @Option(name: [.customShort("p"), .customLong("port")], help: "Port for HTTP transport")
    var port: Int = 8090

    @Option(name: [.customLong("host")], help: "Hostname for HTTP transport")
    var hostname: String = "127.0.0.1"

    @Flag(name: [.customLong("verbose")], help: "Enable verbose logging")
    var verbose: Bool = false

    func run() throws {
        // Check Reminders access
        print("Requesting Reminders access...")
        let (granted, error) = Reminders.requestAccess()

        guard granted else {
            print("Error: Reminders access denied")
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
            print("Grant access in System Preferences > Privacy & Security > Reminders")
            Foundation.exit(1)
        }

        print("Reminders access granted")
        print("Starting MCP server with \(transport) transport...")

        // Initialize server
        let server = try MCPServer(verbose: verbose)

        // Start appropriate transport
        switch transport.lowercased() {
        case "stdio":
            try server.startStdio()
        case "http":
            try server.startHTTP(hostname: hostname, port: port)
        default:
            print("Error: Unknown transport '\(transport)'. Use 'stdio' or 'http'")
            Foundation.exit(1)
        }
    }
}
```

**Validation**:
```bash
swift build --target reminders-mcp
./.build/debug/reminders-mcp --help
```

## Phase 2: MCP Server Foundation

**Goal**: Create core server infrastructure with capability declaration

**Estimated Time**: 6 hours

### Task 2.1: Create MCPServer Class

**File**: `Sources/RemindersLibrary/MCPServer.swift`

**Content**:
```swift
import Foundation
import EventKit
import MCP

public class MCPServer {
    private let remindersService: Reminders
    private let verbose: Bool

    // Tool and resource handlers
    private var toolHandlers: [String: MCPToolHandler] = [:]
    private var resourceHandlers: [String: MCPResourceHandler] = [:]

    public init(verbose: Bool = false) throws {
        self.verbose = verbose
        self.remindersService = Reminders()

        // Register tools
        registerTools()

        // Register resources
        registerResources()

        log("MCPServer initialized")
    }

    private func registerTools() {
        // Lists tool
        toolHandlers["lists"] = ListsTool(remindersService: remindersService, verbose: verbose)

        // Reminders tool
        toolHandlers["reminders"] = RemindersTool(remindersService: remindersService, verbose: verbose)

        // Search tool
        toolHandlers["search"] = SearchTool(remindersService: remindersService, verbose: verbose)

        log("Registered \(toolHandlers.count) tools")
    }

    private func registerResources() {
        // Resource URI patterns
        resourceHandlers["lists"] = ResourceHandler(remindersService: remindersService, verbose: verbose)
        resourceHandlers["list"] = ResourceHandler(remindersService: remindersService, verbose: verbose)
        resourceHandlers["uuid"] = ResourceHandler(remindersService: remindersService, verbose: verbose)

        log("Registered \(resourceHandlers.count) resource patterns")
    }

    // Start stdio transport
    public func startStdio() throws {
        log("Starting stdio transport")
        let transport = StdioTransport(
            toolHandlers: toolHandlers,
            resourceHandlers: resourceHandlers,
            verbose: verbose
        )
        try transport.start()
    }

    // Start HTTP transport
    public func startHTTP(hostname: String, port: Int) throws {
        log("Starting HTTP transport on \(hostname):\(port)")
        let transport = HTTPTransport(
            hostname: hostname,
            port: port,
            toolHandlers: toolHandlers,
            resourceHandlers: resourceHandlers,
            verbose: verbose
        )
        try transport.start()
    }

    private func log(_ message: String) {
        if verbose {
            print("[MCPServer] \(message)")
        }
    }
}

// Protocol for tool handlers
public protocol MCPToolHandler {
    func handle(_ input: [String: Any]) async throws -> Any
    var schema: [String: Any] { get }
}

// Protocol for resource handlers
public protocol MCPResourceHandler {
    func handle(uri: String) async throws -> Any
}
```

**Validation**: Build succeeds (no runtime test yet)

### Task 2.2: Implement Stdio Transport

**File**: `Sources/RemindersLibrary/MCPTransport+Stdio.swift`

**Content**:
```swift
import Foundation
import MCP

class StdioTransport {
    private let toolHandlers: [String: MCPToolHandler]
    private let resourceHandlers: [String: MCPResourceHandler]
    private let verbose: Bool

    init(
        toolHandlers: [String: MCPToolHandler],
        resourceHandlers: [String: MCPResourceHandler],
        verbose: Bool
    ) {
        self.toolHandlers = toolHandlers
        self.resourceHandlers = resourceHandlers
        self.verbose = verbose
    }

    func start() throws {
        log("Stdio transport started, listening on stdin")

        // Read from stdin line by line
        while let line = readLine() {
            log("Received: \(line)")

            // Parse JSON-RPC request
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let method = json["method"] as? String,
                  let id = json["id"] else {
                log("Invalid JSON-RPC request")
                continue
            }

            // Handle request asynchronously
            Task {
                do {
                    let result = try await handleRequest(method: method, params: json["params"] as? [String: Any])
                    sendResponse(id: id, result: result)
                } catch {
                    sendError(id: id, error: error)
                }
            }
        }
    }

    private func handleRequest(method: String, params: [String: Any]?) async throws -> Any {
        switch method {
        case "tools/list":
            return listTools()

        case "tools/call":
            guard let params = params,
                  let toolName = params["name"] as? String,
                  let handler = toolHandlers[toolName] else {
                throw MCPError.toolNotFound
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            return try await handler.handle(arguments)

        case "resources/list":
            return listResources()

        case "resources/read":
            guard let params = params,
                  let uri = params["uri"] as? String else {
                throw MCPError.invalidParams
            }
            return try await handleResource(uri: uri)

        default:
            throw MCPError.methodNotFound
        }
    }

    private func listTools() -> [String: Any] {
        let tools = toolHandlers.map { name, handler in
            [
                "name": name,
                "description": "Tool for \(name) operations",
                "inputSchema": handler.schema
            ]
        }
        return ["tools": tools]
    }

    private func listResources() -> [String: Any] {
        let resources = [
            ["uri": "reminders://lists", "name": "All reminder lists"],
            ["uri": "reminders://list/{name}", "name": "Reminders in specific list"],
            ["uri": "reminders://uuid/{id}", "name": "Single reminder by UUID"]
        ]
        return ["resources": resources]
    }

    private func handleResource(uri: String) async throws -> Any {
        // Parse URI pattern
        if uri == "reminders://lists" {
            return try await resourceHandlers["lists"]!.handle(uri: uri)
        } else if uri.hasPrefix("reminders://list/") {
            return try await resourceHandlers["list"]!.handle(uri: uri)
        } else if uri.hasPrefix("reminders://uuid/") {
            return try await resourceHandlers["uuid"]!.handle(uri: uri)
        } else {
            throw MCPError.resourceNotFound
        }
    }

    private func sendResponse(id: Any, result: Any) {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ]
        sendJSON(response)
    }

    private func sendError(id: Any, error: Error) {
        let mcpError = error as? MCPError ?? MCPError.internalError(error.localizedDescription)
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": mcpError.code,
                "message": mcpError.message,
                "data": mcpError.data ?? [:]
            ]
        ]
        sendJSON(response)
    }

    private func sendJSON(_ json: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: json),
           let string = String(data: data, encoding: .utf8) {
            print(string)
            fflush(stdout)
            log("Sent: \(string)")
        }
    }

    private func log(_ message: String) {
        if verbose {
            fputs("[Stdio] \(message)\n", stderr)
            fflush(stderr)
        }
    }
}

// MCP Error types
enum MCPError: Error {
    case toolNotFound
    case resourceNotFound
    case methodNotFound
    case invalidParams
    case internalError(String)
    case permissionDenied
    case notFound(String)

    var code: Int {
        switch self {
        case .toolNotFound, .resourceNotFound, .methodNotFound: return -32601
        case .invalidParams: return -32602
        case .internalError: return -32603
        case .permissionDenied: return -32001
        case .notFound: return -32002
        }
    }

    var message: String {
        switch self {
        case .toolNotFound: return "Tool not found"
        case .resourceNotFound: return "Resource not found"
        case .methodNotFound: return "Method not found"
        case .invalidParams: return "Invalid parameters"
        case .internalError(let msg): return "Internal error: \(msg)"
        case .permissionDenied: return "Reminders access denied"
        case .notFound(let type): return "\(type) not found"
        }
    }

    var data: [String: String]? {
        switch self {
        case .permissionDenied:
            return [
                "suggestion": "Grant access in System Preferences > Privacy & Security > Reminders",
                "recoverable": "true"
            ]
        case .notFound(let type):
            return ["type": type]
        default:
            return nil
        }
    }
}
```

**Validation**: Build succeeds

### Task 2.3: Implement HTTP Streaming Transport

**File**: `Sources/RemindersLibrary/MCPTransport+HTTP.swift`

**Content**:
```swift
import Foundation
import Hummingbird
import HummingbirdFoundation

class HTTPTransport {
    private let hostname: String
    private let port: Int
    private let toolHandlers: [String: MCPToolHandler]
    private let resourceHandlers: [String: MCPResourceHandler]
    private let verbose: Bool

    init(
        hostname: String,
        port: Int,
        toolHandlers: [String: MCPToolHandler],
        resourceHandlers: [String: MCPResourceHandler],
        verbose: Bool
    ) {
        self.hostname = hostname
        self.port = port
        self.toolHandlers = toolHandlers
        self.resourceHandlers = resourceHandlers
        self.verbose = verbose
    }

    func start() throws {
        let app = HBApplication(configuration: .init(
            address: .hostname(hostname, port: port),
            serverName: "RemindersM CP"
        ))

        // CORS middleware
        app.middleware.add(
            HBCORSMiddleware(
                allowOrigin: .all,
                allowHeaders: ["Content-Type"],
                allowMethods: [.GET, .POST]
            )
        )

        log("HTTP transport configured on \(hostname):\(port)")

        // MCP endpoint
        app.router.post("mcp") { request -> HBResponse in
            // Handle MCP request via HTTP POST
            // Similar to stdio but over HTTP
            return HBResponse(status: .ok)
        }

        print("MCP server running on http://\(hostname):\(port)/mcp")

        try app.start()
        app.wait()
    }

    private func log(_ message: String) {
        if verbose {
            print("[HTTP] \(message)")
        }
    }
}
```

**Validation**: Build succeeds

## Phase 3: Tool Implementations

**Goal**: Implement all three tools (lists, reminders, search)

**Estimated Time**: 12 hours

### Task 3.1: Lists Tool

**File**: `Sources/RemindersLibrary/MCPTools/ListsTool.swift`

**Content**:
```swift
import Foundation
import EventKit

class ListsTool: MCPToolHandler {
    private let remindersService: Reminders
    private let verbose: Bool

    init(remindersService: Reminders, verbose: Bool) {
        self.remindersService = remindersService
        self.verbose = verbose
    }

    var schema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "operation": [
                    "type": "string",
                    "enum": ["get", "create", "delete"],
                    "description": "Operation to perform"
                ],
                "name": [
                    "type": "string",
                    "description": "List name (required for create/delete)"
                ]
            ],
            "required": ["operation"]
        ]
    }

    func handle(_ input: [String: Any]) async throws -> Any {
        guard let operation = input["operation"] as? String else {
            throw MCPError.invalidParams
        }

        log("Lists tool: operation=\(operation)")

        switch operation {
        case "get":
            return try await getLists()
        case "create":
            guard let name = input["name"] as? String else {
                throw MCPError.invalidParams
            }
            return try await createList(name: name)
        case "delete":
            guard let name = input["name"] as? String else {
                throw MCPError.invalidParams
            }
            return try await deleteList(name: name)
        default:
            throw MCPError.invalidParams
        }
    }

    private func getLists() async throws -> Any {
        let calendars = remindersService.getCalendars()

        // Use EKCalendar+Encodable for JSON serialization
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(calendars)

        if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return ["lists": json]
        }

        throw MCPError.internalError("Failed to encode lists")
    }

    private func createList(name: String) async throws -> Any {
        // Check if list already exists
        let existing = remindersService.getCalendars()
        if existing.contains(where: { $0.title == name }) {
            throw MCPError.internalError("List '\(name)' already exists")
        }

        // Create new list (synchronous operation)
        remindersService.newList(with: name, source: nil)

        // Return the created list
        if let calendar = remindersService.getCalendars().first(where: { $0.title == name }) {
            let encoder = JSONEncoder()
            let data = try encoder.encode(calendar)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return ["list": json]
            }
        }

        throw MCPError.internalError("Failed to create list")
    }

    private func deleteList(name: String) async throws -> Any {
        // TODO: Implement list deletion
        // Note: Requires EKEventStore.removeCalendar
        throw MCPError.internalError("List deletion not yet implemented")
    }

    private func log(_ message: String) {
        if verbose {
            print("[ListsTool] \(message)")
        }
    }
}
```

**Validation**: Build succeeds

### Task 3.2: Reminders Tool

**File**: `Sources/RemindersLibrary/MCPTools/RemindersTool.swift`

**Content**:
```swift
import Foundation
import EventKit

class RemindersTool: MCPToolHandler {
    private let remindersService: Reminders
    private let verbose: Bool

    init(remindersService: Reminders, verbose: Bool) {
        self.remindersService = remindersService
        self.verbose = verbose
    }

    var schema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "operation": [
                    "type": "string",
                    "enum": ["create", "get", "update", "delete", "complete", "uncomplete", "list"],
                    "description": "Operation to perform"
                ],
                "list": [
                    "type": "string",
                    "description": "List name or UUID (for create/list)"
                ],
                "uuid": [
                    "type": "string",
                    "description": "Reminder UUID (for get/update/delete/complete/uncomplete)"
                ],
                "title": [
                    "type": "string",
                    "description": "Reminder title"
                ],
                "notes": [
                    "type": "string",
                    "description": "Reminder notes"
                ],
                "dueDate": [
                    "type": "string",
                    "description": "ISO8601 due date"
                ],
                "priority": [
                    "type": "string",
                    "enum": ["none", "low", "medium", "high"]
                ],
                "isCompleted": [
                    "type": "boolean"
                ]
            ],
            "required": ["operation"]
        ]
    }

    func handle(_ input: [String: Any]) async throws -> Any {
        guard let operation = input["operation"] as? String else {
            throw MCPError.invalidParams
        }

        log("Reminders tool: operation=\(operation)")

        switch operation {
        case "create":
            return try await createReminder(input)
        case "get":
            return try await getReminder(input)
        case "update":
            return try await updateReminder(input)
        case "delete":
            return try await deleteReminder(input)
        case "complete":
            return try await setComplete(input, complete: true)
        case "uncomplete":
            return try await setComplete(input, complete: false)
        case "list":
            return try await listReminders(input)
        default:
            throw MCPError.invalidParams
        }
    }

    private func createReminder(_ input: [String: Any]) async throws -> Any {
        guard let listIdentifier = input["list"] as? String,
              let title = input["title"] as? String else {
            throw MCPError.invalidParams
        }

        // Resolve list by name or UUID
        let calendar = remindersService.calendar(withName: listIdentifier)

        // Parse optional fields
        let notes = input["notes"] as? String
        let priorityStr = input["priority"] as? String ?? "none"
        let priority = Priority(rawValue: priorityStr) ?? .none

        // Parse due date
        var dueDateComponents: DateComponents? = nil
        if let dueDateStr = input["dueDate"] as? String {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: dueDateStr) {
                dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: date
                )
            }
        }

        // Create reminder
        let reminder = remindersService.createReminder(
            title: title,
            notes: notes,
            calendar: calendar,
            dueDateComponents: dueDateComponents,
            priority: priority
        )

        // Encode and return
        return try encodeReminder(reminder)
    }

    private func getReminder(_ input: [String: Any]) async throws -> Any {
        guard let uuid = input["uuid"] as? String else {
            throw MCPError.invalidParams
        }

        guard let reminder = remindersService.getReminderByUUID(uuid) else {
            throw MCPError.notFound("Reminder")
        }

        return try encodeReminder(reminder)
    }

    private func updateReminder(_ input: [String: Any]) async throws -> Any {
        guard let uuid = input["uuid"] as? String else {
            throw MCPError.invalidParams
        }

        guard let reminder = remindersService.getReminderByUUID(uuid) else {
            throw MCPError.notFound("Reminder")
        }

        // Update fields if provided
        if let title = input["title"] as? String {
            reminder.title = title
        }
        if let notes = input["notes"] as? String {
            reminder.notes = notes
        }
        if let isCompleted = input["isCompleted"] as? Bool {
            reminder.isCompleted = isCompleted
        }
        if let priorityStr = input["priority"] as? String,
           let priority = Priority(rawValue: priorityStr) {
            reminder.priority = Int(priority.value.rawValue)
        }
        if let dueDateStr = input["dueDate"] as? String {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: dueDateStr) {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: date
                )
            }
        }

        // Save changes
        try remindersService.updateReminder(reminder)

        return try encodeReminder(reminder)
    }

    private func deleteReminder(_ input: [String: Any]) async throws -> Any {
        guard let uuid = input["uuid"] as? String else {
            throw MCPError.invalidParams
        }

        guard let reminder = remindersService.getReminderByUUID(uuid) else {
            throw MCPError.notFound("Reminder")
        }

        try remindersService.deleteReminder(reminder)

        return ["success": true]
    }

    private func setComplete(_ input: [String: Any], complete: Bool) async throws -> Any {
        guard let uuid = input["uuid"] as? String else {
            throw MCPError.invalidParams
        }

        guard let reminder = remindersService.getReminderByUUID(uuid) else {
            throw MCPError.notFound("Reminder")
        }

        try remindersService.setReminderComplete(reminder, complete: complete)

        return try encodeReminder(reminder)
    }

    private func listReminders(_ input: [String: Any]) async throws -> Any {
        guard let listIdentifier = input["list"] as? String else {
            throw MCPError.invalidParams
        }

        let calendar = remindersService.calendar(withName: listIdentifier)
        let displayOptions = DisplayOptions.incomplete

        return try await withCheckedThrowingContinuation { continuation in
            remindersService.reminders(on: [calendar], displayOptions: displayOptions) { reminders in
                do {
                    let encoded = try self.encodeReminders(reminders)
                    continuation.resume(returning: encoded)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func encodeReminder(_ reminder: EKReminder) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(reminder)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPError.internalError("Failed to encode reminder")
        }

        return ["reminder": json]
    }

    private func encodeReminders(_ reminders: [EKReminder]) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(reminders)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw MCPError.internalError("Failed to encode reminders")
        }

        return ["reminders": json]
    }

    private func log(_ message: String) {
        if verbose {
            print("[RemindersTool] \(message)")
        }
    }
}
```

**Validation**: Build succeeds

### Task 3.3: Search Tool

**File**: `Sources/RemindersLibrary/MCPTools/SearchTool.swift`

**Content**:
```swift
import Foundation
import EventKit

class SearchTool: MCPToolHandler {
    private let remindersService: Reminders
    private let verbose: Bool

    init(remindersService: Reminders, verbose: Bool) {
        self.remindersService = remindersService
        self.verbose = verbose
    }

    var schema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "query": ["type": "string"],
                "lists": ["type": "array", "items": ["type": "string"]],
                "completed": ["type": "string", "enum": ["all", "true", "false"]],
                "priority": ["type": "array", "items": ["type": "string"]],
                "dueBefore": ["type": "string"],
                "dueAfter": ["type": "string"],
                "hasNotes": ["type": "boolean"],
                "hasDueDate": ["type": "boolean"],
                "sortBy": ["type": "string"],
                "sortOrder": ["type": "string"],
                "limit": ["type": "integer"]
            ]
        ]
    }

    func handle(_ input: [String: Any]) async throws -> Any {
        log("Search tool invoked with \(input.count) parameters")

        // Parse search parameters
        let params = parseSearchParameters(input)

        // Execute search (reuse logic from reminders-api)
        let results = try await executeSearch(params)

        // Encode results
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(results)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw MCPError.internalError("Failed to encode search results")
        }

        return ["reminders": json, "count": results.count]
    }

    private func parseSearchParameters(_ input: [String: Any]) -> SearchParameters {
        // Extract and parse all search parameters
        // This mirrors the logic from reminders-api/main.swift parseSearchParameters

        let lists = input["lists"] as? [String]
        let query = input["query"] as? String

        // Parse completed status
        let completedStr = input["completed"] as? String ?? "false"
        let completed: DisplayOptions
        switch completedStr {
        case "true": completed = .complete
        case "false": completed = .incomplete
        default: completed = .all
        }

        // Parse dates
        let formatter = ISO8601DateFormatter()
        let dueBefore = (input["dueBefore"] as? String).flatMap { formatter.date(from: $0) }
        let dueAfter = (input["dueAfter"] as? String).flatMap { formatter.date(from: $0) }

        // Parse boolean flags
        let hasNotes = input["hasNotes"] as? Bool
        let hasDueDate = input["hasDueDate"] as? Bool

        // Parse priority
        let priorities: [Priority]?
        if let priorityArray = input["priority"] as? [String] {
            priorities = priorityArray.compactMap { Priority(rawValue: $0) }
        } else {
            priorities = nil
        }

        // Parse sorting
        let sortBy = input["sortBy"] as? String
        let sortOrder = input["sortOrder"] as? String

        // Parse limit
        let limit = input["limit"] as? Int

        return SearchParameters(
            lists: lists,
            excludeLists: nil,
            calendars: nil,
            excludeCalendars: nil,
            query: query,
            completed: completed,
            dueBefore: dueBefore,
            dueAfter: dueAfter,
            modifiedAfter: nil,
            createdAfter: nil,
            hasNotes: hasNotes,
            hasDueDate: hasDueDate,
            priorities: priorities,
            priorityMin: nil,
            priorityMax: nil,
            sortBy: sortBy,
            sortOrder: sortOrder,
            limit: limit
        )
    }

    private func executeSearch(_ params: SearchParameters) async throws -> [EKReminder] {
        return try await withCheckedThrowingContinuation { continuation in
            // Determine calendars to search
            var calendarsToSearch: [EKCalendar] = []

            if let lists = params.lists {
                for identifier in lists {
                    if let calendar = remindersService.calendar(withUUID: identifier)
                        ?? remindersService.getCalendars().first(where: { $0.title == identifier }) {
                        calendarsToSearch.append(calendar)
                    }
                }
            } else {
                calendarsToSearch = remindersService.getCalendars()
            }

            // Fetch reminders
            remindersService.reminders(on: calendarsToSearch, displayOptions: .all) { reminders in
                var filtered = reminders

                // Apply filters
                filtered = filtered.filter { reminder in
                    self.remindersService.shouldDisplay(reminder: reminder, displayOptions: params.completed)
                }

                // Text query filter
                if let query = params.query, !query.isEmpty {
                    filtered = filtered.filter { reminder in
                        (reminder.title?.localizedCaseInsensitiveContains(query) ?? false) ||
                        (reminder.notes?.localizedCaseInsensitiveContains(query) ?? false)
                    }
                }

                // Date filters
                if let dueBefore = params.dueBefore {
                    filtered = filtered.filter { reminder in
                        guard let dueDate = reminder.dueDateComponents?.date else { return false }
                        return dueDate < dueBefore
                    }
                }

                if let dueAfter = params.dueAfter {
                    filtered = filtered.filter { reminder in
                        guard let dueDate = reminder.dueDateComponents?.date else { return false }
                        return dueDate > dueAfter
                    }
                }

                // Notes filter
                if let hasNotes = params.hasNotes {
                    filtered = filtered.filter { reminder in
                        let hasContent = reminder.notes != nil && !reminder.notes!.isEmpty
                        return hasNotes ? hasContent : !hasContent
                    }
                }

                // Due date filter
                if let hasDueDate = params.hasDueDate {
                    filtered = filtered.filter { reminder in
                        let hasDue = reminder.dueDateComponents != nil
                        return hasDueDate ? hasDue : !hasDue
                    }
                }

                // Priority filter
                if let priorities = params.priorities, !priorities.isEmpty {
                    filtered = filtered.filter { reminder in
                        let reminderPriority = Priority(reminder.mappedPriority) ?? .none
                        return priorities.contains(reminderPriority)
                    }
                }

                // Apply sorting
                if let sortBy = params.sortBy {
                    let ascending = params.sortOrder?.lowercased() != "desc"
                    filtered = self.sortReminders(filtered, by: sortBy, ascending: ascending)
                }

                // Apply limit
                if let limit = params.limit, limit > 0 {
                    filtered = Array(filtered.prefix(limit))
                }

                continuation.resume(returning: filtered)
            }
        }
    }

    private func sortReminders(_ reminders: [EKReminder], by field: String, ascending: Bool) -> [EKReminder] {
        return reminders.sorted { first, second in
            switch field.lowercased() {
            case "title":
                let firstTitle = first.title ?? ""
                let secondTitle = second.title ?? ""
                return ascending ? firstTitle < secondTitle : firstTitle > secondTitle

            case "duedate":
                let firstDate = first.dueDateComponents?.date
                let secondDate = second.dueDateComponents?.date
                switch (firstDate, secondDate) {
                case (nil, nil): return false
                case (nil, _): return !ascending
                case (_, nil): return ascending
                case (let first?, let second?):
                    return ascending ? first < second : first > second
                }

            case "priority":
                return ascending ? first.priority < second.priority : first.priority > second.priority

            default:
                return false
            }
        }
    }

    private func log(_ message: String) {
        if verbose {
            print("[SearchTool] \(message)")
        }
    }
}

// Search parameters struct (same as reminders-api)
struct SearchParameters {
    var lists: [String]?
    var excludeLists: [String]?
    var calendars: [String]?
    var excludeCalendars: [String]?
    var query: String?
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
    var sortBy: String?
    var sortOrder: String?
    var limit: Int?
}
```

**Validation**: Build succeeds

## Phase 4: Resource Implementations

**Goal**: Implement resource URI handlers

**Estimated Time**: 4 hours

### Task 4.1: Resource Handler

**File**: `Sources/RemindersLibrary/MCPResources.swift`

**Content**:
```swift
import Foundation
import EventKit

class ResourceHandler: MCPResourceHandler {
    private let remindersService: Reminders
    private let verbose: Bool

    init(remindersService: Reminders, verbose: Bool) {
        self.remindersService = remindersService
        self.verbose = verbose
    }

    func handle(uri: String) async throws -> Any {
        log("Handling resource URI: \(uri)")

        if uri == "reminders://lists" {
            return try await handleListsResource()
        } else if uri.hasPrefix("reminders://list/") {
            let identifier = String(uri.dropFirst("reminders://list/".count))
            return try await handleListResource(identifier: identifier)
        } else if uri.hasPrefix("reminders://uuid/") {
            let uuid = String(uri.dropFirst("reminders://uuid/".count))
            return try await handleUUIDResource(uuid: uuid)
        } else {
            throw MCPError.resourceNotFound
        }
    }

    private func handleListsResource() async throws -> Any {
        let calendars = remindersService.getCalendars()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(calendars)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw MCPError.internalError("Failed to encode lists")
        }

        return ["lists": json]
    }

    private func handleListResource(identifier: String) async throws -> Any {
        // Resolve by name or UUID
        let calendar = remindersService.calendar(withName: identifier)

        return try await withCheckedThrowingContinuation { continuation in
            remindersService.reminders(on: [calendar], displayOptions: .incomplete) { reminders in
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(reminders)

                    guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                        throw MCPError.internalError("Failed to encode reminders")
                    }

                    continuation.resume(returning: ["reminders": json])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func handleUUIDResource(uuid: String) async throws -> Any {
        guard let reminder = remindersService.getReminderByUUID(uuid) else {
            throw MCPError.notFound("Reminder")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(reminder)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPError.internalError("Failed to encode reminder")
        }

        return ["reminder": json]
    }

    private func log(_ message: String) {
        if verbose {
            print("[ResourceHandler] \(message)")
        }
    }
}
```

**Validation**: Build succeeds

## Phase 5: Testing

**Goal**: Comprehensive test coverage

**Estimated Time**: 6 hours

### Task 5.1: Unit Tests

**File**: `Tests/RemindersTests/MCPServerTests.swift`

**Content**:
```swift
import XCTest
@testable import RemindersLibrary

final class MCPServerTests: XCTestCase {
    func testListsToolSchema() throws {
        let tool = ListsTool(remindersService: Reminders(), verbose: false)
        let schema = tool.schema

        XCTAssertNotNil(schema["properties"])
        XCTAssertNotNil(schema["required"])
    }

    func testRemindersToolSchema() throws {
        let tool = RemindersTool(remindersService: Reminders(), verbose: false)
        let schema = tool.schema

        XCTAssertNotNil(schema["properties"])
    }

    func testSearchToolSchema() throws {
        let tool = SearchTool(remindersService: Reminders(), verbose: false)
        let schema = tool.schema

        XCTAssertNotNil(schema["properties"])
    }

    func testUUIDFormatHandling() throws {
        // Test that both UUID formats work
        let withPrefix = "x-apple-reminder://ABC123"
        let without Prefix = "ABC123"

        // Both should be handled correctly
        XCTAssertTrue(withPrefix.hasPrefix("x-apple-reminder://"))
        XCTAssertFalse(withoutPrefix.hasPrefix("x-apple-reminder://"))
    }

    func testResourceURIParsing() throws {
        let listsURI = "reminders://lists"
        let listURI = "reminders://list/Work"
        let uuidURI = "reminders://uuid/ABC123"

        XCTAssertTrue(listsURI == "reminders://lists")
        XCTAssertTrue(listURI.hasPrefix("reminders://list/"))
        XCTAssertTrue(uuidURI.hasPrefix("reminders://uuid/"))
    }
}
```

**Validation**:
```bash
swift test --filter MCPServerTests
```

### Task 5.2: Integration Tests

**File**: `Tests/RemindersTests/MCPIntegrationTests.swift`

**Content**:
```swift
import XCTest
@testable import RemindersLibrary

final class MCPIntegrationTests: XCTestCase {
    var server: MCPServer!

    override func setUp() async throws {
        // Note: These tests require Reminders access
        server = try MCPServer(verbose: true)
    }

    func testListsToolGetOperation() async throws {
        // This test requires real EventKit access
        // Skip if not granted
        let (granted, _) = Reminders.requestAccess()
        try XCTSkipUnless(granted, "Reminders access not granted")

        let tool = ListsTool(remindersService: Reminders(), verbose: true)
        let result = try await tool.handle(["operation": "get"])

        XCTAssertNotNil(result)
    }

    func testRemindersToolCreateAndDelete() async throws {
        let (granted, _) = Reminders.requestAccess()
        try XCTSkipUnless(granted, "Reminders access not granted")

        // Create a test reminder
        let tool = RemindersTool(remindersService: Reminders(), verbose: true)

        let createInput: [String: Any] = [
            "operation": "create",
            "list": "Reminders",
            "title": "MCP Test Reminder",
            "notes": "Created by integration test"
        ]

        let createResult = try await tool.handle(createInput) as! [String: Any]
        XCTAssertNotNil(createResult["reminder"])

        // Extract UUID and delete
        let reminderData = createResult["reminder"] as! [String: Any]
        let uuid = reminderData["uuid"] as! String

        let deleteInput: [String: Any] = [
            "operation": "delete",
            "uuid": uuid
        ]

        let deleteResult = try await tool.handle(deleteInput) as! [String: Any]
        XCTAssertEqual(deleteResult["success"] as? Bool, true)
    }
}
```

**Validation**:
```bash
swift test --filter MCPIntegrationTests
```

## Phase 6: Documentation & Deployment

**Goal**: Complete documentation and deployment setup

**Estimated Time**: 4 hours

### Task 6.1: Usage Documentation

**File**: `docs/MCP_SERVER.md`

**Content**: (Create comprehensive usage guide including installation, configuration, examples)

### Task 6.2: Update CLAUDE.md

**File**: `CLAUDE.md`

**Add section**:
```markdown
## MCP Server

The reminders-mcp executable provides an MCP (Model Context Protocol) server for Apple Reminders.

### Build Commands
- Build: `swift build --target reminders-mcp`
- Run stdio: `./.build/debug/reminders-mcp --transport stdio`
- Run HTTP: `./.build/debug/reminders-mcp --transport http --port 8090`

### Configuration
See `docs/MCP_SERVER.md` for detailed configuration and usage.

### Claude Desktop Integration
Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:
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
```

### Task 6.3: Create Deployment Script

**File**: `scripts/deploy-mcp.sh`

**Content**:
```bash
#!/bin/bash

# Build release version
swift build --configuration release --arch arm64 --arch x86_64

# Copy to /usr/local/bin
sudo cp ./.build/release/reminders-mcp /usr/local/bin/

echo "MCP server installed to /usr/local/bin/reminders-mcp"
echo "Configure Claude Desktop to use: reminders-mcp --transport stdio"
```

**Validation**: Run script and verify installation

## Validation Checklist

After completing all phases:

- [ ] `swift build` succeeds without warnings
- [ ] `swift test` passes all tests
- [ ] Stdio transport works with test client
- [ ] HTTP transport responds to requests
- [ ] Lists tool: get/create operations work
- [ ] Reminders tool: create/get/update/delete work
- [ ] Search tool: filters and sorting work
- [ ] Resources: all URI patterns resolve correctly
- [ ] Private API fields included in responses (debug build)
- [ ] Error messages are clear and helpful
- [ ] Performance meets targets (<500ms single ops, <2s search)
- [ ] Documentation is complete and accurate
- [ ] Claude Desktop integration tested

## Troubleshooting

**Build Errors**:
- Check Swift version: `swift --version` (should be 6.0+)
- Clean build: `swift package clean && swift build`
- Resolve packages: `swift package resolve`

**Runtime Errors**:
- Permission denied: Check System Preferences > Privacy > Reminders
- Tool not found: Verify tool registration in MCPServer.registerTools()
- JSON parse error: Check request format matches JSON-RPC 2.0

**Performance Issues**:
- Large dataset (>5000 reminders): Consider adding pagination
- Slow search: Check filter complexity and calendar count
- Memory usage: Profile with Instruments if needed

## Next Steps

After completing this implementation plan:

1. Deploy to production
2. Monitor error rates and performance
3. Gather feedback from LLM interactions
4. Consider enhancements (see specification.md "Future Enhancements")
5. Update documentation based on real-world usage

## Timeline Summary

- Phase 1: 2 hours
- Phase 2: 6 hours
- Phase 3: 12 hours
- Phase 4: 4 hours
- Phase 5: 6 hours
- Phase 6: 4 hours

**Total Estimated Time**: ~34 hours (5 working days)

**With buffer for debugging/iteration**: ~40 hours (6 working days / 1.5 weeks)
