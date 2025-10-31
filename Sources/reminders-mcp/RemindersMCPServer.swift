import EventKit
import Foundation
import SwiftMCP
import RemindersLibrary

enum RemindersMCPError: Error, LocalizedError {
    case listNotFound(String)
    case listAlreadyExists(String)
    case listReadOnly(String)
    case reminderNotFound(String)
    case storeFailure(String)
    case permissionDenied
    case noReminderSources
    case multipleSources([String])
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case .listNotFound(let id):
            return "List not found: \(id)"
        case .listAlreadyExists(let name):
            return "List '\(name)' already exists"
        case .listReadOnly(let id):
            return "List '\(id)' is read-only and cannot be modified"
        case .reminderNotFound(let uuid):
            return "Reminder not found: \(uuid)"
        case .storeFailure(let message):
            return "Store operation failed: \(message)"
        case .permissionDenied:
            return "Reminders access denied. Grant access in System Preferences > Privacy & Security > Reminders"
        case .noReminderSources:
            return "No reminder sources available"
        case .multipleSources(let sources):
            return "Multiple reminder sources available. Specify source: \(sources.joined(separator: ", "))"
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        }
    }
}

// MARK: - Response Types

public struct ParsedField: Encodable {
    public let original: String
    public let parsed: String

    public init(original: String, parsed: String) {
        self.original = original
        self.parsed = parsed
    }
}

public struct ParsedMetadata: Encodable {
    public let list: ParsedField?
    public let priority: ParsedField?
    public let tags: [ParsedField]?
    public let dueDate: ParsedField?

    public init(list: ParsedField? = nil, priority: ParsedField? = nil, tags: [ParsedField]? = nil, dueDate: ParsedField? = nil) {
        self.list = list
        self.priority = priority
        self.tags = tags
        self.dueDate = dueDate
    }
}

public struct ReminderResponse: Encodable {
    public let reminder: EKReminder
    public let success: Bool
    public let message: String?
    public let parsed: ParsedMetadata?

    public init(reminder: EKReminder, success: Bool = true, message: String? = nil, parsed: ParsedMetadata? = nil) {
        self.reminder = reminder
        self.success = success
        self.message = message
        self.parsed = parsed
    }
}

public struct SuccessResponse: Encodable {
    public let success: Bool
    public let message: String?

    public init(success: Bool = true, message: String? = nil) {
        self.success = success
        self.message = message
    }
}

public struct ListsResponse: Encodable {
    public let lists: [EKCalendar]
    public let success: Bool
    public let message: String?

    public init(lists: [EKCalendar], success: Bool = true, message: String? = nil) {
        self.lists = lists
        self.success = success
        self.message = message
    }
}

public struct SearchFilters: Encodable {
    public let applied: [String]
    public let summary: String

    public init(applied: [String] = [], summary: String = "All reminders") {
        self.applied = applied
        self.summary = summary
    }
}

public struct SearchResponse: Encodable {
    public let reminders: [EKReminder]
    public let totalCount: Int
    public let returnedCount: Int
    public let hasMore: Bool
    public let limit: Int?
    public let offset: Int?
    public let filters: SearchFilters

    public init(reminders: [EKReminder], totalCount: Int, limit: Int? = nil, offset: Int? = nil, filters: SearchFilters = SearchFilters()) {
        self.reminders = reminders
        self.totalCount = totalCount
        self.returnedCount = reminders.count
        self.hasMore = limit != nil && totalCount > reminders.count + (offset ?? 0)
        self.limit = limit
        self.offset = offset
        self.filters = filters
    }
}

public struct ChangeRecord: Encodable {
    public let uuid: String
    public let field: String
    public let from: String
    public let to: String

    public init(uuid: String, field: String, from: String, to: String) {
        self.uuid = uuid
        self.field = field
        self.from = from
        self.to = to
    }
}

public struct BulkResponse: Encodable {
    public let processedCount: Int
    public let failedCount: Int
    public let errors: [String]
    public let changes: [ChangeRecord]
    public let success: Bool

    public init(processedCount: Int, failedCount: Int, errors: [String], changes: [ChangeRecord] = []) {
        self.processedCount = processedCount
        self.failedCount = failedCount
        self.errors = errors
        self.changes = changes
        self.success = failedCount == 0
    }
}

public struct AnalyzeResponse: Encodable {
    public let totalReminders: Int
    public let completedCount: Int
    public let incompleteCount: Int
    public let overdueCount: Int
    public let dueTodayCount: Int
    public let dueThisWeekCount: Int
    public let byPriority: [String: Int]
    public let byList: [String: Int]
}

// MARK: - Filter Expression System

enum FilterOperator: String {
    case equals = "="
    case notEquals = "!="
    case lessThan = "<"
    case greaterThan = ">"
    case lessOrEqual = "<="
    case greaterOrEqual = ">="
    case contains = "CONTAINS"
    case notContains = "NOT CONTAINS"
    case like = "LIKE"
    case notLike = "NOT LIKE"
    case matches = "MATCHES"
    case notMatches = "NOT MATCHES"
    case `in` = "IN"
    case notIn = "NOT IN"
}

enum LogicalOperator: String {
    case and = "AND"
    case or = "OR"
}

struct FilterCondition {
    let field: String
    let op: FilterOperator
    let value: String
    let negate: Bool

    func evaluate(_ reminder: EKReminder, calendar: Calendar) -> Bool {
        let result = evaluateCondition(reminder, calendar: calendar)
        return negate ? !result : result
    }

