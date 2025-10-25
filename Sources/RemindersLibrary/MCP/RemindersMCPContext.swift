import EventKit
import Foundation
import MCP

enum RemindersMCPError: Error {
    case listNotFound(String)
    case listAlreadyExists(String)
    case listReadOnly(String)
    case reminderNotFound(String)
    case invalidArguments(String)
    case storeFailure(String)
    case permissionDenied
    case noReminderSources
    case multipleSources([String])

    var mcpError: MCPError {
        switch self {
        case .invalidArguments(let message):
            return .invalidParams(message)
        case .listAlreadyExists(let name):
            return .serverError(code: -32000, message: "List '\(name)' already exists")
        case .listNotFound(let identifier):
            return .serverError(code: -32002, message: "List not found: \(identifier)")
        case .listReadOnly(let identifier):
            return .serverError(code: -32003, message: "List is read-only: \(identifier)")
        case .reminderNotFound(let uuid):
            return .serverError(code: -32004, message: "Reminder not found: \(uuid)")
        case .storeFailure(let message):
            return .internalError(message)
        case .permissionDenied:
            return .serverError(code: -32001, message: "Reminders access denied")
        case .noReminderSources:
            return .internalError("No reminder sources available")
        case .multipleSources(let sources):
            return .invalidParams(
                "Multiple reminder sources available. Specify source: \(sources.joined(separator: ", "))"
            )
        }
    }
}

struct RemindersMCPContext {
    private let reminders: Reminders
    private let verbose: Bool

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let isoDateFormatter: ISO8601DateFormatter

    init(reminders: Reminders, verbose: Bool) {
        self.reminders = reminders
        self.verbose = verbose

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        self.decoder = JSONDecoder()

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoDateFormatter = formatter
    }

    func listTools() -> [Tool] {
        return [
            Tool(
                name: "lists",
                description: "Create, delete, and list reminder lists",
                inputSchema: listsToolSchema()
            ),
            Tool(
                name: "reminders",
                description: "Create, update, or fetch reminders",
                inputSchema: remindersToolSchema()
            ),
            Tool(
                name: "search",
                description: "Search reminders using complex filters",
                inputSchema: searchToolSchema()
            )
        ]
    }

    func handleToolCall(name: String, arguments: [String: Value]?) async throws -> [Tool.Content] {
        switch name {
        case "lists":
            let payload: ListsInput = try decode(arguments)
            return try await handleListsTool(payload)
        case "reminders":
            let payload: RemindersInput = try decode(arguments)
            return try await handleRemindersTool(payload)
        case "search":
            let payload: SearchInput = try decode(arguments)
            return try await handleSearchTool(payload)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(name)")
        }
    }

    func listResources() throws -> [Resource] {
        [
            Resource(
                name: "All reminder lists",
                uri: "reminders://lists",
                description: "Collection of all reminder lists"
            ),
            Resource(
                name: "Reminders by list",
                uri: "reminders://list/{identifier}",
                description: "List reminders in a specific list by name or UUID"
            ),
            Resource(
                name: "Reminder by UUID",
                uri: "reminders://uuid/{uuid}",
                description: "A single reminder identified by UUID"
            )
        ]
    }

    func readResource(uri: String) async throws -> [Resource.Content] {
        if uri == "reminders://lists" {
            let calendars = reminders.getCalendars()
            return [try encodeResource(ListsResponse(lists: calendars), uri: uri)]
        } else if uri.hasPrefix("reminders://list/") {
            let identifier = String(uri.dropFirst("reminders://list/".count))
            let calendar = try resolveCalendar(identifier)
            let reminders = try await fetchReminders(on: [calendar], display: .all)
            return [try encodeResource(RemindersResponse(reminders: reminders), uri: uri)]
        } else if uri.hasPrefix("reminders://uuid/") {
            let uuid = String(uri.dropFirst("reminders://uuid/".count))
            let reminder = try resolveReminder(uuid: uuid)
            return [try encodeResource(ReminderResponse(reminder: reminder), uri: uri)]
        } else {
            throw MCPError.invalidParams("Unknown resource \(uri)")
        }
    }
}

// MARK: - Tool Schemas

