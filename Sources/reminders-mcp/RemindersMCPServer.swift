import EventKit
import Foundation
import SwiftMCP
import RemindersLibrary

// MARK: - Error Types

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

public struct ListsResponse: Encodable {
    public let lists: [EKCalendar]
}

public struct ListResponse: Encodable {
    public let list: EKCalendar
}

public struct ReminderResponse: Encodable {
    public let reminder: EKReminder
}

public struct RemindersResponse: Encodable {
    public let reminders: [EKReminder]
}

public struct SearchResponse: Encodable {
    public let reminders: [EKReminder]
    public let count: Int
}

public struct SuccessResponse: Encodable {
    public let success: Bool
}

public struct OverviewResponse: Encodable {
    public let totalReminders: Int
    public let completedCount: Int
    public let incompleteCount: Int
    public let overdueCount: Int
    public let dueTodayCount: Int
    public let dueThisWeekCount: Int
    public let byPriority: [String: Int]
    public let byList: [String: Int]
}

public struct BulkOperationResponse: Encodable {
    public let success: Bool
    public let processedCount: Int
    public let failedCount: Int
    public let errors: [String]
}

// MARK: - MCP Server

@MCPServer
public class RemindersMCPServer {
    private let reminders: Reminders
    private let verbose: Bool
    private let isoDateFormatter: ISO8601DateFormatter

    public init(verbose: Bool = false) {
        self.reminders = Reminders()
        self.verbose = verbose

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoDateFormatter = formatter
    }

    // MARK: - Lists Tools

    /// Get all reminder lists
    @MCPTool
    public func lists_get() async throws -> ListsResponse {
        log("Getting all lists")
        let calendars = reminders.getCalendars()
        return ListsResponse(lists: calendars)
    }

