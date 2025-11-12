import EventKit
import Foundation
import SwiftMCP
import RemindersLibrary

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

public struct ListsRequest: Decodable {
    public enum Action: String, Decodable {
        case list
        case create
        case delete
        case ensureArchive
    }

    public let action: Action
    public let list: ListsListPayload?
    public let create: ListsCreatePayload?
    public let delete: ListsDeletePayload?
    public let ensureArchive: ListsEnsureArchivePayload?
}

public struct ListsListPayload: Decodable {
    public let includeReadOnly: Bool?
}

public struct ListsCreatePayload: Decodable {
    public let name: String
    public let source: String?
}

public struct ListsDeletePayload: Decodable {
    public let identifier: String
}

public struct ListsEnsureArchivePayload: Decodable {
    public let name: String?
    public let createIfMissing: Bool?
    public let source: String?
}

public enum AnalyzeMode: String, Decodable {
    case overview
}

public struct AnalyzeRequest: Decodable {
    public let mode: AnalyzeMode?
}

public struct SearchResponse: Encodable {
    public let reminders: [EKReminder]
    public let totalCount: Int
    public let returnedCount: Int
    public let hasMore: Bool
    public let limit: Int?
    public let offset: Int?
    public let filters: SearchFilters?
    public let groups: [SearchGroup]?