private extension RemindersMCPContext {
    func listsToolSchema() -> Value {
        .object([
            "type": .string("object"),
            "properties": .object([
                "operation": .object([
                    "type": .string("string"),
                    "enum": .array([.string("get"), .string("create"), .string("delete")]),
                    "description": .string("Operation to perform")
                ]),
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Reminder list name or UUID")
                ]),
                "source": .object([
                    "type": .string("string"),
                    "description": .string("Optional reminders source when creating a new list")
                ])
            ])
        ])
    }

    func remindersToolSchema() -> Value {
        .object([
            "type": .string("object"),
            "properties": .object([
                "operation": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("create"), .string("get"), .string("update"),
                        .string("delete"), .string("complete"), .string("uncomplete"), .string("list")
                    ]),
                    "description": .string("Operation to perform on reminders")
                ]),
                "list": .object([
                    "type": .string("string"),
                    "description": .string("Reminder list name or UUID")
                ]),
                "uuid": .object([
                    "type": .string("string"),
                    "description": .string("Reminder UUID")
                ]),
                "title": .object(["type": .string("string")]),
                "notes": .object(["type": .string("string")]),
                "dueDate": .object([
                    "type": .string("string"),
                    "description": .string("ISO8601 due date. Example: 2025-03-20T17:00:00Z")
                ]),
                "priority": .object([
                    "type": .string("string"),
                    "enum": .array([.string("none"), .string("low"), .string("medium"), .string("high")])
                ]),
                "isCompleted": .object(["type": .string("boolean")]),
                "includeCompleted": .object(["type": .string("boolean")])
            ]),
            "required": .array([.string("operation")])
        ])
    }

    func searchToolSchema() -> Value {
        .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string")]),
                "text": .object(["type": .string("string")]),
                "lists": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")])
                ]),
                "completed": .object([
                    "type": .string("boolean"),
                    "description": .string("Filter by completion status (true=completed, false=incomplete)")
                ]),
                "priority": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")])
                ]),
                "dueBefore": .object(["type": .string("string")]),
                "dueAfter": .object(["type": .string("string")]),
                "hasNotes": .object(["type": .string("boolean")]),
                "hasDueDate": .object(["type": .string("boolean")]),
                "sortBy": .object(["type": .string("string")]),
                "sortOrder": .object(["type": .string("string")]),
                "limit": .object(["type": .string("integer")])
            ])
        ])
    }
}

// MARK: - Tool Handling

private extension RemindersMCPContext {
    func handleListsTool(_ input: ListsInput) async throws -> [Tool.Content] {
        switch input.operation {
        case .get:
            let calendars = reminders.getCalendars()
            return [try encodeTool(ListsResponse(lists: calendars))]
        case .create:
            guard let name = input.name, !name.isEmpty else {
                throw RemindersMCPError.invalidArguments("List name is required for create")
            }
            let calendar = try createList(named: name, source: input.source)
            return [try encodeTool(ListResponse(list: calendar))]
        case .delete:
            guard let name = input.name, !name.isEmpty else {
                throw RemindersMCPError.invalidArguments("List name is required for delete")
            }
            try deleteList(identifier: name)
            return [.text("{\"success\":true}")]
        }
    }