    /// Create a new reminder list
    /// - Parameters:
    ///   - name: Name of the new list
    ///   - source: Optional source name for the list
    @MCPTool
    public func lists_create(name: String, source: String? = nil) async throws -> ListResponse {
        log("Creating list: \(name)")

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
    @MCPTool
    public func lists_delete(identifier: String) async throws -> SuccessResponse {
        log("Deleting list: \(identifier)")

        let calendar = try resolveCalendar(identifier)
        guard calendar.allowsContentModifications else {
            throw RemindersMCPError.listReadOnly(identifier)
        }

        try reminders.store.removeCalendar(calendar, commit: true)
        return SuccessResponse(success: true)
    }

    // MARK: - Reminders Tools

    /// Create a new reminder
    /// - Parameters:
    ///   - list: List name or UUID
    ///   - title: Reminder title
    ///   - notes: Optional notes
    ///   - dueDate: Optional ISO8601 due date (e.g., "2025-10-20T14:00:00Z")
    ///   - priority: Priority level: "none", "low", "medium", or "high" (default: "none")
    ///     - none: No priority (0)
    ///     - high: High priority (1-4, 1 is highest)
    ///     - medium: Medium priority (5)
    ///     - low: Low priority (6-9, 9 is lowest)
    @MCPTool
    public func reminders_create(
        list: String,
        title: String,
        notes: String? = nil,
        dueDate: String? = nil,
        priority: String = "none"
    ) async throws -> ReminderResponse {
        log("Creating reminder: \(title) in list: \(list)")

        let calendar = try resolveCalendar(list)
        let priorityEnum = Priority(rawValue: priority) ?? .none

        var dueDateComponents: DateComponents? = nil
        if let dueDateStr = dueDate {
            if let date = isoDateFormatter.date(from: dueDateStr) {
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
    @MCPTool
    public func reminders_get(uuid: String) async throws -> ReminderResponse {
        log("Getting reminder: \(uuid)")

        let reminder = try resolveReminder(uuid: uuid)
        return ReminderResponse(reminder: reminder)
    }

    /// Update a reminder
    /// - Parameters:
    ///   - uuid: Reminder UUID
    ///   - title: New title (optional)
    ///   - notes: New notes (optional)
    ///   - dueDate: New ISO8601 due date (optional)
    ///   - priority: New priority: "none", "low", "medium", or "high" (optional)
    ///     - none: No priority (0)
    ///     - high: High priority (1-4, 1 is highest)
    ///     - medium: Medium priority (5)
    ///     - low: Low priority (6-9, 9 is lowest)
    ///   - isCompleted: Completion status (optional)
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

        if let title { reminder.title = title }
        if let notes { reminder.notes = notes }
        if let isCompleted { reminder.isCompleted = isCompleted }

        if let priorityStr = priority, let priorityEnum = Priority(rawValue: priorityStr) {
            reminder.priority = Int(priorityEnum.value.rawValue)
        }

        if let dueDateStr = dueDate {
            if let date = isoDateFormatter.date(from: dueDateStr) {
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
    @MCPTool
    public func reminders_delete(uuid: String) async throws -> SuccessResponse {
        log("Deleting reminder: \(uuid)")

        let reminder = try resolveReminder(uuid: uuid)
        try reminders.deleteReminder(reminder)
        return SuccessResponse(success: true)
    }

    /// Mark a reminder as complete
    /// - Parameter uuid: Reminder UUID
    @MCPTool
    public func reminders_complete(uuid: String) async throws -> ReminderResponse {
        log("Completing reminder: \(uuid)")

        let reminder = try resolveReminder(uuid: uuid)
        try reminders.setReminderComplete(reminder, complete: true)
        return ReminderResponse(reminder: reminder)
    }

    /// Mark a reminder as incomplete
    /// - Parameter uuid: Reminder UUID
    @MCPTool
    public func reminders_uncomplete(uuid: String) async throws -> ReminderResponse {
        log("Uncompleting reminder: \(uuid)")

        let reminder = try resolveReminder(uuid: uuid)
        try reminders.setReminderComplete(reminder, complete: false)
        return ReminderResponse(reminder: reminder)
    }

    /// List reminders in a list
    /// - Parameters:
    ///   - list: List name or UUID
    ///   - includeCompleted: Include completed reminders (default: false)
    @MCPTool
    public func reminders_list(
        list: String,
        includeCompleted: Bool = false
    ) async throws -> RemindersResponse {
        log("Listing reminders in: \(list)")

        let calendar = try resolveCalendar(list)
        let displayOptions: DisplayOptions = includeCompleted ? .all : .incomplete

        return try await withCheckedThrowingContinuation { continuation in
            reminders.reminders(on: [calendar], displayOptions: displayOptions) { reminders in
                continuation.resume(returning: RemindersResponse(reminders: reminders))
            }
        }
    }

    // MARK: - Search Tool

    /// Search reminders with filters
    /// - Parameters:
    ///   - query: Text search in title and notes (searches both fields)
    ///   - lists: Filter by list names or UUIDs
    ///   - completed: Filter by completion status: "all", "true", or "false"
    ///   - priority: Filter by priority levels (array of: "none", "low", "medium", "high")
    ///     - none: No priority (0)
    ///     - high: High priority (1-4)
    ///     - medium: Medium priority (5)
    ///     - low: Low priority (6-9)
    ///   - dueBefore: Filter by due date before this ISO8601 date
    ///   - dueAfter: Filter by due date after this ISO8601 date
    ///   - hasNotes: Filter by presence of notes
    ///   - hasDueDate: Filter by presence of due date
    ///   - sortBy: Sort field: title, dueDate, or priority
    ///   - sortOrder: Sort order: asc or desc
    ///   - limit: Maximum number of results
    @MCPTool
    public func search(
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
        log("Searching reminders with query: \(query ?? "none")")

        // Parse display options
        let displayOptions: DisplayOptions
        switch completed?.lowercased() {
        case "true": displayOptions = .complete
        case "false": displayOptions = .incomplete
        default: displayOptions = .all
        }

        // Resolve calendars
        var calendarsToSearch: [EKCalendar] = []
        if let lists = lists {
            for identifier in lists {
                if let calendar = try? resolveCalendar(identifier) {
                    calendarsToSearch.append(calendar)
                }
            }
            if calendarsToSearch.isEmpty {
                // No valid calendars found, return empty results
                return SearchResponse(reminders: [], count: 0)
            }
        } else {
            calendarsToSearch = reminders.getCalendars()
        }

        // Fetch reminders
        let allReminders = try await fetchReminders(on: calendarsToSearch, display: displayOptions)
        var filtered = allReminders

        // Apply text query filter
        if let query = query, !query.isEmpty {
            filtered = filtered.filter { reminder in
                (reminder.title?.localizedCaseInsensitiveContains(query) ?? false) ||
                (reminder.notes?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }

        // Apply priority filter
        if let priorityStrings = priority, !priorityStrings.isEmpty {
            let priorities = priorityStrings.compactMap { Priority(rawValue: $0) }
            filtered = filtered.filter { reminder in
                // Map reminder.priority (Int) to Priority enum
                let reminderPriority: Priority
                switch reminder.priority {
                case 0: reminderPriority = .none
                case 1...4: reminderPriority = .high
                case 5: reminderPriority = .medium
                case 6...9: reminderPriority = .low
                default: reminderPriority = .none
                }
                return priorities.contains(reminderPriority)
            }
        }

        // Apply date filters
        if let dueBefore = dueBefore, let date = isoDateFormatter.date(from: dueBefore) {
            filtered = filtered.filter { reminder in
                guard let dueDate = reminder.dueDateComponents?.date else { return false }
                return dueDate < date
            }
        }

        if let dueAfter = dueAfter, let date = isoDateFormatter.date(from: dueAfter) {
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

        // Apply sorting
        if let sortBy = sortBy {
            let ascending = sortOrder?.lowercased() != "desc"
            filtered = sortReminders(filtered, by: sortBy, ascending: ascending)
        }

        // Apply limit
        if let limit = limit, limit > 0 {
            filtered = Array(filtered.prefix(limit))
        }

        return SearchResponse(reminders: filtered, count: filtered.count)
    }

    // MARK: - Overview & Bulk Operations

    /// Get overview of all reminders with counts and summaries
    /// Returns total counts, overdue, due today/this week, grouped by priority and list
    @MCPTool
    public func reminders_get_overview() async throws -> OverviewResponse {
        log("Getting reminders overview")

        let calendars = reminders.getCalendars()
        let allReminders = try await fetchReminders(on: calendars, display: .all)

        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: todayStart)!

        let completedCount = allReminders.filter { $0.isCompleted }.count
        let incompleteCount = allReminders.count - completedCount

        // Count overdue (incomplete + due date in past)
        let overdueCount = allReminders.filter { reminder in
            !reminder.isCompleted &&
            reminder.dueDateComponents?.date != nil &&
            reminder.dueDateComponents!.date! < now
        }.count

        // Count due today
        let dueTodayCount = allReminders.filter { reminder in
            guard let dueDate = reminder.dueDateComponents?.date else { return false }
            return dueDate >= todayStart && dueDate < todayEnd
        }.count

        // Count due this week
        let dueThisWeekCount = allReminders.filter { reminder in
            guard let dueDate = reminder.dueDateComponents?.date else { return false }
            return dueDate >= todayStart && dueDate < weekEnd
        }.count

        // Group by priority
        var byPriority: [String: Int] = ["none": 0, "low": 0, "medium": 0, "high": 0]
        for reminder in allReminders {
            let priorityName: String
            switch reminder.priority {
            case 0: priorityName = "none"
            case 1...4: priorityName = "high"
            case 5: priorityName = "medium"
            case 6...9: priorityName = "low"
            default: priorityName = "none"
            }
            byPriority[priorityName, default: 0] += 1
        }

        // Group by list
        var byList: [String: Int] = [:]
        for reminder in allReminders {
            let listName = reminder.calendar.title
            byList[listName, default: 0] += 1
        }

        return OverviewResponse(
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

    /// Mark multiple reminders as complete by UUID array
    /// - Parameter uuids: Array of reminder UUIDs to mark as complete
    @MCPTool
    public func reminders_bulk_complete(uuids: [String]) async throws -> BulkOperationResponse {
        log("Bulk completing \(uuids.count) reminders")

        var processedCount = 0
        var failedCount = 0
        var errors: [String] = []

        for uuid in uuids {
            do {
                let reminder = try resolveReminder(uuid: uuid)
                try reminders.setReminderComplete(reminder, complete: true)
                processedCount += 1
            } catch {
                failedCount += 1
                errors.append("Failed to complete \(uuid): \(error.localizedDescription)")
            }
        }

        return BulkOperationResponse(
            success: failedCount == 0,
            processedCount: processedCount,
            failedCount: failedCount,
            errors: errors
        )
    }

    /// Update multiple reminders at once
    /// - Parameters:
    ///   - uuids: Array of reminder UUIDs to update
    ///   - priority: New priority for all reminders: "none", "low", "medium", or "high" (optional)
    ///     - none: No priority (0)
    ///     - high: High priority (1-4)
    ///     - medium: Medium priority (5)
    ///     - low: Low priority (6-9)
    ///   - isCompleted: New completion status for all reminders (optional)
    @MCPTool
    public func reminders_bulk_update(
        uuids: [String],
        priority: String? = nil,
        isCompleted: Bool? = nil
    ) async throws -> BulkOperationResponse {
        log("Bulk updating \(uuids.count) reminders")

        var processedCount = 0
        var failedCount = 0
        var errors: [String] = []

        for uuid in uuids {
            do {
                let reminder = try resolveReminder(uuid: uuid)

                if let isCompleted = isCompleted {
                    reminder.isCompleted = isCompleted
                }

                if let priorityStr = priority, let priorityEnum = Priority(rawValue: priorityStr) {
                    reminder.priority = Int(priorityEnum.value.rawValue)
                }

                try reminders.updateReminder(reminder)
                processedCount += 1
            } catch {
                failedCount += 1
                errors.append("Failed to update \(uuid): \(error.localizedDescription)")
            }
        }

        return BulkOperationResponse(
            success: failedCount == 0,
            processedCount: processedCount,
            failedCount: failedCount,
            errors: errors
        )
    }

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
        // Handle both UUID formats (with or without prefix)
        let cleanUUID = uuid.replacingOccurrences(of: "x-apple-reminder://", with: "")

        guard let reminder = reminders.getReminderByUUID(cleanUUID) else {
            throw RemindersMCPError.reminderNotFound(uuid)
        }

        return reminder
    }

    private func fetchReminders(on calendars: [EKCalendar], display: DisplayOptions) async throws -> [EKReminder] {
        return try await withCheckedThrowingContinuation { continuation in
            reminders.reminders(on: calendars, displayOptions: display) { reminders in
                continuation.resume(returning: reminders)
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
        guard verbose else { return }
        fputs("[RemindersMCPServer] \(message)\n", stderr)
    }
}