    private func evaluateCondition(_ reminder: EKReminder, calendar: Calendar) -> Bool {
        let fieldValue = getFieldValue(from: reminder, field: field)

        switch op {
        case .equals:
            return fieldValue.lowercased() == value.lowercased()
        case .notEquals:
            return fieldValue.lowercased() != value.lowercased()
        case .contains:
            return fieldValue.lowercased().contains(value.lowercased())
        case .notContains:
            return !fieldValue.lowercased().contains(value.lowercased())
        case .like:
            // LIKE supports wildcards: * (any chars) and ? (single char)
            return matchesWildcard(fieldValue, pattern: value)
        case .notLike:
            return !matchesWildcard(fieldValue, pattern: value)
        case .matches:
            // MATCHES uses regex patterns
            return matchesRegex(fieldValue, pattern: value)
        case .notMatches:
            return !matchesRegex(fieldValue, pattern: value)
        case .in:
            let values = value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }
            return values.contains(fieldValue.lowercased())
        case .notIn:
            let values = value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }
            return !values.contains(fieldValue.lowercased())
        case .lessThan, .greaterThan, .lessOrEqual, .greaterOrEqual:
            return evaluateDateComparison(reminder, op: op, value: value, calendar: calendar)
        }
    }

    /// Match with wildcards: * = any chars, ? = single char
    private func matchesWildcard(_ text: String, pattern: String) -> Bool {
        // Convert wildcard pattern to regex
        var regexPattern = NSRegularExpression.escapedPattern(for: pattern)
        regexPattern = regexPattern.replacingOccurrences(of: "\\*", with: ".*")
        regexPattern = regexPattern.replacingOccurrences(of: "\\?", with: ".")
        regexPattern = "^" + regexPattern + "$"

        return text.range(of: regexPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Match with regex pattern
    private func matchesRegex(_ text: String, pattern: String) -> Bool {
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func getFieldValue(from reminder: EKReminder, field: String) -> String {
        switch field.lowercased() {
        case "title":
            return reminder.title ?? ""
        case "notes":
            return reminder.notes ?? ""
        case "list":
            return reminder.calendar.title
        case "completed":
            return reminder.isCompleted ? "true" : "false"
        case "priority":
            let bucket = priorityBucket(for: reminder)
            return bucket
        default:
            return ""
        }
    }

    private func evaluateDateComparison(_ reminder: EKReminder, op: FilterOperator, value: String, calendar: Calendar) -> Bool {
        guard let dueDate = reminder.dueDateComponents?.date else { return false }

        // Parse comparison date
        let compareDate: Date
        if let parsed = parseDate(value, calendar: calendar) {
            compareDate = parsed
        } else {
            return false
        }

        switch op {
        case .lessThan:
            return dueDate < compareDate
        case .greaterThan:
            return dueDate > compareDate
        case .lessOrEqual:
            return dueDate <= compareDate
        case .greaterOrEqual:
            return dueDate >= compareDate
        default:
            return false
        }
    }

    private func parseDate(_ dateStr: String, calendar: Calendar) -> Date? {
        // Try ISO8601 first
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: dateStr) {
            return date
        }

        // Try natural language
        if let components = DateComponents(argument: dateStr) {
            return calendar.date(from: components)
        }

        return nil
    }

    private func priorityBucket(for reminder: EKReminder) -> String {
        switch reminder.priority {
        case 0:
            return "none"
        case 1...4:
            return "high"
        case 5:
            return "medium"
        case 6...9:
            return "low"
        default:
            return "none"
        }
    }
}

struct FilterExpression {
    let conditions: [FilterCondition]
    let logicalOps: [LogicalOperator]

    func evaluate(_ reminder: EKReminder, calendar: Calendar) -> Bool {
        guard !conditions.isEmpty else { return true }

        if conditions.count == 1 {
            return conditions[0].evaluate(reminder, calendar: calendar)
        }

        var result = conditions[0].evaluate(reminder, calendar: calendar)

        for (index, logicalOp) in logicalOps.enumerated() {
            let nextCondition = conditions[index + 1]
            let nextResult = nextCondition.evaluate(reminder, calendar: calendar)

            switch logicalOp {
            case .and:
                result = result && nextResult
            case .or:
                result = result || nextResult
            }
        }

        return result
    }

    /// Expand query shortcuts to full filter expressions
    private static func expandShortcuts(_ query: String) -> String {
        let shortcuts: [String: String] = [
            "overdue": "(dueDate < now AND completed = false)",
            "due_today": "(dueDate >= today AND dueDate < tomorrow)",
            "due_tomorrow": "(dueDate >= tomorrow AND dueDate < tomorrow+1)",
            "this_week": "(dueDate < end_of_week)",
            "next_week": "(dueDate >= next_week AND dueDate < next_week+7)",
            "high_priority": "priority IN [high,medium]",
            "incomplete": "completed = false",
            "complete": "completed = true"
        ]

        var expanded = query
        for (shortcut, replacement) in shortcuts {
            // Match whole word only (not part of other words)
            let pattern = "\\b\(shortcut)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(expanded.startIndex..<expanded.endIndex, in: expanded)
                expanded = regex.stringByReplacingMatches(in: expanded, range: range, withTemplate: replacement)
            }
        }

        return expanded
    }

    static func parse(_ filterString: String) throws -> FilterExpression {
        // Expand shortcuts first
        let expandedFilter = expandShortcuts(filterString)

        var conditions: [FilterCondition] = []
        var logicalOps: [LogicalOperator] = []

        // Simple parser: split by AND/OR, then parse each condition
        let parts = splitByLogicalOperators(expandedFilter)

        for (index, part) in parts.enumerated() {
            if index % 2 == 0 {
                // This is a condition
                if let condition = try? parseCondition(part.trimmingCharacters(in: .whitespaces)) {
                    conditions.append(condition)
                }
            } else {
                // This is a logical operator
                if let op = LogicalOperator(rawValue: part.trimmingCharacters(in: .whitespaces).uppercased()) {
                    logicalOps.append(op)
                }
            }
        }

        // Validate for impossible combinations
        try validateFilterLogic(conditions: conditions, logicalOps: logicalOps)

        return FilterExpression(conditions: conditions, logicalOps: logicalOps)
    }

    /// Validate that the filter doesn't contain impossible combinations
    private static func validateFilterLogic(conditions: [FilterCondition], logicalOps: [LogicalOperator]) throws {
        // Look for field = value1 AND field = value2 patterns (with different values)
        // These are impossible for single-value fields like list, priority, completed

        for i in 0..<conditions.count {
            guard i < logicalOps.count else { break }

            // Only check AND operators
            guard logicalOps[i] == .and else { continue }

            let current = conditions[i]
            let next = conditions[i + 1]

            // Check if both conditions are about the same field
            guard current.field.lowercased() == next.field.lowercased() else { continue }

            // For single-value fields, check if values are different
            let singleValueFields = ["list", "priority", "completed"]
            guard singleValueFields.contains(current.field.lowercased()) else { continue }

            // If both are equality checks with different values, it's impossible
            if (current.op == .equals && next.op == .equals) {
                if current.value.lowercased() != next.value.lowercased() {
                    let fieldName = current.field.lowercased()
                    throw RemindersMCPError.invalidArguments(
                        "Impossible filter: A reminder cannot have \(fieldName)='\(current.value)' AND \(fieldName)='\(next.value)'. " +
                        "Did you mean to use OR instead? Example: \(fieldName)='\(current.value)' OR \(fieldName)='\(next.value)'"
                    )
                }
            }

            // Check for contradictory IN/NOT IN on same field
            if (current.op == .in && next.op == .notIn) || (current.op == .notIn && next.op == .in) {
                // This could be valid in some cases, but warn if values overlap
                continue
            }
        }
    }

    private static func splitByLogicalOperators(_ input: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var i = input.startIndex

        while i < input.endIndex {
            // Check for AND
            if input[i...].hasPrefix(" AND ") {
                parts.append(current)
                parts.append("AND")
                current = ""
                i = input.index(i, offsetBy: 5)
                continue
            }

            // Check for OR
            if input[i...].hasPrefix(" OR ") {
                parts.append(current)
                parts.append("OR")
                current = ""
                i = input.index(i, offsetBy: 4)
                continue
            }

            current.append(input[i])
            i = input.index(after: i)
        }

        if !current.isEmpty {
            parts.append(current)
        }

        return parts
    }

    private static func parseCondition(_ conditionStr: String) throws -> FilterCondition {
        var negate = false
        var workingStr = conditionStr.trimmingCharacters(in: .whitespaces)

        // Check for NOT prefix
        if workingStr.uppercased().hasPrefix("NOT ") {
            negate = true
            workingStr = String(workingStr.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        }

        // Try to parse operator
        // Order matters: check longer operators first (e.g., NOT MATCHES before MATCHES)
        let operators: [FilterOperator] = [.notContains, .notLike, .notMatches, .contains, .like, .matches, .notIn, .in, .lessOrEqual, .greaterOrEqual, .notEquals, .equals, .lessThan, .greaterThan]

        for op in operators {
            if let range = workingStr.range(of: " \(op.rawValue) ", options: .caseInsensitive) {
                let field = String(workingStr[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let value = String(workingStr[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

                return FilterCondition(field: field, op: op, value: value, negate: negate)
            }

            // Try without spaces for = and !=
            if op == .equals || op == .notEquals || op == .lessThan || op == .greaterThan {
                if let range = workingStr.range(of: op.rawValue, options: .caseInsensitive) {
                    let field = String(workingStr[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let value = String(workingStr[range.upperBound...]).trimmingCharacters(in: .whitespaces)

                    if !field.isEmpty && !value.isEmpty {
                        return FilterCondition(field: field, op: op, value: value, negate: negate)
                    }
                }
            }
        }

        throw RemindersMCPError.invalidArguments("Could not parse filter condition: \(conditionStr)")
    }
}

@MCPServer
public class RemindersMCPServer {
    private let reminders: Reminders
    private let verbose: Bool
    private let isoDateFormatter: ISO8601DateFormatter
    private let calendar: Calendar = Calendar.current

    public init(verbose: Bool = false) {
        self.reminders = Reminders()
        self.verbose = verbose

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoDateFormatter = formatter
    }

    // MARK: - Reminder CRUD Tools

    /// Create a new reminder with smart parsing
    /// - Parameters:
    ///   - title: Reminder title. Supports metadata markers (@listname, !priority, #tags, natural dates)
    ///   - list: List name or UUID (optional if @listname in title)
    ///   - notes: Optional notes
    ///   - dueDate: Due date (ISO8601 or natural language like "tomorrow")
    ///   - priority: Priority (!high, !3, !urgent, !medium, !2, !low, !1, !none, !0, or just: high, medium, low, none, 0-3)
    @MCPTool
    public func reminders_create(
        title: String,
        list: String? = nil,
        notes: String? = nil,
        dueDate: String? = nil,
        priority: String? = nil
    ) async throws -> ReminderResponse {
        log("Creating reminder: \(title)")

        let metadata = TitleParser.parse(title)

        // Track what was parsed from the title
        var parsedList: ParsedField?
        var parsedPriority: ParsedField?
        var parsedTags: [ParsedField]?
        var parsedDueDate: ParsedField?

        let listIdentifier: String
        if let explicitList = list {
            listIdentifier = explicitList
        } else if let extractedList = metadata.listName {
            listIdentifier = extractedList
            parsedList = ParsedField(original: "@\(extractedList)", parsed: extractedList)
        } else {
            throw RemindersMCPError.invalidArguments("Provide list parameter or include @listname in title")
        }

        let calendar = try resolveCalendar(listIdentifier)
        let priorityEnum = resolvePriority(explicit: priority, inferred: metadata.priority)

        if priority == nil, let inferredPriority = metadata.priority {
            parsedPriority = ParsedField(
                original: "!\(inferredPriority.rawValue)",
                parsed: inferredPriority.rawValue
            )
        }

        if !metadata.tags.isEmpty {
            parsedTags = metadata.tags.map { tag in
                ParsedField(original: "#\(tag)", parsed: tag)
            }
        }

        let dueComponents = try resolveDueDate(explicit: dueDate, inferred: metadata.dueDate)

        if dueDate == nil, metadata.dueDate != nil {
            // Try to find the date string in the original title
            if let dueComp = metadata.dueDate, let date = dueComp.date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                parsedDueDate = ParsedField(
                    original: "(natural language date)",
                    parsed: formatter.string(from: date)
                )
            }
        }

        let reminder = try reminders.createReminder(
            title: metadata.cleanedTitle,
            notes: notes,
            calendar: calendar,
            dueDateComponents: dueComponents,
            priority: priorityEnum
        )

        let parsedMetadata = ParsedMetadata(
            list: parsedList,
            priority: parsedPriority,
            tags: parsedTags,
            dueDate: parsedDueDate
        )

        return ReminderResponse(reminder: reminder, message: "Reminder created", parsed: parsedMetadata)
    }

    /// Get a reminder by UUID
    /// - Parameter uuid: Reminder UUID (with or without x-apple-reminder:// prefix)
    @MCPTool
    public func reminders_get(uuid: String) async throws -> ReminderResponse {
        log("Getting reminder: \(uuid)")
        let reminder = try resolveReminder(uuid: uuid)
        return ReminderResponse(reminder: reminder)
    }

    /// Update a reminder with smart parsing
    /// - Parameters:
    ///   - uuid: Reminder UUID
    ///   - title: New title (supports metadata extraction)
    ///   - notes: New notes
    ///   - dueDate: New due date (ISO8601 or natural language)
    ///   - priority: New priority (symbols, words, or numbers)
    ///   - isCompleted: Completion status
    @MCPTool
    public func reminders_update(
        uuid: String,
        title: String? = nil,
        notes: String? = nil,
        dueDate: String? = nil,
        priority: String? = nil,
        isCompleted: Bool? = nil
    ) async throws -> ReminderResponse {
        log("Updating reminder: \(uuid)")

        let reminder = try resolveReminder(uuid: uuid)

        if let title {
            let metadata = TitleParser.parse(title)
            reminder.title = metadata.cleanedTitle

            if priority == nil, let extractedPriority = metadata.priority {
                reminder.priority = Int(extractedPriority.value.rawValue)
            }

            if dueDate == nil, let extractedDate = metadata.dueDate {
                reminder.dueDateComponents = extractedDate
            }
        }

        if let notes {
            reminder.notes = notes
        }

        if let isCompleted {
            reminder.isCompleted = isCompleted
        }

        if let priorityStr = priority {
            if let priorityEnum = Priority(fromString: priorityStr) {
                reminder.priority = Int(priorityEnum.value.rawValue)
            } else {
                throw RemindersMCPError.invalidArguments("Unknown priority: \(priorityStr)")
            }
        }

        if let dueDateStr = dueDate {
            if let components = try resolveDueDate(explicit: dueDateStr, inferred: nil) {
                reminder.dueDateComponents = components
            } else {
                reminder.dueDateComponents = nil
            }
        }

        try reminders.updateReminder(reminder)
        return ReminderResponse(reminder: reminder, message: "Reminder updated")
    }

    /// Delete a reminder
    /// - Parameter uuid: Reminder UUID
    @MCPTool
    public func reminders_delete(uuid: String) async throws -> SuccessResponse {
        log("Deleting reminder: \(uuid)")
        let reminder = try resolveReminder(uuid: uuid)
        try reminders.deleteReminder(reminder)
        return SuccessResponse(message: "Reminder deleted")
    }

    /// Mark a reminder as complete
    /// - Parameter uuid: Reminder UUID
    @MCPTool
    public func reminders_complete(uuid: String) async throws -> ReminderResponse {
        log("Completing reminder: \(uuid)")
        let reminder = try resolveReminder(uuid: uuid)
        try reminders.setReminderComplete(reminder, complete: true)
        return ReminderResponse(reminder: reminder, message: "Reminder completed")
    }

    /// Mark a reminder as incomplete
    /// - Parameter uuid: Reminder UUID
    @MCPTool
    public func reminders_uncomplete(uuid: String) async throws -> ReminderResponse {
        log("Uncompleting reminder: \(uuid)")
        let reminder = try resolveReminder(uuid: uuid)
        try reminders.setReminderComplete(reminder, complete: false)
        return ReminderResponse(reminder: reminder, message: "Reminder marked incomplete")
    }

    /// Move a reminder to a different list
    /// - Parameters:
    ///   - uuid: Reminder UUID
    ///   - targetList: Target list name or UUID
    @MCPTool
    public func reminders_move(uuid: String, targetList: String) async throws -> ReminderResponse {
        log("Moving reminder \(uuid) to \(targetList)")
        let reminder = try resolveReminder(uuid: uuid)
        let target = try resolveCalendar(targetList)
        reminder.calendar = target
        try reminders.updateReminder(reminder)
        return ReminderResponse(reminder: reminder, message: "Reminder moved to \(target.title)")
    }

    /// Archive a reminder by moving it to an archive list
    /// - Parameters:
    ///   - uuid: Reminder UUID
    ///   - archiveList: Archive list name (defaults to "Archive")
    ///   - createIfMissing: Create archive list if it doesn't exist
    @MCPTool
    public func reminders_archive(
        uuid: String,
        archiveList: String? = nil,
        createIfMissing: Bool? = nil
    ) async throws -> ReminderResponse {
        log("Archiving reminder: \(uuid)")
        let reminder = try resolveReminder(uuid: uuid)
        let archiveName = archiveList ?? "Archive"
        let calendar = try ensureArchiveCalendar(
            named: archiveName,
            createIfMissing: createIfMissing ?? false,
            sourceName: nil
        )

        reminder.calendar = calendar
        try reminders.updateReminder(reminder)
        return ReminderResponse(reminder: reminder, message: "Reminder archived to \(calendar.title)")
    }

    // MARK: - List Management Tools

    /// List all reminder lists
    /// - Parameter includeReadOnly: Include read-only lists (default: false)
    @MCPTool
    public func lists_list(includeReadOnly: Bool? = nil) async throws -> ListsResponse {
        log("Listing reminder lists")
        let calendars = reminders.store.calendars(for: .reminder).filter {
            guard let includeRO = includeReadOnly, includeRO else {
                return $0.allowsContentModifications
            }
            return true
        }
        return ListsResponse(lists: calendars)
    }

    /// Create a new reminder list
    /// - Parameters:
    ///   - name: Name of the new list
    ///   - source: Optional source name for the list
    @MCPTool
    public func lists_create(name: String, source: String? = nil) async throws -> ListsResponse {
        log("Creating list: \(name)")

        let existing = reminders.getCalendars()
        guard !existing.contains(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw RemindersMCPError.listAlreadyExists(name)
        }

        try reminders.newList(with: name, source: source)

        guard let created = reminders.getCalendars().first(where: {
            $0.title.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            throw RemindersMCPError.storeFailure("Failed to create list")
        }

        return ListsResponse(lists: [created], message: "List '\(name)' created")
    }

    /// Delete a reminder list
    /// - Parameter identifier: List name or UUID to delete
    @MCPTool
    public func lists_delete(identifier: String) async throws -> SuccessResponse {
        log("Deleting list: \(identifier)")

        let calendar = try resolveCalendar(identifier)
        guard calendar.allowsContentModifications else {
            throw RemindersMCPError.listReadOnly(identifier)
        }

        try reminders.store.removeCalendar(calendar, commit: true)
        return SuccessResponse(message: "List '\(calendar.title)' deleted")
    }

    /// Ensure an archive list exists, creating it if necessary
    /// - Parameters:
    ///   - name: Archive list name (defaults to "Archive")
    ///   - createIfMissing: Create if doesn't exist (default: false)
    ///   - source: Optional source for new list
    @MCPTool
    public func lists_ensure_archive(
        name: String? = nil,
        createIfMissing: Bool? = nil,
        source: String? = nil
    ) async throws -> ListsResponse {
        let archiveName = name ?? "Archive"
        log("Ensuring archive list: \(archiveName)")

        let existedBefore = reminders.getCalendars().contains {
            $0.title.compare(archiveName, options: .caseInsensitive) == .orderedSame
        }

        let calendar = try ensureArchiveCalendar(
            named: archiveName,
            createIfMissing: createIfMissing ?? false,
            sourceName: source
        )

        let message = existedBefore ? "Archive list already exists" : "Archive list created"
        return ListsResponse(lists: [calendar], message: message)
    }

    /// List reminders in a specific list
    /// - Parameters:
    ///   - list: List name or UUID
    ///   - includeCompleted: Include completed reminders (default: false)
    @MCPTool
    public func reminders_list(
        list: String,
        includeCompleted: Bool? = nil
    ) async throws -> SearchResponse {
        log("Listing reminders in: \(list)")

        let calendar = try resolveCalendar(list)
        let displayOptions: DisplayOptions = (includeCompleted ?? false) ? .all : .incomplete

        let reminders = try await withCheckedThrowingContinuation { continuation in
            self.reminders.reminders(on: [calendar], displayOptions: displayOptions) { reminders in
                continuation.resume(returning: reminders)
            }
        }

        let filterSummary = (includeCompleted ?? false) ? "All reminders in \(calendar.title)" : "Incomplete reminders in \(calendar.title)"
        let filters = SearchFilters(
            applied: ["list=\(calendar.title)", "completed=\(includeCompleted ?? false ? "all" : "false")"],
            summary: filterSummary
        )

        return SearchResponse(reminders: reminders, totalCount: reminders.count, filters: filters)
    }

    // MARK: - Search Tool

    /// Search reminders with filters
    ///
    /// Filter Syntax:
    ///   **Fields:** title, notes, list, priority, completed, dueDate
    ///   **Operators:** =, !=, <, >, <=, >=, CONTAINS, LIKE, MATCHES, IN, NOT
    ///   **Logic:** AND, OR
    ///   **Sorting:** ORDER BY field [ASC|DESC], field2 [ASC|DESC]
    ///
    ///   **Wildcards (LIKE):**
    ///   - * = any characters
    ///   - ? = single character
    ///
    ///   **Shortcuts:**
    ///   - overdue = (dueDate < now AND completed = false)
    ///   - due_today = (dueDate >= today AND dueDate < tomorrow)
    ///   - this_week = (dueDate < end_of_week)
    ///   - high_priority = priority IN [high,medium]
    ///   - incomplete = completed = false
    ///
    ///   **Examples:**
    ///   - "priority = high" - High priority reminders
    ///   - "overdue" - Overdue incomplete reminders
    ///   - "title LIKE meet*" - Title starts with "meet"
    ///   - "title MATCHES urgent|critical" - Regex: "urgent" or "critical"
    ///   - "priority = high ORDER BY dueDate ASC" - Sorted results
    ///   - "list = Work ORDER BY priority DESC, dueDate ASC" - Multi-field sort
    ///   - "NOT completed = true" - Incomplete reminders
    ///
    ///   Note: When using filter, all reminders are searched by default.
    ///         Add "completed = false" or use "incomplete" shortcut for incomplete only.
    ///
    /// - Parameters:
    ///   - filter: Advanced filter expression (see syntax above)
    ///   - query: Text search in title and notes (legacy, use filter instead)
    ///   - lists: Filter by list names or UUIDs (legacy, use filter instead)
    ///   - completed: Filter by completion (legacy, use filter instead)
    ///   - priority: Filter by priorities (legacy, use filter instead)
    ///   - dueBefore: Filter by due before date (legacy, use filter instead)
    ///   - dueAfter: Filter by due after date (legacy, use filter instead)
    ///   - hasNotes: Filter by presence of notes (legacy, use filter instead)
    ///   - hasDueDate: Filter by presence of due date (legacy, use filter instead)
    ///   - sortBy: Sort by field (title, dueDate, priority, createdAt)
    ///   - sortOrder: Sort order (asc or desc)
    ///   - limit: Maximum results to return
    ///   - offset: Number of results to skip
    @MCPTool
    public func reminders_search(
        filter: String? = nil,
        query: String? = nil,
        lists: String? = nil,
        completed: String? = nil,
        priority: String? = nil,
        dueBefore: String? = nil,
        dueAfter: String? = nil,
        hasNotes: Bool? = nil,
        hasDueDate: Bool? = nil,
        sortBy: String? = nil,
        sortOrder: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) async throws -> SearchResponse {
        log("Searching reminders with query: \(query ?? "none")")

        // Parse display options
        // If using advanced filter, default to .all so filter has full control
        // Otherwise, default to .incomplete for backward compatibility
        let displayOptions: DisplayOptions
        if filter != nil {
            // When using advanced filter, search all reminders unless completed is explicitly set
            switch completed?.lowercased() {
            case "true": displayOptions = .complete
            case "false": displayOptions = .incomplete
            default: displayOptions = .all
            }
        } else {
            // Legacy behavior: default to incomplete
            switch completed?.lowercased() {
            case "true": displayOptions = .complete
            case "false", nil: displayOptions = .incomplete
            default: displayOptions = .all
            }
        }

        // Resolve calendars
        var calendarsToSearch: [EKCalendar] = []
        if let listsStr = lists, !listsStr.isEmpty {
            let listNames = listsStr.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            for identifier in listNames {
                if let calendar = try? resolveCalendar(identifier) {
                    calendarsToSearch.append(calendar)
                }
            }
            if calendarsToSearch.isEmpty {
                return SearchResponse(reminders: [], totalCount: 0)
            }
        } else {
            calendarsToSearch = reminders.getCalendars()
        }

        // Fetch reminders
        let allReminders = try await fetchReminders(on: calendarsToSearch, display: displayOptions)
        var filtered = allReminders

        // Parse ORDER BY if present in filter
        var orderByFields: [(field: String, ascending: Bool)] = []
        var filterWithoutOrder = filter

        if let filterStr = filter, !filterStr.isEmpty {
            // Split filter and ORDER BY clause
            let (filterPart, orderPart) = splitOrderBy(filterStr)
            filterWithoutOrder = filterPart.isEmpty ? nil : filterPart

            if !orderPart.isEmpty {
                orderByFields = parseOrderBy(orderPart)
            }

            // Apply filter if present
            if let filterPart = filterWithoutOrder, !filterPart.isEmpty {
                let filterExpression = try FilterExpression.parse(filterPart)
                filtered = filtered.filter { reminder in
                    filterExpression.evaluate(reminder, calendar: Calendar.current)
                }
            }
        }

        // Apply legacy text query filter (only if not using filter expression)
        if filter == nil, let query = query, !query.isEmpty {
            filtered = filtered.filter { reminder in
                (reminder.title?.localizedCaseInsensitiveContains(query) ?? false) ||
                (reminder.notes?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }

        // Apply priority filter
        if let priorityStr = priority, !priorityStr.isEmpty {
            let priorities = priorityStr.split(separator: ",").map {
                String($0).trimmingCharacters(in: .whitespaces).lowercased()
            }
            filtered = filtered.filter { reminder in
                let bucket = priorityBucket(for: reminder)
                return priorities.contains(bucket)
            }
        }

        // Apply date filters
        if let dueBeforeStr = dueBefore, let date = parseDate(dueBeforeStr) {
            filtered = filtered.filter { reminder in
                guard let dueDate = reminder.dueDateComponents?.date else { return false }
                return dueDate < date
            }
        }

        if let dueAfterStr = dueAfter, let date = parseDate(dueAfterStr) {
            filtered = filtered.filter { reminder in
                guard let dueDate = reminder.dueDateComponents?.date else { return false }
                return dueDate > date
            }
        }

        // Apply notes filter
        if let hasNotes = hasNotes {
            filtered = filtered.filter { reminder in
                let hasContent = reminder.notes != nil && !reminder.notes!.isEmpty
                return hasNotes ? hasContent : !hasContent
            }
        }

        // Apply due date filter
        if let hasDueDate = hasDueDate {
            filtered = filtered.filter { reminder in
                let hasDue = reminder.dueDateComponents != nil
                return hasDueDate ? hasDue : !hasDue
            }
        }

        // Apply sorting (from ORDER BY clause or legacy sortBy parameter)
        if !orderByFields.isEmpty {
            // Use ORDER BY from filter
            filtered = sortRemindersByMultipleFields(filtered, orderByFields)
        } else if let sortBy = sortBy {
            // Fallback to legacy sortBy parameter
            let ascending = sortOrder?.lowercased() != "desc"
            filtered = sortReminders(filtered, by: sortBy, ascending: ascending)
        }

        // Get total count before pagination
        let totalCount = filtered.count

        // Apply pagination
        let offsetValue = offset ?? 0
        if let limit = limit, limit > 0 {
            let start = max(0, offsetValue)
            let end = min(totalCount, start + limit)
            if start < totalCount {
                filtered = Array(filtered[start..<end])
            } else {
                filtered = []
            }
        } else if offsetValue > 0 {
            filtered = Array(filtered.dropFirst(offsetValue))
        }

        // Build filters summary
        var appliedFilters: [String] = []
        var summaryParts: [String] = []

        // If using advanced filter expression
        if let filterStr = filter, !filterStr.isEmpty {
            appliedFilters.append("filter=\"\(filterStr)\"")
            summaryParts.append(filterStr)
        }

        if let q = query, !q.isEmpty {
            appliedFilters.append("query=\"\(q)\"")
            summaryParts.append("matching '\(q)'")
        }

        if let l = lists, !l.isEmpty {
            appliedFilters.append("lists=[\(l)]")
            summaryParts.append("in lists: \(l)")
        }

        if let p = priority, !p.isEmpty {
            appliedFilters.append("priority=[\(p)]")
            summaryParts.append("priority: \(p)")
        }

        switch completed?.lowercased() {
        case "true":
            appliedFilters.append("completed=true")
            summaryParts.append("completed")
        case "false", nil:
            appliedFilters.append("completed=false")
            summaryParts.append("incomplete")
        case "all":
            appliedFilters.append("completed=all")
        default:
            break
        }

        if dueBefore != nil || dueAfter != nil {
            if let before = dueBefore {
                appliedFilters.append("dueBefore=\(before)")
                summaryParts.append("due before \(before)")
            }
            if let after = dueAfter {
                appliedFilters.append("dueAfter=\(after)")
                summaryParts.append("due after \(after)")
            }
        }

        if let hasN = hasNotes {
            appliedFilters.append("hasNotes=\(hasN)")
            summaryParts.append(hasN ? "with notes" : "without notes")
        }

        if let hasD = hasDueDate {
            appliedFilters.append("hasDueDate=\(hasD)")
            summaryParts.append(hasD ? "with due date" : "without due date")
        }

        if let sort = sortBy {
            let order = sortOrder?.lowercased() == "desc" ? "desc" : "asc"
            appliedFilters.append("sortBy=\(sort):\(order)")
        }

        let summary: String
        if summaryParts.isEmpty {
            summary = "All reminders"
        } else {
            let joined = summaryParts.joined(separator: ", ")
            summary = joined.prefix(1).uppercased() + joined.dropFirst()
        }

        let searchFilters = SearchFilters(
            applied: appliedFilters,
            summary: summary
        )

        return SearchResponse(
            reminders: filtered,
            totalCount: totalCount,
            limit: limit,
            offset: offsetValue > 0 ? offsetValue : nil,
            filters: searchFilters
        )
    }

    // MARK: - Bulk Operations Tools

    /// Mark multiple reminders as complete
    /// - Parameter uuids: Array of reminder UUIDs (comma-separated string)
    @MCPTool
    public func bulk_complete(uuids: String) async throws -> BulkResponse {
        let uuidArray = uuids.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        log("Bulk completing \(uuidArray.count) reminders")

        var processedCount = 0
        var failedCount = 0
        var errors: [String] = []
        var changes: [ChangeRecord] = []

        for uuid in uuidArray {
            do {
                let reminder = try resolveReminder(uuid: uuid)
                let reminderUUID = reminder.calendarItemExternalIdentifier.replacingOccurrences(of: "x-apple-reminder://", with: "")

                if !reminder.isCompleted {
                    changes.append(ChangeRecord(
                        uuid: reminderUUID,
                        field: "isCompleted",
                        from: "false",
                        to: "true"
                    ))
                }

                try reminders.setReminderComplete(reminder, complete: true)
                processedCount += 1
            } catch {
                failedCount += 1
                errors.append("\(uuid): \(error.localizedDescription)")
            }
        }

        return BulkResponse(processedCount: processedCount, failedCount: failedCount, errors: errors, changes: changes)
    }

    /// Mark multiple reminders as incomplete
    /// - Parameter uuids: Array of reminder UUIDs (comma-separated string)
    @MCPTool
    public func bulk_uncomplete(uuids: String) async throws -> BulkResponse {
        let uuidArray = uuids.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        log("Bulk uncompleting \(uuidArray.count) reminders")

        var processedCount = 0
        var failedCount = 0
        var errors: [String] = []
        var changes: [ChangeRecord] = []

        for uuid in uuidArray {
            do {
                let reminder = try resolveReminder(uuid: uuid)
                let reminderUUID = reminder.calendarItemExternalIdentifier.replacingOccurrences(of: "x-apple-reminder://", with: "")

                if reminder.isCompleted {
                    changes.append(ChangeRecord(
                        uuid: reminderUUID,
                        field: "isCompleted",
                        from: "true",
                        to: "false"
                    ))
                }

                try reminders.setReminderComplete(reminder, complete: false)
                processedCount += 1
            } catch {
                failedCount += 1
                errors.append("\(uuid): \(error.localizedDescription)")
            }
        }

        return BulkResponse(processedCount: processedCount, failedCount: failedCount, errors: errors, changes: changes)
    }

    /// Update multiple reminders at once
    /// - Parameters:
    ///   - uuids: Array of reminder UUIDs (comma-separated string)
    ///   - priority: New priority for all (optional)
    ///   - isCompleted: New completion status for all (optional)
    @MCPTool
    public func bulk_update(
        uuids: String,
        priority: String? = nil,
        isCompleted: Bool? = nil
    ) async throws -> BulkResponse {
        let uuidArray = uuids.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        log("Bulk updating \(uuidArray.count) reminders")

        guard priority != nil || isCompleted != nil else {
            throw RemindersMCPError.invalidArguments("Bulk update requires priority and/or isCompleted")
        }

        var processedCount = 0
        var failedCount = 0
        var errors: [String] = []
        var changes: [ChangeRecord] = []

        for uuid in uuidArray {
            do {
                let reminder = try resolveReminder(uuid: uuid)
                let reminderUUID = reminder.calendarItemExternalIdentifier.replacingOccurrences(of: "x-apple-reminder://", with: "")

                if let isCompleted = isCompleted {
                    let oldValue = reminder.isCompleted
                    if oldValue != isCompleted {
                        changes.append(ChangeRecord(
                            uuid: reminderUUID,
                            field: "isCompleted",
                            from: String(oldValue),
                            to: String(isCompleted)
                        ))
                        reminder.isCompleted = isCompleted
                    }
                }

                if let priorityStr = priority {
                    guard let priorityEnum = Priority(fromString: priorityStr) else {
                        throw RemindersMCPError.invalidArguments("Unknown priority: \(priorityStr)")
                    }
                    let newPriority = Int(priorityEnum.value.rawValue)
                    let oldPriority = reminder.priority
                    if oldPriority != newPriority {
                        changes.append(ChangeRecord(
                            uuid: reminderUUID,
                            field: "priority",
                            from: priorityBucket(for: reminder),
                            to: priorityStr
                        ))
                        reminder.priority = newPriority
                    }
                }

                try reminders.updateReminder(reminder)
                processedCount += 1
            } catch {
                failedCount += 1
                errors.append("\(uuid): \(error.localizedDescription)")
            }
        }

        return BulkResponse(processedCount: processedCount, failedCount: failedCount, errors: errors, changes: changes)
    }

    /// Move multiple reminders to a different list
    /// - Parameters:
    ///   - uuids: Array of reminder UUIDs (comma-separated string)
    ///   - targetList: Target list name or UUID
    @MCPTool
    public func bulk_move(uuids: String, targetList: String) async throws -> BulkResponse {
        let uuidArray = uuids.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        log("Bulk moving \(uuidArray.count) reminders to \(targetList)")

        let target = try resolveCalendar(targetList)
        var processedCount = 0
        var failedCount = 0
        var errors: [String] = []
        var changes: [ChangeRecord] = []

        for uuid in uuidArray {
            do {
                let reminder = try resolveReminder(uuid: uuid)
                let reminderUUID = reminder.calendarItemExternalIdentifier.replacingOccurrences(of: "x-apple-reminder://", with: "")
                let oldList = reminder.calendar.title

                changes.append(ChangeRecord(
                    uuid: reminderUUID,
                    field: "list",
                    from: oldList,
                    to: target.title
                ))

                reminder.calendar = target
                try reminders.updateReminder(reminder)
                processedCount += 1
            } catch {
                failedCount += 1
                errors.append("\(uuid): \(error.localizedDescription)")
            }
        }

        return BulkResponse(processedCount: processedCount, failedCount: failedCount, errors: errors, changes: changes)
    }

    /// Archive multiple reminders
    /// - Parameters:
    ///   - uuids: Array of reminder UUIDs (comma-separated string)
    ///   - archiveList: Archive list name (defaults to "Archive")
    ///   - createIfMissing: Create archive list if it doesn't exist
    @MCPTool
    public func bulk_archive(
        uuids: String,
        archiveList: String? = nil,
        createIfMissing: Bool? = nil
    ) async throws -> BulkResponse {
        let uuidArray = uuids.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        log("Bulk archiving \(uuidArray.count) reminders")

        let archiveName = archiveList ?? "Archive"
        let calendar = try ensureArchiveCalendar(
            named: archiveName,
            createIfMissing: createIfMissing ?? false,
            sourceName: nil
        )

        var processedCount = 0
        var failedCount = 0
        var errors: [String] = []
        var changes: [ChangeRecord] = []

        for uuid in uuidArray {
            do {
                let reminder = try resolveReminder(uuid: uuid)
                let reminderUUID = reminder.calendarItemExternalIdentifier.replacingOccurrences(of: "x-apple-reminder://", with: "")
                let oldList = reminder.calendar.title

                changes.append(ChangeRecord(
                    uuid: reminderUUID,
                    field: "list",
                    from: oldList,
                    to: calendar.title
                ))

                reminder.calendar = calendar
                try reminders.updateReminder(reminder)
                processedCount += 1
            } catch {
                failedCount += 1
                errors.append("\(uuid): \(error.localizedDescription)")
            }
        }

        return BulkResponse(processedCount: processedCount, failedCount: failedCount, errors: errors, changes: changes)
    }

    /// Delete multiple reminders
    /// - Parameter uuids: Array of reminder UUIDs (comma-separated string)
    @MCPTool
    public func bulk_delete(uuids: String) async throws -> BulkResponse {
        let uuidArray = uuids.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        log("Bulk deleting \(uuidArray.count) reminders")

        var processedCount = 0
        var failedCount = 0
        var errors: [String] = []

        for uuid in uuidArray {
            do {
                let reminder = try resolveReminder(uuid: uuid)
                try reminders.deleteReminder(reminder)
                processedCount += 1
            } catch {
                failedCount += 1
                errors.append("\(uuid): \(error.localizedDescription)")
            }
        }

        return BulkResponse(processedCount: processedCount, failedCount: failedCount, errors: errors)
    }

    // MARK: - Analytics Tool

    /// Get overview statistics for all reminders
    /// - Parameter mode: Analysis mode (currently only "overview" is supported)
    @MCPTool
    public func reminders_analyze(mode: String? = nil) async throws -> AnalyzeResponse {
        log("Analyzing reminders")

        let calendars = reminders.getCalendars()
        let allReminders = try await fetchReminders(on: calendars, display: .all)

        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: todayStart)!

        let completedCount = allReminders.filter { $0.isCompleted }.count
        let incompleteCount = allReminders.count - completedCount

        let overdueCount = allReminders.filter { reminder in
            guard !reminder.isCompleted,
                  let dueDate = reminder.dueDateComponents?.date else {
                return false
            }
            return dueDate < now
        }.count

        let dueTodayCount = allReminders.filter { reminder in
            guard !reminder.isCompleted,
                  let dueDate = reminder.dueDateComponents?.date else {
                return false
            }
            return dueDate >= todayStart && dueDate < todayEnd
        }.count

        let dueThisWeekCount = allReminders.filter { reminder in
            guard !reminder.isCompleted,
                  let dueDate = reminder.dueDateComponents?.date else {
                return false
            }
            return dueDate >= todayStart && dueDate < weekEnd
        }.count

        var byPriority: [String: Int] = ["none": 0, "low": 0, "medium": 0, "high": 0]
        for reminder in allReminders {
            let bucket = priorityBucket(for: reminder)
            byPriority[bucket, default: 0] += 1
        }

        var byList: [String: Int] = [:]
        for reminder in allReminders {
            let listName = reminder.calendar.title
            byList[listName, default: 0] += 1
        }

        return AnalyzeResponse(
            totalReminders: allReminders.count,
            completedCount: completedCount,
            incompleteCount: incompleteCount,
            overdueCount: overdueCount,
            dueTodayCount: dueTodayCount,
            dueThisWeekCount: dueThisWeekCount,
            byPriority: byPriority,
            byList: byList
        )
    }

    // MARK: - Helper Methods

    private func resolveCalendar(_ identifier: String) throws -> EKCalendar {
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

    private func resolveReminder(uuid: String) throws -> EKReminder {
        let cleanUUID = uuid.replacingOccurrences(of: "x-apple-reminder://", with: "")
        guard let reminder = reminders.getReminderByUUID(cleanUUID) else {
            throw RemindersMCPError.reminderNotFound(uuid)
        }
        return reminder
    }

    private func ensureArchiveCalendar(named name: String, createIfMissing: Bool, sourceName: String?) throws -> EKCalendar {
        if let existing = reminders.getCalendars().first(where: {
            $0.title.compare(name, options: .caseInsensitive) == .orderedSame
        }) {
            return existing
        }

        guard createIfMissing else {
            throw RemindersMCPError.invalidArguments("Archive list '\(name)' not found. Set createIfMissing=true to create it.")
        }

        try reminders.newList(with: name, source: sourceName)

        guard let created = reminders.getCalendars().first(where: {
            $0.title.compare(name, options: .caseInsensitive) == .orderedSame
        }) else {
            throw RemindersMCPError.storeFailure("Failed to create archive list '\(name)'")
        }

        return created
    }

    private func fetchReminders(on calendars: [EKCalendar], display: DisplayOptions) async throws -> [EKReminder] {
        try await withCheckedThrowingContinuation { continuation in
            reminders.reminders(on: calendars, displayOptions: display) { reminders in
                continuation.resume(returning: reminders)
            }
        }
    }

    private func resolvePriority(explicit: String?, inferred: Priority?) -> Priority {
        if let explicit {
            return Priority(fromString: explicit) ?? .none
        }
        if let inferred {
            return inferred
        }
        return .none
    }

    private func resolveDueDate(explicit: String?, inferred: DateComponents?) throws -> DateComponents? {
        if let explicit {
            if let natural = DateComponents(argument: explicit) {
                return natural
            }
            if let date = isoDateFormatter.date(from: explicit) {
                return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            }
            throw RemindersMCPError.invalidArguments("Unable to parse due date: \(explicit)")
        }
        return inferred
    }

    private func parseDate(_ dateString: String) -> Date? {
        if let natural = DateComponents(argument: dateString),
           let date = calendar.date(from: natural) {
            return date
        }
        return isoDateFormatter.date(from: dateString)
    }

    private func priorityBucket(for reminder: EKReminder) -> String {
        switch reminder.priority {
        case 1...4:
            return "high"
        case 5:
            return "medium"
        case 6...9:
            return "low"
        default:
            return "none"
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

            case "createdat", "created":
                let firstDate = first.creationDate
                let secondDate = second.creationDate
                switch (firstDate, secondDate) {
                case (nil, nil): return false
                case (nil, _): return !ascending
                case (_, nil): return ascending
                case (let first?, let second?):
                    return ascending ? first < second : first > second
                }

            default:
                return false
            }
        }
    }

    /// Split filter into filter part and ORDER BY part
    private func splitOrderBy(_ query: String) -> (filter: String, orderBy: String) {
        // Case-insensitive search for ORDER BY
        if let range = query.range(of: "ORDER BY", options: .caseInsensitive) {
            let filterPart = String(query[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let orderPart = String(query[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (filterPart, orderPart)
        }
        return (query, "")
    }

    /// Parse ORDER BY clause: "field1 ASC, field2 DESC" -> [(field1, true), (field2, false)]
    private func parseOrderBy(_ orderClause: String) -> [(field: String, ascending: Bool)] {
        var fields: [(String, Bool)] = []

        let parts = orderClause.split(separator: ",")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            let components = trimmed.split(separator: " ", maxSplits: 1)

            if components.isEmpty { continue }

            let field = String(components[0])
            let ascending: Bool
            if components.count > 1 {
                ascending = components[1].uppercased() != "DESC"
            } else {
                ascending = true  // Default to ASC
            }

            fields.append((field, ascending))
        }

        return fields
    }

    /// Sort by multiple fields in order
    private func sortRemindersByMultipleFields(_ reminders: [EKReminder], _ orderFields: [(field: String, ascending: Bool)]) -> [EKReminder] {
        return reminders.sorted { first, second in
            for (field, ascending) in orderFields {
                // Compare by this field
                let comparison = compareReminders(first, second, by: field, ascending: ascending)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                // If equal, continue to next field
            }
            return false // All fields equal
        }
    }

    /// Compare two reminders by a specific field
    private func compareReminders(_ first: EKReminder, _ second: EKReminder, by field: String, ascending: Bool) -> ComparisonResult {
        let result: ComparisonResult

        switch field.lowercased() {
        case "title":
            let firstTitle = first.title ?? ""
            let secondTitle = second.title ?? ""
            result = firstTitle.compare(secondTitle)

        case "duedate":
            let firstDate = first.dueDateComponents?.date
            let secondDate = second.dueDateComponents?.date
            switch (firstDate, secondDate) {
            case (nil, nil): result = .orderedSame
            case (nil, _): result = .orderedDescending
            case (_, nil): result = .orderedAscending
            case (let f?, let s?): result = f.compare(s)
            }

        case "priority":
            if first.priority < second.priority {
                result = .orderedAscending
            } else if first.priority > second.priority {
                result = .orderedDescending
            } else {
                result = .orderedSame
            }

        case "createdat", "created":
            let firstDate = first.creationDate
            let secondDate = second.creationDate
            switch (firstDate, secondDate) {
            case (nil, nil): result = .orderedSame
            case (nil, _): result = .orderedDescending
            case (_, nil): result = .orderedAscending
            case (let f?, let s?): result = f.compare(s)
            }

        case "list":
            result = first.calendar.title.compare(second.calendar.title)

        default:
            result = .orderedSame
        }

        // Reverse if descending
        return ascending ? result : (result == .orderedAscending ? .orderedDescending : (result == .orderedDescending ? .orderedAscending : .orderedSame))
    }

    private func log(_ message: String) {
        guard verbose else { return }
        fputs("[RemindersMCPServer] \(message)\n", stderr)
    }
}