    public init(
        reminders: [EKReminder],
        totalCount: Int,
        limit: Int? = nil,
        offset: Int? = nil,
        filters: SearchFilters? = nil,
        groups: [SearchGroup]? = nil
    ) {
        self.reminders = reminders
        self.totalCount = totalCount
        self.returnedCount = reminders.count
        self.hasMore = limit != nil && totalCount > reminders.count + (offset ?? 0)
        self.limit = limit
        self.offset = offset
        self.filters = filters
        self.groups = groups
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
    public let items: [BulkItemResult]
    public let dryRun: Bool
    public let success: Bool

    public init(
        processedCount: Int,
        failedCount: Int,
        errors: [String],
        changes: [ChangeRecord] = [],
        items: [BulkItemResult] = [],
        dryRun: Bool = false
    ) {
        self.processedCount = processedCount
        self.failedCount = failedCount
        self.errors = errors
        self.changes = changes
        self.items = items
        self.dryRun = dryRun
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

    // MARK: - Consolidated MCP Tools

    /// Unified single-reminder CRUD/complete/archive tool.
    ///
    /// ### Supported `action` values
    /// - `create`: Provide `create { title, list?, notes?, dueDate? }`
    /// - `read`: Provide `read { uuid }`
    /// - `update`: Provide `update { uuid, title?, notes?, dueDate?, priority?, tags? }`
    /// - `delete`: Provide `delete { uuid }`
    /// - `complete` / `uncomplete`: Provide `{ uuid }`
    /// - `move`: Provide `move { uuid, targetList }`
    /// - `archive`: Provide `archive { uuid, archiveList?, createIfMissing?, source? }`
    ///
    /// ### Usage Tips
    /// - Use `lists_list` to discover valid list identifiers before move/archive.
    /// - `dueDate` accepts ISO8601 or natural language strings (`"tomorrow 5pm"`).
    /// - `priority` accepts `high|medium|low|none` or numeric `0-9`.
    @MCPTool
    public func reminders_manage(_ request: ManageRequest) async throws -> ManageResponse {
        switch request.action {
        case .create:
            guard let payload = request.create else {
                throw RemindersMCPError.invalidArguments("Missing create payload")
            }
            return try handleManageCreate(payload)
        case .read:
            guard let payload = request.read else {
                throw RemindersMCPError.invalidArguments("Missing read payload")
            }
            return try handleManageRead(uuid: payload.uuid)
        case .update:
            guard let payload = request.update else {
                throw RemindersMCPError.invalidArguments("Missing update payload")
            }
            return try handleManageUpdate(payload)
        case .delete:
            guard let payload = request.delete else {
                throw RemindersMCPError.invalidArguments("Missing delete payload")
            }
            return try handleManageDelete(uuid: payload.uuid)
        case .complete:
            guard let payload = request.complete else {
                throw RemindersMCPError.invalidArguments("Missing complete payload")
            }
            return try handleManageCompletion(uuid: payload.uuid, complete: true)
        case .uncomplete:
            guard let payload = request.uncomplete else {
                throw RemindersMCPError.invalidArguments("Missing uncomplete payload")
            }
            return try handleManageCompletion(uuid: payload.uuid, complete: false)
        case .move:
            guard let payload = request.move else {
                throw RemindersMCPError.invalidArguments("Missing move payload")
            }
            return try handleManageMove(payload)
        case .archive:
            guard let payload = request.archive else {
                throw RemindersMCPError.invalidArguments("Missing archive payload")
            }
            return try handleManageArchive(payload)
        }
    }

    /// Batch reminder operations with optional dry-run reporting.
    ///
    /// ### Supported `action` values
    /// - `complete`, `uncomplete`
    /// - `delete`
    /// - `move` (requires `fields.targetList`)
    /// - `archive` (requires `fields.archiveList?`, `fields.createIfMissing?`)
    ///
    /// ### Example
    /// ```json
    /// {
    ///   "action": "complete",
    ///   "uuids": ["UUID-1", "UUID-2"],
    ///   "dryRun": true
    /// }
    /// ```
    ///
    /// Dry-runs report what *would* change without mutating reminders.
    @MCPTool
    public func reminders_bulk(_ request: BulkRequest) async throws -> BulkResponse {
        guard !request.uuids.isEmpty else {
            throw RemindersMCPError.invalidArguments("Provide at least one UUID for bulk actions")
        }

        let dryRun = request.dryRun ?? false
        var processed = 0
        var failed = 0
        var errors: [String] = []
        var changeLog: [ChangeRecord] = []
        var itemResults: [BulkItemResult] = []

        for uuid in request.uuids {
            do {
                let result = try handleBulkAction(uuid: uuid, action: request.action, fields: request.fields, dryRun: dryRun)
                if result.success {
                    processed += 1
                    changeLog.append(contentsOf: result.changes)
                } else {
                    failed += 1
                    if let message = result.message {
                        errors.append("\(uuid): \(message)")
                    }
                }
                itemResults.append(result)
            } catch {
                failed += 1
                errors.append("\(uuid): \(error.localizedDescription)")
                itemResults.append(BulkItemResult(uuid: uuid, success: false, message: error.localizedDescription, changes: []))
            }
        }

        return BulkResponse(
            processedCount: processed,
            failedCount: failed,
            errors: errors,
            changes: changeLog,
            items: itemResults,
            dryRun: dryRun
        )
    }

    /// Advanced reminder search with logic trees, natural language dates, grouping, and pagination.
    ///
    /// ### Logic tree helpers
    /// - Use `logic.all` for AND, `logic.any` for OR, `logic.not` to invert.
    /// - Leaf nodes use `{ "clause": { "field": "priority", "op": "in", "value": ["high","medium"] } }`.
    /// - Supported fields: `title`, `notes`, `list`, `priority`, `tag`, `dueDate`, `createdAt`, `updatedAt`, `completed`, `hasDueDate`, `hasNotes`.
    /// - Date literals accept ISO8601 or natural phrases (`"today"`, `"next week"`, `"friday+2"`).
    ///
    /// ### Example payload
    /// ```json
    /// {
    ///   "logic": {
    ///     "all": [
    ///       { "clause": { "field": "priority", "op": "in", "value": ["high","medium"] } },
    ///       { "clause": { "field": "list", "op": "equals", "value": "Work" } },
    ///       { "clause": { "field": "dueDate", "op": "lessOrEqual", "value": "end of week" } }
    ///     ]
    ///   },
    ///   "sort": [{ "field": "dueDate", "direction": "asc" }],
    ///   "pagination": { "limit": 25 }
    /// }
    /// ```
    ///
    /// ### Request tips
    /// - `logic`: structured filtering (preferred over ad-hoc parsing).
    /// - `query`: lightweight fuzzy search across title + notes.
    /// - `sort`: array of `{ "field": "dueDate", "direction": "asc" }`.
    /// - `pagination`: `{ "limit": 25, "offset": 50 }`.
    /// - `groupBy`: group counts by list/priority/tag with optional `granularity` for dates.
    @MCPTool
    public func reminders_search(_ request: SearchRequest) async throws -> SearchResponse {
        let includeCompleted = request.includeCompleted ?? false
        let displayOptions: DisplayOptions = includeCompleted ? .all : .incomplete

        let calendars: [EKCalendar]
        if let listFilters = request.lists, !listFilters.isEmpty {
            calendars = try listFilters.map { try resolveCalendar($0) }
        } else {
            calendars = reminders.getCalendars()
        }

        var reminders = try await fetchReminders(on: calendars, display: displayOptions)

        if let logic = request.logic, !logic.isEmpty {
            reminders = reminders.filter { reminder in
                evaluateLogicNode(logic, reminder: reminder)
            }
        }

        if let query = request.query, !query.isEmpty {
            reminders = reminders.filter { reminder in
                (reminder.title?.localizedCaseInsensitiveContains(query) ?? false) ||
                (reminder.notes?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }

        if let sortDescriptors = request.sort, !sortDescriptors.isEmpty {
            reminders = sortReminders(reminders, descriptors: sortDescriptors)
        }

        let totalCount = reminders.count
        var pagedReminders = reminders
        var appliedLimit: Int?
        var appliedOffset: Int?

        if let pagination = request.pagination {
            appliedLimit = pagination.limit
            appliedOffset = pagination.offset
            let start = max(0, pagination.offset ?? 0)
            if let limit = pagination.limit, limit > 0 {
                let end = min(totalCount, start + limit)
                pagedReminders = start < totalCount ? Array(reminders[start..<end]) : []
            } else if start > 0 {
                pagedReminders = start < totalCount ? Array(reminders[start...]) : []
            }
        }

        let groups = buildGroups(for: reminders, descriptors: request.groupBy)

        return SearchResponse(
            reminders: pagedReminders,
            totalCount: totalCount,
            limit: appliedLimit,
            offset: appliedOffset,
            groups: groups
        )
    }

    /// List discovery, creation, deletion, and archive helpers.
    ///
    /// ### Supported actions
    /// - `list`: `{ "includeReadOnly": false }` lists available reminder lists.
    /// - `create`: `{ "name": "Projects", "source": "iCloud" }`.
    /// - `delete`: `{ "identifier": "<list name or UUID>" }`.
    /// - `ensureArchive`: `{ "name": "Archive", "createIfMissing": true }`.
    ///
    /// Use `list` results to drive other tools (eg. `move`, `archive`) so you always pass valid identifiers.
    @MCPTool
    public func reminders_lists(_ request: ListsRequest) async throws -> ListsResponse {
        switch request.action {
        case .list:
            let includeReadOnly = request.list?.includeReadOnly ?? false
            log("Listing reminder lists (include read-only: \(includeReadOnly))")
            let calendars = reminders.store.calendars(for: .reminder).filter {
                includeReadOnly ? true : $0.allowsContentModifications
            }
            return ListsResponse(lists: calendars, message: "Lists fetched")
        case .create:
            guard let payload = request.create else {
                throw RemindersMCPError.invalidArguments("Missing create payload for lists action")
            }
            return try handleListCreate(name: payload.name, source: payload.source)
        case .delete:
            guard let payload = request.delete else {
                throw RemindersMCPError.invalidArguments("Missing delete payload for lists action")
            }
            return try handleListDelete(identifier: payload.identifier)
        case .ensureArchive:
            guard let payload = request.ensureArchive else {
                throw RemindersMCPError.invalidArguments("Missing ensureArchive payload")
            }
            return try handleEnsureArchive(payload: payload)
        }
    }

    /// Aggregate reminder analytics (overview mode).
    ///
    /// Returns counts for:
    /// - completed vs incomplete
    /// - overdue, due today, due this week
    /// - per-priority and per-list distribution
    ///
    /// Future modes can expand the `AnalyzeRequest` enum; for now send `{ "mode": "overview" }` or omit the body.
    @MCPTool
    public func reminders_analyze(_ request: AnalyzeRequest? = nil) async throws -> AnalyzeResponse {
        let mode = request?.mode ?? .overview
        switch mode {
        case .overview:
            return try await performOverviewAnalysis()
        }
    }

    // MARK: - Manage Action Helpers

    private func handleManageCreate(_ payload: ManageCreatePayload) throws -> ManageResponse {
        let metadata = TitleParser.parse(payload.title)

        var parsedList: ParsedField?
        var parsedPriority: ParsedField?
        var parsedTags: [ParsedField]?
        var parsedDueDate: ParsedField?

        let listIdentifier: String
        if let explicitList = payload.list, !explicitList.isEmpty {
            listIdentifier = explicitList
        } else if let extractedList = metadata.listName {
            listIdentifier = extractedList
            parsedList = ParsedField(original: "@\(extractedList)", parsed: extractedList)
        } else {
            throw RemindersMCPError.invalidArguments("Provide list parameter or include @listname in title")
        }

        let calendar = try resolveCalendar(listIdentifier)
        let priorityValue = resolvePriority(explicit: payload.priority, inferred: metadata.priority)

        if payload.priority == nil, let inferredPriority = metadata.priority {
            parsedPriority = ParsedField(original: "!\(inferredPriority.rawValue)", parsed: inferredPriority.rawValue)
        }

        if !metadata.tags.isEmpty {
            parsedTags = metadata.tags.map { tag in
                ParsedField(original: "#\(tag)", parsed: tag)
            }
        }

        let dueComponents = try resolveDueDate(explicit: payload.dueDate, inferred: metadata.dueDate)

        if payload.dueDate == nil, metadata.dueDate != nil {
            if let naturalDate = metadata.dueDate?.date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                parsedDueDate = ParsedField(original: "(natural language date)", parsed: formatter.string(from: naturalDate))
            }
        }

        let reminder = try reminders.createReminder(
            title: metadata.cleanedTitle,
            notes: payload.notes,
            calendar: calendar,
            dueDateComponents: dueComponents,
            priority: priorityValue
        )

        let parsedMetadata = ParsedMetadata(
            list: parsedList,
            priority: parsedPriority,
            tags: parsedTags,
            dueDate: parsedDueDate
        )

        return ManageResponse(reminder: reminder, message: "Reminder created", parsed: parsedMetadata)
    }

    private func handleManageRead(uuid: String) throws -> ManageResponse {
        let reminder = try resolveReminder(uuid: uuid)
        return ManageResponse(reminder: reminder, message: "Reminder fetched")
    }

    private func handleManageUpdate(_ payload: ManageUpdatePayload) throws -> ManageResponse {
        let reminder = try resolveReminder(uuid: payload.uuid)

        if let title = payload.title {
            let metadata = TitleParser.parse(title)
            reminder.title = metadata.cleanedTitle

            if payload.priority == nil, let extractedPriority = metadata.priority {
                reminder.priority = Int(extractedPriority.value.rawValue)
            }

            if payload.dueDate == nil, let extractedDate = metadata.dueDate {
                reminder.dueDateComponents = extractedDate
            }
        }

        if let notes = payload.notes {
            reminder.notes = notes
        }

        if let isCompleted = payload.isCompleted {
            reminder.isCompleted = isCompleted
        }

        if let priorityString = payload.priority {
            guard let priorityEnum = Priority(fromString: priorityString) else {
                throw RemindersMCPError.invalidArguments("Unknown priority: \(priorityString)")
            }
            reminder.priority = Int(priorityEnum.value.rawValue)
        }

        if let dueDateString = payload.dueDate {
            if let components = try resolveDueDate(explicit: dueDateString, inferred: nil) {
                reminder.dueDateComponents = components
            } else {
                reminder.dueDateComponents = nil
            }
        }

        try reminders.updateReminder(reminder)
        return ManageResponse(reminder: reminder, message: "Reminder updated")
    }

    private func handleManageDelete(uuid: String) throws -> ManageResponse {
        let reminder = try resolveReminder(uuid: uuid)
        try reminders.deleteReminder(reminder)
        return ManageResponse(reminder: nil, message: "Reminder deleted")
    }

    private func handleManageCompletion(uuid: String, complete: Bool) throws -> ManageResponse {
        let reminder = try resolveReminder(uuid: uuid)
        try reminders.setReminderComplete(reminder, complete: complete)
        let message = complete ? "Reminder completed" : "Reminder marked incomplete"
        return ManageResponse(reminder: reminder, message: message)
    }

    private func handleManageMove(_ payload: ManageMovePayload) throws -> ManageResponse {
        let reminder = try resolveReminder(uuid: payload.uuid)
        let target = try resolveCalendar(payload.targetList)
        let previousList = reminder.calendar.title
        reminder.calendar = target
        try reminders.updateReminder(reminder)
        let message = previousList == target.title ? "Reminder already in \(target.title)" : "Reminder moved to \(target.title)"
        return ManageResponse(reminder: reminder, message: message)
    }

    private func handleManageArchive(_ payload: ManageArchivePayload) throws -> ManageResponse {
        let reminder = try resolveReminder(uuid: payload.uuid)
        let archiveName = payload.archiveList ?? "Archive"
        let archiveCalendar = try ensureArchiveCalendar(
            named: archiveName,
            createIfMissing: payload.createIfMissing ?? false,
            sourceName: payload.source
        )
        reminder.calendar = archiveCalendar
        try reminders.updateReminder(reminder)
        return ManageResponse(reminder: reminder, message: "Reminder archived to \(archiveCalendar.title)")
    }

    // MARK: - List Helpers

    private func handleListCreate(name: String, source: String?) throws -> ListsResponse {
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

    private func handleListDelete(identifier: String) throws -> ListsResponse {
        let calendar = try resolveCalendar(identifier)
        guard calendar.allowsContentModifications else {
            throw RemindersMCPError.listReadOnly(identifier)
        }

        try reminders.store.removeCalendar(calendar, commit: true)
        return ListsResponse(lists: [], message: "List '\(calendar.title)' deleted")
    }

    private func handleEnsureArchive(payload: ListsEnsureArchivePayload) throws -> ListsResponse {
        let archiveName = payload.name ?? "Archive"
        let existedBefore = reminders.getCalendars().contains {
            $0.title.compare(archiveName, options: .caseInsensitive) == .orderedSame
        }

        let calendar = try ensureArchiveCalendar(
            named: archiveName,
            createIfMissing: payload.createIfMissing ?? false,
            sourceName: payload.source
        )

        let message = existedBefore ? "Archive list already exists" : "Archive list created"
        return ListsResponse(lists: [calendar], message: message)
    }

    private func performOverviewAnalysis() async throws -> AnalyzeResponse {
        let calendars = reminders.getCalendars()
        let allReminders = try await fetchReminders(on: calendars, display: .all)

        let completedCount = allReminders.filter { $0.isCompleted }.count
        let incompleteCount = allReminders.count - completedCount
        let overdueCount = allReminders.filter { reminder in
            guard let dueDate = reminder.dueDateComponents?.date else { return false }
            return dueDate < Date() && !reminder.isCompleted
        }.count

        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: today)!

        let dueTodayCount = allReminders.filter { reminder in
            guard let dueDate = reminder.dueDateComponents?.date else { return false }
            return dueDate >= today && dueDate < tomorrow && !reminder.isCompleted
        }.count

        let dueThisWeekCount = allReminders.filter { reminder in
            guard let dueDate = reminder.dueDateComponents?.date else { return false }
            return dueDate >= today && dueDate < nextWeek && !reminder.isCompleted
        }.count

        var byPriority: [String: Int] = [:]
        var byList: [String: Int] = [:]

        for reminder in allReminders {
            let bucket = priorityBucket(for: reminder)
            byPriority[bucket, default: 0] += 1
            byList[reminder.calendar.title, default: 0] += 1
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

    // MARK: - Bulk Helpers

    private func handleBulkAction(
        uuid: String,
        action: BulkAction,
        fields: BulkFieldChanges?,
        dryRun: Bool
    ) throws -> BulkItemResult {
        let reminder = try resolveReminder(uuid: uuid)
        let reminderUUID = reminderIdentifier(reminder)
        var changes: [ChangeRecord] = []
        var message = ""
        let success = true

        switch action {
        case .complete:
            if reminder.isCompleted {
                message = "Already completed"
            } else {
                changes.append(ChangeRecord(uuid: reminderUUID, field: "isCompleted", from: "false", to: "true"))
                if !dryRun {
                    try reminders.setReminderComplete(reminder, complete: true)
                }
                message = dryRun ? "Dry-run: would mark complete" : "Reminder completed"
            }

        case .uncomplete:
            if !reminder.isCompleted {
                message = "Already incomplete"
            } else {
                changes.append(ChangeRecord(uuid: reminderUUID, field: "isCompleted", from: "true", to: "false"))
                if !dryRun {
                    try reminders.setReminderComplete(reminder, complete: false)
                }
                message = dryRun ? "Dry-run: would mark incomplete" : "Reminder marked incomplete"
            }

        case .delete:
            changes.append(ChangeRecord(uuid: reminderUUID, field: "deleted", from: "false", to: "true"))
            if !dryRun {
                try reminders.deleteReminder(reminder)
            }
            message = dryRun ? "Dry-run: would delete" : "Reminder deleted"

        case .move:
            guard let targetList = fields?.targetList else {
                throw RemindersMCPError.invalidArguments("Bulk move requires targetList in fields")
            }
            let target = try resolveCalendar(targetList)
            let oldList = reminder.calendar.title
            if oldList.caseInsensitiveCompare(target.title) == .orderedSame {
                message = "Reminder already in \(target.title)"
            } else {
                changes.append(ChangeRecord(uuid: reminderUUID, field: "list", from: oldList, to: target.title))
                if !dryRun {
                    reminder.calendar = target
                    try reminders.updateReminder(reminder)
                }
                message = dryRun ? "Dry-run: would move to \(target.title)" : "Reminder moved to \(target.title)"
            }

        case .archive:
            let archiveName = fields?.archiveList ?? "Archive"
            let archiveCalendar = try ensureArchiveCalendar(
                named: archiveName,
                createIfMissing: fields?.createArchiveIfMissing ?? false,
                sourceName: nil
            )
            let oldList = reminder.calendar.title
            if oldList.caseInsensitiveCompare(archiveCalendar.title) == .orderedSame {
                message = "Already archived"
            } else {
                changes.append(ChangeRecord(uuid: reminderUUID, field: "list", from: oldList, to: archiveCalendar.title))
                if !dryRun {
                    reminder.calendar = archiveCalendar
                    try reminders.updateReminder(reminder)
                }
                message = dryRun ? "Dry-run: would archive to \(archiveCalendar.title)" : "Reminder archived"
            }

        case .update:
            guard let fields else {
                throw RemindersMCPError.invalidArguments("Bulk update requires fields payload")
            }
            var mutated = false

            if let title = fields.title {
                changes.append(ChangeRecord(uuid: reminderUUID, field: "title", from: reminder.title ?? "", to: title))
                if !dryRun {
                    reminder.title = title
                }
                mutated = true
            }

            if let notes = fields.notes {
                changes.append(ChangeRecord(uuid: reminderUUID, field: "notes", from: reminder.notes ?? "", to: notes))
                if !dryRun {
                    reminder.notes = notes
                }
                mutated = true
            }

            if let priorityString = fields.priority {
                guard let priorityEnum = Priority(fromString: priorityString) else {
                    throw RemindersMCPError.invalidArguments("Unknown priority: \(priorityString)")
                }
                let newValue = Int(priorityEnum.value.rawValue)
                changes.append(ChangeRecord(uuid: reminderUUID, field: "priority", from: "\(reminder.priority)", to: "\(newValue)"))
                if !dryRun {
                    reminder.priority = newValue
                }
                mutated = true
            }

            if let isCompleted = fields.isCompleted {
                changes.append(ChangeRecord(uuid: reminderUUID, field: "isCompleted", from: "\(reminder.isCompleted)", to: "\(isCompleted)"))
                if !dryRun {
                    reminder.isCompleted = isCompleted
                }
                mutated = true
            }

            if let dueDateString = fields.dueDate {
                let oldDate = reminder.dueDateComponents?.date?.description ?? "nil"
                let newComponents = try resolveDueDate(explicit: dueDateString, inferred: nil)
                let newDate = newComponents?.date?.description ?? "nil"
                changes.append(ChangeRecord(uuid: reminderUUID, field: "dueDate", from: oldDate, to: newDate))
                if !dryRun {
                    reminder.dueDateComponents = newComponents
                }
                mutated = true
            }

            if mutated {
                if !dryRun {
                    try reminders.updateReminder(reminder)
                }
                message = dryRun ? "Dry-run: would update reminder" : "Reminder updated"
            } else {
                message = "No fields changed"
            }
        }

        return BulkItemResult(uuid: reminderUUID, success: success, message: message, changes: changes)
    }

    private func reminderIdentifier(_ reminder: EKReminder) -> String {
        canonicalUUID(from: reminder.calendarItemExternalIdentifier ?? reminder.calendarItemIdentifier)
    }

    private func canonicalUUID(from identifier: String?) -> String {
        guard let identifier else { return UUID().uuidString }
        return identifier.replacingOccurrences(of: "x-apple-reminder://", with: "")
    }

    // MARK: - Search Helpers

    private func buildGroups(for reminders: [EKReminder], descriptors: [SearchGrouping]?) -> [SearchGroup]? {
        guard let descriptors, !descriptors.isEmpty else { return nil }
        return buildGroups(reminders: reminders, descriptorIndex: 0, descriptors: descriptors)
    }

    private func buildGroups(
        reminders: [EKReminder],
        descriptorIndex: Int,
        descriptors: [SearchGrouping]
    ) -> [SearchGroup] {
        guard descriptorIndex < descriptors.count else { return [] }
        let descriptor = descriptors[descriptorIndex]
        var buckets: [String: [EKReminder]] = [:]

        for reminder in reminders {
            for key in groupKeys(for: reminder, grouping: descriptor) {
                buckets[key, default: []].append(reminder)
            }
        }

        let sortedKeys = buckets.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        return sortedKeys.map { key in
            let bucketReminders = buckets[key] ?? []
            let childGroups = buildGroups(reminders: bucketReminders, descriptorIndex: descriptorIndex + 1, descriptors: descriptors)
            return SearchGroup(
                field: descriptor.field.rawValue,
                value: key,
                count: bucketReminders.count,
                reminderUUIDs: bucketReminders.map(reminderIdentifier),
                children: childGroups.isEmpty ? nil : childGroups
            )
        }
    }

    private func groupKeys(for reminder: EKReminder, grouping: SearchGrouping) -> [String] {
        switch grouping.field {
        case .priority:
            return [priorityBucket(for: reminder)]
        case .list:
            return [reminder.calendar.title]
        case .tag:
            let tags = tags(for: reminder)
            return tags.isEmpty ? ["<none>"] : tags
        case .dueDate:
            let value = groupValue(for: reminder.dueDateComponents?.date, granularity: grouping.granularity)
            return [value]
        }
    }

    private func groupValue(for date: Date?, granularity: SearchDateGranularity?) -> String {
        guard let date else { return "none" }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = calendar.timeZone

        switch granularity ?? .day {
        case .day:
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        case .week:
            let weekOfYear = calendar.component(.weekOfYear, from: date)
            let year = calendar.component(.yearForWeekOfYear, from: date)
            return "Week \(weekOfYear), \(year)"
        case .month:
            formatter.dateFormat = "LLLL yyyy"
            return formatter.string(from: date)
        }
    }

    private func tags(for reminder: EKReminder) -> [String] {
        // Placeholder until Private API tag support is implemented.
        return []
    }

    private func evaluateLogicNode(_ node: LogicNode, reminder: EKReminder) -> Bool {
        var evaluations: [Bool] = []

        if let clause = node.clause {
            evaluations.append(evaluateClause(clause, reminder: reminder))
        }

        if let allNodes = node.all {
            evaluations.append(allNodes.allSatisfy { evaluateLogicNode($0, reminder: reminder) })
        }

        if let anyNodes = node.any {
            evaluations.append(anyNodes.contains { evaluateLogicNode($0, reminder: reminder) })
        }

        if let xorNodes = node.xor {
            let trueCount = xorNodes.filter { evaluateLogicNode($0, reminder: reminder) }.count
            evaluations.append(trueCount == 1)
        }

        if let notNode = node.not {
            evaluations.append(!evaluateLogicNode(notNode, reminder: reminder))
        }

        return evaluations.isEmpty ? true : evaluations.allSatisfy { $0 }
    }

    private func evaluateClause(_ clause: SearchClause, reminder: EKReminder) -> Bool {
        switch clause.field {
        case .title:
            return evaluateString(reminder.title, op: clause.op, value: clause.value)
        case .notes:
            return evaluateString(reminder.notes, op: clause.op, value: clause.value)
        case .list:
            return evaluateString(reminder.calendar.title, op: clause.op, value: clause.value)
        case .listId:
            return evaluateString(reminder.calendar.calendarIdentifier, op: clause.op, value: clause.value)
        case .priority:
            return evaluateString(priorityBucket(for: reminder), op: clause.op, value: clause.value)
        case .tag:
            let tagValues = tags(for: reminder)
            return evaluateCollection(tagValues, op: clause.op, value: clause.value)
        case .dueDate:
            return evaluateDate(reminder.dueDateComponents?.date, op: clause.op, value: clause.value)
        case .createdAt:
            return evaluateDate(reminder.creationDate, op: clause.op, value: clause.value)
        case .updatedAt:
            return evaluateDate(reminder.lastModifiedDate, op: clause.op, value: clause.value)
        case .completed:
            return evaluateBool(reminder.isCompleted, op: clause.op, value: clause.value)
        case .hasDueDate:
            return evaluateBool(reminder.dueDateComponents != nil, op: clause.op, value: clause.value)
        case .hasNotes:
            let hasNotes = (reminder.notes?.isEmpty == false)
            return evaluateBool(hasNotes, op: clause.op, value: clause.value)
        }
    }

    private func evaluateString(_ lhs: String?, op: SearchOperator, value: SearchValue?) -> Bool {
        let left = lhs ?? ""
        switch op {
        case .equals:
            return left.compare(value?.stringValue ?? "", options: .caseInsensitive) == .orderedSame
        case .notEquals:
            return left.compare(value?.stringValue ?? "", options: .caseInsensitive) != .orderedSame
        case .contains:
            return evaluateContains(haystack: left, needle: value?.stringValue, negate: false)
        case .notContains:
            return evaluateContains(haystack: left, needle: value?.stringValue, negate: true)
        case .like, .notLike:
            return evaluateLike(haystack: left, pattern: value?.stringValue, negate: op == .notLike)
        case .matches, .notMatches:
            return evaluateRegex(haystack: left, pattern: value?.stringValue, negate: op == .notMatches)
        case .in:
            guard let options = value?.stringArray else { return false }
            return options.contains { option in
                left.compare(option, options: .caseInsensitive) == .orderedSame
            }
        case .notIn:
            guard let options = value?.stringArray else { return true }
            return !options.contains { option in
                left.compare(option, options: .caseInsensitive) == .orderedSame
            }
        case .includes, .excludes:
            return evaluateContains(haystack: left, needle: value?.stringValue, negate: op == .excludes)
        case .exists:
            return !left.isEmpty
        case .notExists:
            return left.isEmpty
        default:
            return false
        }
    }

    private func evaluateBool(_ lhs: Bool, op: SearchOperator, value: SearchValue?) -> Bool {
        switch op {
        case .equals:
            return lhs == (value?.boolValue ?? false)
        case .notEquals:
            return lhs != (value?.boolValue ?? false)
        case .exists:
            return true
        case .notExists:
            return false
        default:
            return false
        }
    }

    private func evaluateDate(_ lhs: Date?, op: SearchOperator, value: SearchValue?) -> Bool {
        guard let lhs else {
            return op == .notExists
        }

        switch op {
        case .before:
            guard let rhs = parseDateValue(value) else { return false }
            return lhs < rhs
        case .after:
            guard let rhs = parseDateValue(value) else { return false }
            return lhs > rhs
        case .equals:
            guard let rhs = parseDateValue(value) else { return false }
            return abs(lhs.timeIntervalSince(rhs)) < 1
        case .notEquals:
            guard let rhs = parseDateValue(value) else { return false }
            return abs(lhs.timeIntervalSince(rhs)) >= 1
        case .greaterThan:
            guard let rhs = parseDateValue(value) else { return false }
            return lhs > rhs
        case .lessThan:
            guard let rhs = parseDateValue(value) else { return false }
            return lhs < rhs
        case .greaterOrEqual:
            guard let rhs = parseDateValue(value) else { return false }
            return lhs >= rhs
        case .lessOrEqual:
            guard let rhs = parseDateValue(value) else { return false }
            return lhs <= rhs
        case .exists:
            return true
        case .notExists:
            return false
        default:
            return false
        }
    }

    private func evaluateCollection(_ collection: [String], op: SearchOperator, value: SearchValue?) -> Bool {
        switch op {
        case .includes:
            guard let needle = value?.stringValue else { return false }
            return collection.contains { $0.compare(needle, options: .caseInsensitive) == .orderedSame }
        case .excludes:
            guard let needle = value?.stringValue else { return true }
            return !collection.contains { $0.compare(needle, options: .caseInsensitive) == .orderedSame }
        case .in:
            guard let needles = value?.stringArray else { return false }
            return !collection.filter { item in
                needles.contains { $0.compare(item, options: .caseInsensitive) == .orderedSame }
            }.isEmpty
        case .notIn:
            guard let needles = value?.stringArray else { return true }
            return collection.allSatisfy { item in
                needles.contains { $0.compare(item, options: .caseInsensitive) == .orderedSame } == false
            }
        case .exists:
            return !collection.isEmpty
        case .notExists:
            return collection.isEmpty
        default:
            if let stringValue = value?.stringValue {
                return collection.contains { $0.compare(stringValue, options: .caseInsensitive) == .orderedSame }
            }
            return false
        }
    }

    private func evaluateContains(haystack: String, needle: String?, negate: Bool) -> Bool {
        guard let needle, !needle.isEmpty else { return negate }
        let result = haystack.range(of: needle, options: .caseInsensitive) != nil
        return negate ? !result : result
    }

    private func evaluateLike(haystack: String, pattern: String?, negate: Bool) -> Bool {
        guard let pattern else { return negate }
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        return evaluateRegex(haystack: haystack, pattern: "^\(escaped)$", negate: negate)
    }

    private func evaluateRegex(haystack: String, pattern: String?, negate: Bool) -> Bool {
        guard let pattern, let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return negate
        }
        let range = NSRange(location: 0, length: haystack.utf16.count)
        let matches = regex.firstMatch(in: haystack, options: [], range: range) != nil
        return negate ? !matches : matches
    }

    private func parseDateValue(_ value: SearchValue?) -> Date? {
        guard let stringValue = value?.stringValue else { return nil }
        return parseDate(stringValue)
    }

    private func sortReminders(_ reminders: [EKReminder], descriptors: [SearchSortDescriptor]) -> [EKReminder] {
        guard !descriptors.isEmpty else { return reminders }
        return reminders.sorted { lhs, rhs in
            for descriptor in descriptors {
                let comparison = compare(lhs, rhs, descriptor: descriptor)
                if comparison != .orderedSame {
                    return descriptor.direction == .asc ? comparison == .orderedAscending : comparison == .orderedDescending
                }
            }
            return false
        }
    }

    private func compare(_ lhs: EKReminder, _ rhs: EKReminder, descriptor: SearchSortDescriptor) -> ComparisonResult {
        switch descriptor.field {
        case .title:
            return (lhs.title ?? "").localizedCaseInsensitiveCompare(rhs.title ?? "")
        case .list:
            return lhs.calendar.title.localizedCaseInsensitiveCompare(rhs.calendar.title)
        case .tag:
            let left = tags(for: lhs).sorted().first ?? ""
            let right = tags(for: rhs).sorted().first ?? ""
            return left.localizedCaseInsensitiveCompare(right)
        case .priority:
            return priorityBucket(for: lhs).localizedCaseInsensitiveCompare(priorityBucket(for: rhs))
        case .dueDate:
            return compareDates(lhs.dueDateComponents?.date, rhs.dueDateComponents?.date)
        case .createdAt:
            return compareDates(lhs.creationDate, rhs.creationDate)
        case .updatedAt:
            return compareDates(lhs.lastModifiedDate, rhs.lastModifiedDate)
        }
    }

    private func compareDates(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        case (let left?, let right?): return left.compare(right)
        }
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
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var keyword = trimmed.lowercased()
        if keyword.hasSuffix("()") {
            keyword = String(keyword.dropLast(2))
        }
        keyword = keyword.replacingOccurrences(of: "_", with: " ")

        if let keywordDate = dateFromKeyword(keyword) {
            return keywordDate
        }

        if let natural = DateComponents(argument: trimmed),
           let date = calendar.date(from: natural) {
            return date
        }

        return isoDateFormatter.date(from: trimmed)
    }

    private func dateFromKeyword(_ keyword: String) -> Date? {
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        switch keyword {
        case "now":
            return now
        case "today":
            return startOfToday
        case "tomorrow":
            return calendar.date(byAdding: .day, value: 1, to: startOfToday)
        case "yesterday":
            return calendar.date(byAdding: .day, value: -1, to: startOfToday)
        case "next week":
            return calendar.date(byAdding: .day, value: 7, to: startOfToday)
        case "last week":
            return calendar.date(byAdding: .day, value: -7, to: startOfToday)
        case "next month":
            return calendar.date(byAdding: .month, value: 1, to: startOfToday)
        case "last month":
            return calendar.date(byAdding: .month, value: -1, to: startOfToday)
        default:
            break
        }

        if keyword.hasPrefix("next ") {
            let token = String(keyword.dropFirst(5))
            return dateForWeekday(named: token, direction: .forward)
        }

        if keyword.hasPrefix("last ") {
            let token = String(keyword.dropFirst(5))
            return dateForWeekday(named: token, direction: .backward)
        }

        return nil
    }

    private func dateForWeekday(named name: String, direction: Calendar.SearchDirection) -> Date? {
        guard let weekday = weekdayNumber(from: name) else { return nil }
        var components = DateComponents()
        components.weekday = weekday
        return calendar.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime, direction: direction)
    }

    private func weekdayNumber(from name: String) -> Int? {
        let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let weekdays = calendar.weekdaySymbols.map { $0.lowercased() }
        if let index = weekdays.firstIndex(of: lower) {
            return index + 1 // Calendar weekday is 1-based
        }

        let shortWeekdays = calendar.shortWeekdaySymbols.map { $0.lowercased() }
        if let index = shortWeekdays.firstIndex(of: lower) {
            return index + 1
        }

        return nil
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

    private func log(_ message: String) {
        guard verbose else { return }
        fputs("[RemindersMCPServer] \(message)\n", stderr)
    }
}