    func handleRemindersTool(_ input: RemindersInput) async throws -> [Tool.Content] {
        switch input.operation {
        case .create:
            guard let list = input.list, let title = input.title else {
                throw RemindersMCPError.invalidArguments("Both list and title are required for create")
            }
            let calendar = try resolveCalendar(list)
            let reminder = try createReminder(
                title: title,
                notes: input.notes,
                calendar: calendar,
                dueDate: input.dueDate.flatMap(parseDate),
                priority: input.priority.flatMap(Priority.init) ?? .none
            )
            return [try encodeTool(ReminderResponse(reminder: reminder))]

        case .get:
            guard let uuid = input.uuid else {
                throw RemindersMCPError.invalidArguments("uuid is required for get")
            }
            let reminder = try resolveReminder(uuid: uuid)
            return [try encodeTool(ReminderResponse(reminder: reminder))]

        case .update:
            guard let uuid = input.uuid else {
                throw RemindersMCPError.invalidArguments("uuid is required for update")
            }

            let reminder = try resolveReminder(uuid: uuid)
            if let title = input.title { reminder.title = title }
            if let notes = input.notes { reminder.notes = notes }
            if let isCompleted = input.isCompleted {
                reminder.isCompleted = isCompleted
            }
            if let priority = input.priority.flatMap(Priority.init) {
                reminder.priority = Int(priority.value.rawValue)
            }
            if let dueDateString = input.dueDate {
                reminder.dueDateComponents = parseDate(dueDateString)
                    .flatMap { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
            }
            try reminders.updateReminder(reminder)
            return [try encodeTool(ReminderResponse(reminder: reminder))]

        case .delete:
            guard let uuid = input.uuid else {
                throw RemindersMCPError.invalidArguments("uuid is required for delete")
            }
            let reminder = try resolveReminder(uuid: uuid)
            try reminders.deleteReminder(reminder)
            return [.text("{\"success\":true}")]

        case .complete:
            guard let uuid = input.uuid else {
                throw RemindersMCPError.invalidArguments("uuid is required for complete")
            }
            let reminder = try resolveReminder(uuid: uuid)
            try reminders.setReminderComplete(reminder, complete: true)
            return [try encodeTool(ReminderResponse(reminder: reminder))]

        case .uncomplete:
            guard let uuid = input.uuid else {
                throw RemindersMCPError.invalidArguments("uuid is required for uncomplete")
            }
            let reminder = try resolveReminder(uuid: uuid)
            try reminders.setReminderComplete(reminder, complete: false)
            return [try encodeTool(ReminderResponse(reminder: reminder))]

        case .list:
            let calendars: [EKCalendar]
            if let identifier = input.list, !identifier.isEmpty {
                calendars = [try resolveCalendar(identifier)]
            } else {
                calendars = reminders.getCalendars()
            }
            let display: DisplayOptions = input.includeCompleted == true ? .all : .incomplete
            let reminders = try await fetchReminders(on: calendars, display: display)
            return [try encodeTool(RemindersResponse(reminders: reminders))]
        }
    }

    func handleSearchTool(_ input: SearchInput) async throws -> [Tool.Content] {
        let calendars: [EKCalendar]
        if let lists = input.lists, !lists.isEmpty {
            calendars = try lists.compactMap { identifier in
                do {
                    return try resolveCalendar(identifier)
                } catch RemindersMCPError.listNotFound {
                    return nil
                }
            }
        } else {
            calendars = reminders.getCalendars()
        }

        var remindersList = try await fetchReminders(on: calendars, display: .all)

        let searchText = input.text ?? input.query
        if let query = searchText, !query.isEmpty {
            remindersList = remindersList.filter { reminder in
                (reminder.title?.localizedCaseInsensitiveContains(query) ?? false)
                    || (reminder.notes?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }

        let completionFilter = input.completed ?? .onlyIncomplete
        switch completionFilter {
        case .all: break
        case .onlyCompleted:
            remindersList = remindersList.filter(\.isCompleted)
        case .onlyIncomplete:
            remindersList = remindersList.filter { !$0.isCompleted }
        }

        if let hasNotes = input.hasNotes {
            remindersList = remindersList.filter { reminder in
                let hasContent = (reminder.notes?.isEmpty == false)
                return hasNotes ? hasContent : !hasContent
            }
        }

        if let hasDueDate = input.hasDueDate {
            remindersList = remindersList.filter { reminder in
                let hasDue = reminder.dueDateComponents?.date != nil
                return hasDueDate ? hasDue : !hasDue
            }
        }

        if let dueBefore = input.dueBefore.flatMap(parseDate) {
            remindersList = remindersList.filter { reminder in
                guard let due = reminder.dueDateComponents?.date else { return false }
                return due <= dueBefore
            }
        }

        if let dueAfter = input.dueAfter.flatMap(parseDate) {
            remindersList = remindersList.filter { reminder in
                guard let due = reminder.dueDateComponents?.date else { return false }
                return due >= dueAfter
            }
        }

        if let priorities = input.priority, !priorities.isEmpty {
            let targetPriorities = priorities.compactMap { Priority(rawValue: $0) }
            remindersList = remindersList.filter { reminder in
                Priority(reminder.mappedPriority).map { targetPriorities.contains($0) } ?? false
            }
        }

        if let sortKey = input.sortBy {
            let ascending = input.sortOrder?.lowercased() != "desc"
            remindersList.sort { lhs, rhs in
                switch sortKey.lowercased() {
                case "title":
                    let left = lhs.title ?? ""
                    let right = rhs.title ?? ""
                    return ascending ? left < right : left > right
                case "duedate":
                    let left = lhs.dueDateComponents?.date
                    let right = rhs.dueDateComponents?.date
                    switch (left, right) {
                    case (nil, nil): return false
                    case (nil, _): return !ascending
                    case (_, nil): return ascending
                    case (let l?, let r?):
                        return ascending ? l < r : l > r
                    }
                case "priority":
                    return ascending ? lhs.priority < rhs.priority : lhs.priority > rhs.priority
                default:
                    return false
                }
            }
        }

        if let limit = input.limit, limit > 0 {
            remindersList = Array(remindersList.prefix(limit))
        }

        let response = SearchResponse(reminders: remindersList, count: remindersList.count)
        return [try encodeTool(response)]
    }
}

// MARK: - Helpers

private extension RemindersMCPContext {
    func decode<T: Decodable>(_ arguments: [String: Value]?) throws -> T {
        let payload = arguments ?? [:]
        do {
            let data = try encoder.encode(payload)
            return try decoder.decode(T.self, from: data)
        } catch let decodingError as DecodingError {
            throw MCPError.invalidParams(decodingErrorMessage(decodingError))
        } catch {
            throw MCPError.invalidParams("Unable to decode arguments for \(String(describing: T.self))")
        }
    }

    func decodingErrorMessage(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            let codingPath = (context.codingPath + [key]).map(\.stringValue).joined(separator: ".")
            return "Missing required parameter '\(codingPath)'"
        case .valueNotFound(_, let context):
            let codingPath = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Value missing for parameter '\(codingPath)'"
        case .typeMismatch(let expected, let context):
            let codingPath = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Type mismatch for parameter '\(codingPath)'; expected \(expected)"
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return "Invalid arguments"
        }
    }

    func encodeTool<T: Encodable>(_ value: T) throws -> Tool.Content {
        .text(try encodeString(value))
    }

    func encodeResource<T: Encodable>(_ value: T, uri: String) throws -> Resource.Content {
        .text(try encodeString(value), uri: uri, mimeType: "application/json")
    }

    func encodeString<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw RemindersMCPError.storeFailure("Failed to encode response data")
        }
        return string
    }

    func resolveCalendar(_ identifier: String) throws -> EKCalendar {
        if let calendar = reminders.getCalendars().first(where: { $0.calendarIdentifier == identifier }) {
            return calendar
        }

        if let calendar = reminders.getCalendars().first(where: {
            $0.title.compare(identifier, options: .caseInsensitive) == .orderedSame
        }) {
            return calendar
        }

        throw RemindersMCPError.listNotFound(identifier)
    }

    func createList(named name: String, source: String?) throws -> EKCalendar {
        guard reminders.getCalendars().first(where: { $0.title == name }) == nil else {
            throw RemindersMCPError.listAlreadyExists(name)
        }

        let sources = reminders.store.sources
        guard var selectedSource = sources.first else {
            throw RemindersMCPError.noReminderSources
        }

        if let sourceName = source {
            guard let requested = sources.first(where: { $0.title == sourceName }) else {
                throw RemindersMCPError.invalidArguments("No source named '\(sourceName)'")
            }
            selectedSource = requested
        } else {
            let uniqueSources = Set(sources.map(\.title))
            if uniqueSources.count > 1 {
                throw RemindersMCPError.multipleSources(Array(uniqueSources))
            }
        }

        let newList = EKCalendar(for: .reminder, eventStore: reminders.store)
        newList.title = name
        newList.source = selectedSource

        do {
            try reminders.store.saveCalendar(newList, commit: true)
            return newList
        } catch {
            throw RemindersMCPError.storeFailure("Failed to save list: \(error.localizedDescription)")
        }
    }

    func deleteList(identifier: String) throws {
        let calendar = try resolveCalendar(identifier)
        guard calendar.allowsContentModifications else {
            throw RemindersMCPError.listReadOnly(identifier)
        }

        do {
            try reminders.store.removeCalendar(calendar, commit: true)
        } catch {
            throw RemindersMCPError.storeFailure("Failed to delete list: \(error.localizedDescription)")
        }
    }

    func resolveReminder(uuid: String) throws -> EKReminder {
        guard let reminder = reminders.getReminderByUUID(uuid) else {
            throw RemindersMCPError.reminderNotFound(uuid)
        }
        return reminder
    }

    func createReminder(
        title: String,
        notes: String?,
        calendar: EKCalendar,
        dueDate: Date?,
        priority: Priority
    ) throws -> EKReminder {
        let reminder = EKReminder(eventStore: reminders.store)
        reminder.calendar = calendar
        reminder.title = title
        reminder.notes = notes
        reminder.priority = Int(priority.value.rawValue)

        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
            if reminder.dueDateComponents?.hour != nil {
                reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
            }
        }

        do {
            try reminders.store.save(reminder, commit: true)
            return reminder
        } catch {
            throw RemindersMCPError.storeFailure("Failed to save reminder: \(error.localizedDescription)")
        }
    }

    func fetchReminders(on calendars: [EKCalendar], display: DisplayOptions) async throws -> [EKReminder] {
        try await withCheckedThrowingContinuation { continuation in
            reminders.reminders(on: calendars, displayOptions: display) { remindersList in
                continuation.resume(returning: remindersList)
            }
        }
    }

    func parseDate(_ string: String) -> Date? {
        if let date = isoDateFormatter.date(from: string) {
            return date
        }
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        return fallbackFormatter.date(from: string)
    }

    func log(_ message: String) {
        guard verbose else { return }
        fputs("[RemindersMCP] \(message)\n", stderr)
    }
}

// MARK: - Codable Input / Output Types

private struct ListsInput: Decodable {
    enum Operation: String, Decodable {
        case get
        case create
        case delete
    }

    let operation: Operation
    let name: String?
    let source: String?

    init(operation: Operation = .get, name: String? = nil, source: String? = nil) {
        self.operation = operation
        self.name = name
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let operation = try container.decodeIfPresent(Operation.self, forKey: .operation) ?? .get
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        let source = try container.decodeIfPresent(String.self, forKey: .source)
        self.init(operation: operation, name: name, source: source)
    }

    private enum CodingKeys: String, CodingKey {
        case operation
        case name
        case source
    }
}

private struct RemindersInput: Decodable {
    enum Operation: String, Decodable {
        case create
        case get
        case update
        case delete
        case complete
        case uncomplete
        case list
    }

    let operation: Operation
    let list: String?
    let uuid: String?
    let title: String?
    let notes: String?
    let dueDate: String?
    let priority: String?
    let isCompleted: Bool?
    let includeCompleted: Bool?

    init(
        operation: Operation = .list,
        list: String? = nil,
        uuid: String? = nil,
        title: String? = nil,
        notes: String? = nil,
        dueDate: String? = nil,
        priority: String? = nil,
        isCompleted: Bool? = nil,
        includeCompleted: Bool? = nil
    ) {
        self.operation = operation
        self.list = list
        self.uuid = uuid
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.priority = priority
        self.isCompleted = isCompleted
        self.includeCompleted = includeCompleted
    }

    private enum CodingKeys: String, CodingKey {
        case operation
        case list
        case uuid
        case title
        case notes
        case dueDate
        case priority
        case isCompleted
        case includeCompleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let operation = try container.decodeIfPresent(Operation.self, forKey: .operation) ?? .list
        let list = try container.decodeIfPresent(String.self, forKey: .list)
        let uuid = try container.decodeIfPresent(String.self, forKey: .uuid)
        let title = try container.decodeIfPresent(String.self, forKey: .title)
        let notes = try container.decodeIfPresent(String.self, forKey: .notes)
        let dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate)
        let priority = try container.decodeIfPresent(String.self, forKey: .priority)
        let isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted)
        let includeCompleted = try container.decodeIfPresent(Bool.self, forKey: .includeCompleted)
        self.init(
            operation: operation,
            list: list,
            uuid: uuid,
            title: title,
            notes: notes,
            dueDate: dueDate,
            priority: priority,
            isCompleted: isCompleted,
            includeCompleted: includeCompleted
        )
    }
}

private struct SearchInput: Decodable {
    enum CompletedFilter: Decodable {
        case all
        case onlyCompleted
        case onlyIncomplete

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let boolValue = try? container.decode(Bool.self) {
                self = boolValue ? .onlyCompleted : .onlyIncomplete
                return
            }

            if let stringValue = try? container.decode(String.self) {
                switch stringValue.lowercased() {
                case "all":
                    self = .all
                case "true", "completed":
                    self = .onlyCompleted
                case "false", "incomplete":
                    self = .onlyIncomplete
                default:
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Unsupported completion filter value '\(stringValue)'"
                    )
                }
                return
            }

            if container.decodeNil() {
                self = .onlyIncomplete
                return
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected bool or string for completion filter"
            )
        }
    }

    let text: String?
    let query: String?
    let lists: [String]?
    let completed: CompletedFilter?
    let priority: [String]?
    let dueBefore: String?
    let dueAfter: String?
    let hasNotes: Bool?
    let hasDueDate: Bool?
    let sortBy: String?
    let sortOrder: String?
    let limit: Int?
}

private struct ListsResponse: Encodable {
    let lists: [EKCalendar]
}

private struct ListResponse: Encodable {
    let list: EKCalendar
}

private struct ReminderResponse: Encodable {
    let reminder: EKReminder
}

private struct RemindersResponse: Encodable {
    let reminders: [EKReminder]
}

private struct SearchResponse: Encodable {
    let reminders: [EKReminder]
    let count: Int
}
