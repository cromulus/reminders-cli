import EventKit
import Foundation
import CoreLocation
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
    public let recurrence: ParsedField?
    public let location: ParsedField?

    public init(list: ParsedField? = nil,
                priority: ParsedField? = nil,
                tags: [ParsedField]? = nil,
                dueDate: ParsedField? = nil,
                recurrence: ParsedField? = nil,
                location: ParsedField? = nil) {
        self.list = list
        self.priority = priority
        self.tags = tags
        self.dueDate = dueDate
        self.recurrence = recurrence
        self.location = location
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

private struct ListsRequestDTO: Decodable {
    let action: ListsRequest.Action
    let list: ListsListPayload?
    let create: ListsCreatePayload?
    let delete: ListsDeletePayload?
    let ensureArchive: ListsEnsureArchivePayload?
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

    public init(
        action: Action,
        list: ListsListPayload? = nil,
        create: ListsCreatePayload? = nil,
        delete: ListsDeletePayload? = nil,
        ensureArchive: ListsEnsureArchivePayload? = nil
    ) {
        self.action = action
        self.list = list
        self.create = create
        self.delete = delete
        self.ensureArchive = ensureArchive
    }

    private init(dto: ListsRequestDTO) {
        self.init(
            action: dto.action,
            list: dto.list,
            create: dto.create,
            delete: dto.delete,
            ensureArchive: dto.ensureArchive
        )
    }

    public init(from decoder: Decoder) throws {
        if let dto = try? ListsRequestDTO(from: decoder) {
            self.init(dto: dto)
            return
        }

        if let stringValue = try? decoder.singleValueContainer().decode(String.self),
           !stringValue.isEmpty
        {
            let data = Data(stringValue.utf8)
            let dto = try JSONDecoder().decode(ListsRequestDTO.self, from: data)
            self.init(dto: dto)
            return
        }

        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self),
           let requestKey = container.allKeys.first(where: { $0.stringValue == "request" })
        {
            let nested = try container.superDecoder(forKey: requestKey)
            let dto = try ListsRequestDTO(from: nested)
            self.init(dto: dto)
            return
        }

        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unable to decode ListsRequest payload"))
    }
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

public enum AnalyzeMode: String, Codable {
    case overview
    case lists
    case priority
    case dueWindows
    case recurrence
}

public struct AnalyzeRequest: Decodable {
    public let mode: AnalyzeMode?
    public let upcomingWindowDays: Int?

    public init(mode: AnalyzeMode? = nil, upcomingWindowDays: Int? = nil) {
        self.mode = mode
        self.upcomingWindowDays = upcomingWindowDays
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case upcomingWindowDays
    }

    public init(from decoder: Decoder) throws {
        // Normal keyed decoding
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            let mode = try container.decodeIfPresent(AnalyzeMode.self, forKey: .mode)
            let window = try container.decodeIfPresent(Int.self, forKey: .upcomingWindowDays)
            self.init(mode: mode, upcomingWindowDays: window)
            return
        }

        // Handle { "request": { ... } }
        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self),
           let requestKey = container.allKeys.first(where: { $0.stringValue == "request" })
        {
            let nested = try container.superDecoder(forKey: requestKey)
            self = try AnalyzeRequest(from: nested)
            return
        }

        // Handle stringified JSON payloads
        if let stringValue = try? decoder.singleValueContainer().decode(String.self),
           !stringValue.isEmpty,
           let data = stringValue.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(AnalyzeRequest.self, from: data)
        {
            self = decoded
            return
        }

        self.init()
    }
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

public struct AnalyzeSummary: Encodable {
    public let total: Int
    public let completed: Int
    public let incomplete: Int
    public let overdue: Int
    public let dueToday: Int
    public let dueWithinWindow: Int
    public let upcomingWindowDays: Int
}

public struct AnalyzeListBreakdown: Encodable {
    public let list: String
    public let total: Int
    public let completed: Int
    public let overdue: Int
    public let recurring: Int
}

public struct AnalyzePriorityBreakdown: Encodable {
    public let priority: String
    public let total: Int
    public let completed: Int
    public let overdue: Int
}

public struct AnalyzeDueWindow: Encodable {
    public let label: String
    public let count: Int
}

public struct AnalyzeRecurrenceStats: Encodable {
    public let recurring: Int
    public let nonRecurring: Int
    public let byFrequency: [String: Int]
}

public struct AnalyzeResponse: Encodable {
    public let mode: AnalyzeMode
    public let summary: AnalyzeSummary?
    public let lists: [AnalyzeListBreakdown]?
    public let priorities: [AnalyzePriorityBreakdown]?
    public let dueWindows: [AnalyzeDueWindow]?
    public let recurrence: AnalyzeRecurrenceStats?
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

    /// Unified single-reminder CRUD/complete/archive/move/archive tool with natural-language parsing.
    ///
    /// **When to use:** create/read/update/delete an individual reminder, complete/uncomplete, move between lists, or archive (with auto archive creation). Accepts natural-language titles such as `“Send report tomorrow 9am @Finance ^high”`.
    ///
    /// ### Supported actions
    /// | Action | Payload |
    /// |--------|---------|
    /// | `create` | `create { title, list?, notes?, dueDate?, priority? }` |
    /// | `read` | `read { uuid }` |
    /// | `update` | `update { uuid, title?, notes?, dueDate?, priority?, isCompleted? }` |
    /// | `delete` / `complete` / `uncomplete` | `{ uuid }` |
    /// | `move` | `move { uuid, targetList }` |
    /// | `archive` | `archive { uuid, archiveList?, createIfMissing?, source? }` |
    ///
    /// Recurrence:
    /// - Structured: `recurrence { "frequency": "weekly", "interval": 1, "daysOfWeek": ["monday"] }`
    /// - Natural shorthand: append `~weekly`, `~every 2 weeks`, `~monthly on 15`, `~daily for 10`
    ///
    /// **Limitations:** Apple’s EventKit does not let us set attachments or the `url` field, and only one structured location alarm is supported per reminder.
    ///
    /// ### Sample prompts
    /// - “Create ‘Prep slides tomorrow 10am @Work ^high ~weekly on Mondays’ and move it to ‘Projects’.”
    /// - “Archive reminder `UUID-123` into the Archive list (create if missing).”
    ///
    /// ### Sample JSON
    /// ```json
    /// {
    ///   "request": {
    ///     "action": "create",
    ///     "create": {
    ///       "title": "Book flights tomorrow 9am @Travel ^high",
    ///       "list": "Travel",
    ///       "notes": "Use miles for SFO→JFK",
    ///       "dueDate": "next friday 17:00",
    ///       "priority": "high",
    ///       "recurrence": {
    ///         "frequency": "weekly",
    ///         "daysOfWeek": ["monday"],
    ///         "end": { "type": "count", "value": "8" }
    ///       },
    ///       "location": {
    ///         "title": "HQ Office",
    ///         "latitude": 37.3317,
    ///         "longitude": -122.0301,
    ///         "radius": 75,
    ///         "proximity": "arrival"
    ///       }
    ///     }
    ///   }
    /// }
    /// ```
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
    /// **When to use:** run the same mutation over many reminders (complete all overdue items, move a batch to another list, archive multiple UUIDs). Supports dry runs so you can check results before committing.
    ///
    /// | Action | Notes |
    /// |--------|-------|
    /// | `update` | `fields` may include `title`, `notes`, `dueDate`, `priority`, `isCompleted` |
    /// | `complete`, `uncomplete`, `delete` | only `uuids` required |
    /// | `move` | include `fields.targetList` |
    /// | `archive` | include `fields.archiveList?`, `fields.createArchiveIfMissing?` |
    ///
    /// ### Sample prompt
    /// “Archive every reminder returned by my last search, dry-run first, then apply if no errors.”
    ///
    /// ### Sample JSON
    /// ```json
    /// {
    ///   "request": {
    ///     "action": "move",
    ///     "uuids": ["UUID-1", "UUID-2"],
    ///     "fields": {
    ///       "targetList": "Archive",
    ///       "createArchiveIfMissing": true
    ///     },
    ///     "dryRun": true
    ///   }
    /// }
    /// ```
    ///
    /// Dry-runs report what *would* change without mutating reminders.
    ///
    /// **Limitations:** bulk mode intentionally ignores attachments, subtasks, and structured location alarms.
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
    /// **Capabilities:** nested AND/OR/NOT logic via `logic`, fuzzy `query`, grouping (`groupBy`), multi-key sorting (`sort`), pagination, list filters, and natural dates (`today`, `tomorrow`, `friday+2`, `start of week`, etc.).
    ///
    /// ### Sample prompts
    /// - “Find high-priority Work reminders due this week, grouped by list, sorted by due date ascending.”
    /// - “Show all reminders tagged #delegated that are overdue or due today.”
    ///
    /// ### Sample JSON
    /// ```json
    /// {
    ///   "request": {
    ///     "logic": {
    ///       "all": [
    ///         { "clause": { "field": "priority", "op": "in", "value": ["high","medium"] } },
    ///         { "clause": { "field": "list", "op": "equals", "value": "Work" } },
    ///         { "clause": { "field": "dueDate", "op": "lessOrEqual", "value": "end of week" } }
    ///       ],
    ///       "not": {
    ///         "clause": { "field": "tag", "op": "includes", "value": "delegated" }
    ///       }
    ///     },
    ///     "groupBy": [{ "field": "list" }, { "field": "priority" }],
    ///     "sort": [
    ///       { "field": "dueDate", "direction": "asc" },
    ///       { "field": "priority", "direction": "desc" }
    ///     ],
    ///     "pagination": { "limit": 25 },
    ///     "includeCompleted": false
    ///   }
    /// }
    /// ```
    ///
    /// **Limitations:** parentheses inside the SQL-like `filter` string are not supported yet—use the structured `logic` tree for nested groups.
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
    /// **When to use:** discover valid list identifiers, create/delete lists, or guarantee an Archive list exists before bulk moves.
    ///
    /// | Action | Example payload |
    /// |--------|-----------------|
    /// | `list` | `{ "request": { "action": "list", "list": { "includeReadOnly": false } } }` |
    /// | `create` | `{ "request": { "action": "create", "create": { "name": "Projects", "source": "iCloud" } } }` |
    /// | `delete` | `{ "request": { "action": "delete", "delete": { "identifier": "Work" } } }` |
    /// | `ensureArchive` | `{ "request": { "action": "ensureArchive", "ensureArchive": { "name": "Archive", "createIfMissing": true } } }` |
    ///
    /// **Sample prompt:** “List all writable reminder lists and ensure there is an Archive list (create if needed).”
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

    /// Aggregate reminder analytics with multiple modes.
    ///
    /// **When to use:** you need a dashboard-style snapshot (overview), a per-list scoreboard, priority histogram, due-window buckets, or recurrence stats without iterating through individual reminders.
    ///
    /// Modes:
    /// - `overview` (default) – summary + list and priority breakdowns
    /// - `lists` – focus on list totals, overdue counts, and recurrence per list
    /// - `priority` – priority histogram with completion/overdue counts
    /// - `dueWindows` – buckets reminders into `overdue`, `today`, `next N days`, `later`, `unscheduled`
    /// - `recurrence` – recurring vs one-off distribution, grouped by frequency
    ///
    /// **Limitations:** analytics operate on the reminders currently available on this device (no historical trend data) and do not include raw reminder payloads.
    ///
    /// ### Sample prompts
    /// - “Summarize my reminders: how many overdue, due today, and the busiest lists?”
    /// - “Give me a priority histogram so I can see how many highs vs lows remain.”
    /// - “Show a table of lists sorted by how many overdue items they have.”
    ///
    /// ### Example request
    /// ```json
    /// {
    ///   "request": {
    ///     "mode": "dueWindows",
    ///     "upcomingWindowDays": 10
    ///   }
    /// }
    /// ```
    ///
    /// ⚠️ Requests must be JSON objects (not quoted strings). Pass `{ "request": { ... } }`
    /// just like the other tools (do **not** wrap the payload in a string literal).
    ///
    /// Set `upcomingWindowDays` (1-30) to control how “due soon” windows are calculated; defaults to 7 days.
    @MCPTool
    public func reminders_analyze(_ request: AnalyzeRequest? = nil) async throws -> AnalyzeResponse {
        let mode = request?.mode ?? .overview
        let windowDays = max(1, min(30, request?.upcomingWindowDays ?? 7))
        let calendars = reminders.getCalendars()
        let allReminders = try await fetchReminders(on: calendars, display: .all)

        switch mode {
        case .overview:
            return buildOverviewAnalysis(reminders: allReminders, windowDays: windowDays)
        case .lists:
            return buildListAnalysis(reminders: allReminders, windowDays: windowDays)
        case .priority:
            return buildPriorityAnalysis(reminders: allReminders, windowDays: windowDays)
        case .dueWindows:
            return buildDueWindowAnalysis(reminders: allReminders, windowDays: windowDays)
        case .recurrence:
            return buildRecurrenceAnalysis(reminders: allReminders, windowDays: windowDays)
        }
    }

    // MARK: - Documentation Resources

    /// Quick reference for the five consolidated tools (purpose, sample payloads, prompts).
    @MCPResource("docs://reminders/overview", name: "Reminders MCP Overview", mimeType: "text/markdown")
    func remindersOverviewResource() -> String {
        MCPDocs.toolOverview
    }

    /// SQL-like search/filter cheat sheet (operators, shortcuts, examples).
    @MCPResource("docs://reminders/filter-cheatsheet", name: "Reminders Filter Cheatsheet", mimeType: "text/markdown")
    func remindersFilterCheatsheetResource() -> String {
        MCPDocs.filterDetails
    }

    // MARK: - Manage Action Helpers

    private func handleManageCreate(_ payload: ManageCreatePayload) throws -> ManageResponse {
        let metadata = TitleParser.parse(payload.title)

        var parsedList: ParsedField?
        var parsedPriority: ParsedField?
        var parsedTags: [ParsedField]?
        var parsedDueDate: ParsedField?
        var parsedLocation: ParsedField?
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
        let recurrenceInstruction = try resolveRecurrenceInstruction(
            payload: payload.recurrence,
            metadataPattern: metadata.recurrencePattern,
            dueDateComponents: dueComponents
        )
        var parsedRecurrence: ParsedField?
        var needsSave = false

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

        switch recurrenceInstruction {
        case .set(let build):
            reminder.recurrenceRules = [build.rule]
            parsedRecurrence = build.parsedField
            needsSave = true
        case .remove:
            reminder.recurrenceRules = nil
            needsSave = true
        case .none:
            break
        }

        let locationResult = try applyLocationInstruction(payload.location, to: reminder)
        if locationResult.changed {
            parsedLocation = locationResult.parsedField
            needsSave = true
        }

        if needsSave {
            try reminders.updateReminder(reminder)
        }

        let parsedMetadata = ParsedMetadata(
            list: parsedList,
            priority: parsedPriority,
            tags: parsedTags,
            dueDate: parsedDueDate,
            recurrence: parsedRecurrence,
            location: parsedLocation
        )

        return ManageResponse(reminder: reminder, message: "Reminder created", parsed: parsedMetadata)
    }

    private func handleManageRead(uuid: String) throws -> ManageResponse {
        let reminder = try resolveReminder(uuid: uuid)
        return ManageResponse(reminder: reminder, message: "Reminder fetched")
    }

    private func handleManageUpdate(_ payload: ManageUpdatePayload) throws -> ManageResponse {
        let reminder = try resolveReminder(uuid: payload.uuid)

        var metadataRecurrencePattern: String?
        var parsedRecurrence: ParsedField?
        var parsedLocation: ParsedField?

        if let title = payload.title {
            let metadata = TitleParser.parse(title)
            reminder.title = metadata.cleanedTitle
            metadataRecurrencePattern = metadata.recurrencePattern

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

        if payload.recurrence != nil || metadataRecurrencePattern != nil {
            let recurrenceInstruction = try resolveRecurrenceInstruction(
                payload: payload.recurrence,
                metadataPattern: metadataRecurrencePattern,
                dueDateComponents: reminder.dueDateComponents
            )

            switch recurrenceInstruction {
            case .set(let build):
                reminder.recurrenceRules = [build.rule]
                parsedRecurrence = build.parsedField
            case .remove:
                reminder.recurrenceRules = nil
            case .none:
                break
            }
        }

        let locationResult = try applyLocationInstruction(payload.location, to: reminder)
        if locationResult.changed {
            parsedLocation = locationResult.parsedField
        }

        try reminders.updateReminder(reminder)
        let parsedMetadata: ParsedMetadata?
        if parsedRecurrence != nil || parsedLocation != nil {
            parsedMetadata = ParsedMetadata(recurrence: parsedRecurrence, location: parsedLocation)
        } else {
            parsedMetadata = nil
        }
        return ManageResponse(reminder: reminder, message: "Reminder updated", parsed: parsedMetadata)
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

    // MARK: - Recurrence Helpers

    private enum RecurrenceInstruction {
        case none
        case set(RecurrenceBuildResult)
        case remove
    }

    private struct RecurrenceBuildResult {
        let rule: EKRecurrenceRule
        let parsedField: ParsedField?
    }

    private enum RecurrenceEndDescriptor {
        case never
        case count(Int)
        case date(Date)
    }

    private struct RecurrenceSpec {
        let frequency: RecurrenceFrequency
        let interval: Int
        let daysOfWeek: [Weekday]?
        let dayOfMonth: Int?
        let end: RecurrenceEndDescriptor?
        let sourcePattern: String?

        func summary() -> String {
            var parts: [String] = []
            let intervalText: String
            switch frequency {
            case .daily:
                intervalText = interval == 1 ? "Every day" : "Every \(interval) days"
            case .weekly:
                intervalText = interval == 1 ? "Every week" : "Every \(interval) weeks"
            case .monthly:
                intervalText = interval == 1 ? "Every month" : "Every \(interval) months"
            case .yearly:
                intervalText = interval == 1 ? "Every year" : "Every \(interval) years"
            }
            parts.append(intervalText)

            if frequency == .weekly, let days = daysOfWeek, !days.isEmpty {
                let names = days.map { $0.displayName }
                parts.append("on " + names.joined(separator: ", "))
            }

            if frequency == .monthly, let day = dayOfMonth {
                parts.append("on day \(day)")
            }

            if let end = end {
                switch end {
                case .never:
                    break
                case .count(let count):
                    parts.append("for \(count) occurrence\(count == 1 ? "" : "s")")
                case .date(let date):
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .none
                    parts.append("until \(formatter.string(from: date))")
                }
            }

            return parts.joined(separator: ", ")
        }
    }

    private enum Weekday: Int, CaseIterable {
        case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

        init?(string: String) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch trimmed {
            case "sun", "sunday": self = .sunday
            case "mon", "monday": self = .monday
            case "tue", "tues", "tuesday": self = .tuesday
            case "wed", "wednesday": self = .wednesday
            case "thu", "thur", "thurs", "thursday": self = .thursday
            case "fri", "friday": self = .friday
            case "sat", "saturday": self = .saturday
            default: return nil
            }
        }

        var displayName: String {
            switch self {
            case .sunday: return "Sunday"
            case .monday: return "Monday"
            case .tuesday: return "Tuesday"
            case .wednesday: return "Wednesday"
            case .thursday: return "Thursday"
            case .friday: return "Friday"
            case .saturday: return "Saturday"
            }
        }

        var recurrenceDay: EKRecurrenceDayOfWeek {
            EKRecurrenceDayOfWeek(EKWeekday(rawValue: rawValue)!)
        }
    }

    private func resolveRecurrenceInstruction(
        payload: RecurrencePayload?,
        metadataPattern: String?,
        dueDateComponents: DateComponents?
    ) throws -> RecurrenceInstruction {
        if payload == nil && metadataPattern == nil {
            return .none
        }

        if payload?.remove == true {
            return .remove
        }

        let normalizedMetadata = metadataPattern?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let pattern = normalizedMetadata, Self.recurrenceRemovalKeywords.contains(pattern.lowercased()) {
            return .remove
        }

        if let payloadPattern = payload?.pattern?.lowercased(), Self.recurrenceRemovalKeywords.contains(payloadPattern.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return .remove
        }

        guard let specResult = try recurrenceSpec(from: payload, metadataPattern: metadataPattern, dueDateComponents: dueDateComponents) else {
            return .none
        }

        let rule = try buildRecurrenceRule(from: specResult.spec)
        let summary = specResult.spec.summary()
        let original = specResult.original ?? specResult.spec.sourcePattern
        let parsedField = original.map { ParsedField(original: "~\($0)", parsed: summary) }
        return .set(RecurrenceBuildResult(rule: rule, parsedField: parsedField))
    }

    private func recurrenceSpec(
        from payload: RecurrencePayload?,
        metadataPattern: String?,
        dueDateComponents: DateComponents?
    ) throws -> (spec: RecurrenceSpec, original: String?)? {
        if let payload = payload {
            if let spec = try spec(from: payload, dueDateComponents: dueDateComponents) {
                return (spec, payload.pattern)
            }
        }

        guard let pattern = (payload?.pattern ?? metadataPattern)?.trimmingCharacters(in: .whitespacesAndNewlines), !pattern.isEmpty else {
            return nil
        }

        guard let spec = try spec(fromPattern: pattern, dueDateComponents: dueDateComponents) else {
            return nil
        }
        return (spec, pattern)
    }

    private func spec(from payload: RecurrencePayload, dueDateComponents: DateComponents?) throws -> RecurrenceSpec? {
        let hasStructuredFields = payload.frequency != nil || payload.interval != nil || payload.daysOfWeek != nil || payload.dayOfMonth != nil || payload.end != nil
        if !hasStructuredFields, payload.pattern == nil {
            return nil
        }

        guard let frequency = payload.frequency else {
            if let pattern = payload.pattern {
                return try spec(fromPattern: pattern, dueDateComponents: dueDateComponents)
            }
            return nil
        }

        let interval = max(payload.interval ?? 1, 1)
        var days: [Weekday]? = nil
        if let dayStrings = payload.daysOfWeek {
            days = try mapWeekdays(dayStrings)
        }

        let dayOfMonth = payload.dayOfMonth
        if let day = dayOfMonth, !(1...31).contains(day) {
            throw RemindersMCPError.invalidArguments("dayOfMonth must be between 1 and 31")
        }

        let endDescriptor = try parseEndDescriptor(payload.end)

        return try finalizeSpec(
            frequency: frequency,
            interval: interval,
            daysOfWeek: days,
            dayOfMonth: dayOfMonth,
            end: endDescriptor,
            sourcePattern: payload.pattern,
            dueDateComponents: dueDateComponents
        )
    }

    private func spec(fromPattern pattern: String, dueDateComponents: DateComponents?) throws -> RecurrenceSpec? {
        let normalized = pattern.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        if Self.recurrenceRemovalKeywords.contains(normalized) {
            return nil
        }

        var interval = 1
        var frequency: RecurrenceFrequency?
        var days: [Weekday]? = nil
        var dayOfMonth: Int?
        var endDescriptor: RecurrenceEndDescriptor?

        if normalized.contains("biweekly") || normalized.contains("fortnight") {
            frequency = .weekly
            interval = 2
        }

        if normalized.contains("quarter") {
            frequency = .monthly
            interval = 3
        }

        if frequency == nil {
            if normalized.contains("daily") {
                frequency = .daily
            } else if normalized.contains("weekly") {
                frequency = .weekly
            } else if normalized.contains("monthly") {
                frequency = .monthly
            } else if normalized.contains("yearly") || normalized.contains("annually") {
                frequency = .yearly
            }
        }

        if let everyMatch = Self.everyRegex.firstMatch(in: normalized, options: [], range: NSRange(location: 0, length: normalized.count)),
           let intervalRange = Range(everyMatch.range(at: 1), in: normalized),
           let unitRange = Range(everyMatch.range(at: 2), in: normalized) {
            interval = max(Int(normalized[intervalRange]) ?? 1, 1)
            let unit = normalized[unitRange]
            switch unit {
            case "day", "days": frequency = .daily
            case "week", "weeks": frequency = .weekly
            case "month", "months": frequency = .monthly
            case "year", "years": frequency = .yearly
            default: break
            }
        }

        if normalized.contains("every other week") {
            frequency = .weekly
            interval = 2
        }

        var working = normalized
        if let untilRange = working.range(of: "until ") {
            let endString = working[untilRange.upperBound...].trimmingCharacters(in: .whitespaces)
            working = String(working[..<untilRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            if let date = parseEndDateString(endString) {
                endDescriptor = .date(date)
            }
        }

        if let forRange = working.range(of: "for ") {
            let countString = working[forRange.upperBound...].trimmingCharacters(in: .whitespaces)
            working = String(working[..<forRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            if let count = Int(countString.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
                endDescriptor = .count(max(count, 1))
            }
        }

        if frequency == .weekly, let onRange = working.range(of: "on ") {
            let tail = working[onRange.upperBound...]
            let tokens = tail.components(separatedBy: CharacterSet(charactersIn: ",;"))
            let trimmedTokens = tokens.flatMap { token -> [String] in
                token
                    .split(separator: " ")
                    .map { String($0) }
            }
            let weekdays = try mapWeekdays(trimmedTokens)
            if !weekdays.isEmpty {
                days = weekdays
            }
        }

        if frequency == .monthly {
            if let match = Self.dayOfMonthRegex.firstMatch(in: working, options: [], range: NSRange(location: 0, length: working.count)),
               let dayRange = Range(match.range(at: 1), in: working) {
                let value = working[dayRange]
                if let day = Int(value) {
                    dayOfMonth = day
                }
            }
        }

        guard let freq = frequency else { return nil }

        return try finalizeSpec(
            frequency: freq,
            interval: interval,
            daysOfWeek: days,
            dayOfMonth: dayOfMonth,
            end: endDescriptor,
            sourcePattern: pattern,
            dueDateComponents: dueDateComponents
        )
    }

    private func finalizeSpec(
        frequency: RecurrenceFrequency,
        interval: Int,
        daysOfWeek: [Weekday]?,
        dayOfMonth: Int?,
        end: RecurrenceEndDescriptor?,
        sourcePattern: String?,
        dueDateComponents: DateComponents?
    ) throws -> RecurrenceSpec {
        var resolvedDays = daysOfWeek
        var resolvedDayOfMonth = dayOfMonth

        if frequency == .weekly, resolvedDays == nil {
            guard let fallbackDay = defaultWeekday(from: dueDateComponents) else {
                throw RemindersMCPError.invalidArguments("Provide dueDate (or specify daysOfWeek) when setting a weekly recurrence")
            }
            resolvedDays = [fallbackDay]
        }

        if frequency == .monthly, resolvedDayOfMonth == nil {
            guard let fallback = dueDateComponents?.day else {
                throw RemindersMCPError.invalidArguments("Provide dueDate (or dayOfMonth) when setting a monthly recurrence")
            }
            resolvedDayOfMonth = fallback
        }

        return RecurrenceSpec(
            frequency: frequency,
            interval: interval,
            daysOfWeek: resolvedDays,
            dayOfMonth: resolvedDayOfMonth,
            end: end,
            sourcePattern: sourcePattern
        )
    }

    private func buildRecurrenceRule(from spec: RecurrenceSpec) throws -> EKRecurrenceRule {
        let frequency = spec.frequency.ekFrequency
        let days = spec.daysOfWeek?.map { $0.recurrenceDay }
        let daysOfMonth = spec.dayOfMonth.map { [NSNumber(value: $0)] }
        let end = recurrenceEnd(from: spec.end)

        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: spec.interval,
            daysOfTheWeek: days,
            daysOfTheMonth: daysOfMonth,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: end
        )
    }

    private func recurrenceEnd(from descriptor: RecurrenceEndDescriptor?) -> EKRecurrenceEnd? {
        guard let descriptor else { return nil }
        switch descriptor {
        case .never:
            return nil
        case .count(let count):
            return EKRecurrenceEnd(occurrenceCount: count)
        case .date(let date):
            return EKRecurrenceEnd(end: date)
        }
    }

    private func parseEndDescriptor(_ payload: RecurrenceEndPayload?) throws -> RecurrenceEndDescriptor? {
        guard let payload = payload else { return nil }
        switch payload.type {
        case .none:
            return nil
        case .some(.never):
            return .never
        case .some(.count):
            guard let value = payload.value, let count = Int(value) else {
                throw RemindersMCPError.invalidArguments("Provide numeric value for end.count")
            }
            return .count(max(count, 1))
        case .some(.date):
            guard let value = payload.value, let date = parseEndDateString(value) else {
                throw RemindersMCPError.invalidArguments("Unable to parse end date: \(payload.value ?? "")")
            }
            return .date(date)
        }
    }

    private func mapWeekdays(_ values: [String]) throws -> [Weekday] {
        var weekdays: [Weekday] = []
        for value in values {
            if let day = Weekday(string: value) {
                weekdays.append(day)
            } else {
                throw RemindersMCPError.invalidArguments("Unknown weekday: \(value)")
            }
        }
        return weekdays
    }

    private func defaultWeekday(from components: DateComponents?) -> Weekday? {
        guard let weekday = components?.weekday else { return nil }
        return Weekday(rawValue: weekday)
    }

    private func parseEndDateString(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: trimmed) {
            return date
        }

        if let components = DateComponents(argument: trimmed) {
            return Calendar.current.date(from: components)
        }

        return nil
    }

    // MARK: - Location Helpers

    private func applyLocationInstruction(_ payload: LocationAlarmPayload?, to reminder: EKReminder) throws -> (changed: Bool, parsedField: ParsedField?) {
        guard let payload = payload else {
            return (false, nil)
        }

        let currentAlarms = reminder.alarms ?? []

        if payload.remove == true {
            let filtered = currentAlarms.filter { $0.structuredLocation == nil }
            if filtered.count == currentAlarms.count {
                return (false, nil)
            }
            reminder.alarms = filtered.isEmpty ? nil : filtered
            return (true, ParsedField(original: "~location remove", parsed: "Location alarm removed"))
        }

        let structuredLocation = EKStructuredLocation(title: payload.title)
        structuredLocation.geoLocation = CLLocation(latitude: payload.latitude, longitude: payload.longitude)
        if let radius = payload.radius, radius > 0 {
            structuredLocation.radius = radius
        }

        var filteredAlarms = currentAlarms.filter { $0.structuredLocation == nil }
        let alarm = EKAlarm()
        alarm.structuredLocation = structuredLocation
        alarm.proximity = mapProximity(payload.proximity)
        filteredAlarms.append(alarm)
        reminder.alarms = filteredAlarms

        if let note = payload.note, !note.isEmpty {
            if let current = reminder.notes, !current.isEmpty {
                reminder.notes = "\(current)\n\n\(note)"
            } else {
                reminder.notes = note
            }
        }

        let coords = String(format: "%.4f, %.4f", payload.latitude, payload.longitude)
        let parsed = ParsedField(original: "@location", parsed: "\(payload.title) (\(coords))")
        return (true, parsed)
    }

    private func mapProximity(_ value: AlarmProximity?) -> EKAlarmProximity {
        switch value {
        case .some(.arrival), .none:
            return .enter
        case .some(.departure):
            return .leave
        case .some(.any):
            return .none
        }
    }

    private static let recurrenceRemovalKeywords: Set<String> = ["none", "remove", "clear", "never"]
    private static let everyRegex = try! NSRegularExpression(pattern: #"every\s+(\d+)\s+(day|days|week|weeks|month|months|year|years)"#, options: [])
    private static let dayOfMonthRegex = try! NSRegularExpression(pattern: #"on\s+(?:the\s+)?(\d{1,2})"#, options: [])

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

    // MARK: - Analyze Helpers

    private func buildOverviewAnalysis(reminders: [EKReminder], windowDays: Int) -> AnalyzeResponse {
        AnalyzeResponse(
            mode: .overview,
            summary: summarizeReminders(reminders, windowDays: windowDays),
            lists: buildListBreakdown(reminders),
            priorities: buildPriorityBreakdown(reminders),
            dueWindows: nil,
            recurrence: nil
        )
    }

    private func buildListAnalysis(reminders: [EKReminder], windowDays: Int) -> AnalyzeResponse {
        AnalyzeResponse(
            mode: .lists,
            summary: summarizeReminders(reminders, windowDays: windowDays),
            lists: buildListBreakdown(reminders),
            priorities: nil,
            dueWindows: nil,
            recurrence: nil
        )
    }

    private func buildPriorityAnalysis(reminders: [EKReminder], windowDays: Int) -> AnalyzeResponse {
        AnalyzeResponse(
            mode: .priority,
            summary: summarizeReminders(reminders, windowDays: windowDays),
            lists: nil,
            priorities: buildPriorityBreakdown(reminders),
            dueWindows: nil,
            recurrence: nil
        )
    }

    private func buildDueWindowAnalysis(reminders: [EKReminder], windowDays: Int) -> AnalyzeResponse {
        AnalyzeResponse(
            mode: .dueWindows,
            summary: summarizeReminders(reminders, windowDays: windowDays),
            lists: nil,
            priorities: nil,
            dueWindows: buildDueWindowBreakdown(reminders, windowDays: windowDays),
            recurrence: nil
        )
    }

    private func buildRecurrenceAnalysis(reminders: [EKReminder], windowDays: Int) -> AnalyzeResponse {
        AnalyzeResponse(
            mode: .recurrence,
            summary: summarizeReminders(reminders, windowDays: windowDays),
            lists: nil,
            priorities: nil,
            dueWindows: nil,
            recurrence: buildRecurrenceStats(reminders)
        )
    }

    private func summarizeReminders(_ reminders: [EKReminder], windowDays: Int) -> AnalyzeSummary {
        let clamp = max(1, min(30, windowDays))
        let startOfDay = calendar.startOfDay(for: Date())
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let windowEnd = calendar.date(byAdding: .day, value: clamp, to: startOfDay)!

        var completed = 0
        var overdue = 0
        var dueToday = 0
        var dueWithin = 0

        for reminder in reminders {
            if reminder.isCompleted {
                completed += 1
            }

            guard let dueDate = reminder.dueDateComponents?.date else { continue }

            if dueDate < startOfDay && !reminder.isCompleted {
                overdue += 1
            }

            if dueDate >= startOfDay && dueDate < todayEnd && !reminder.isCompleted {
                dueToday += 1
            }

            if dueDate >= startOfDay && dueDate < windowEnd && !reminder.isCompleted {
                dueWithin += 1
            }
        }

        return AnalyzeSummary(
            total: reminders.count,
            completed: completed,
            incomplete: reminders.count - completed,
            overdue: overdue,
            dueToday: dueToday,
            dueWithinWindow: dueWithin,
            upcomingWindowDays: clamp
        )
    }

    private func buildListBreakdown(_ reminders: [EKReminder]) -> [AnalyzeListBreakdown] {
        var temp: [String: (total: Int, completed: Int, overdue: Int, recurring: Int)] = [:]
        let now = Date()

        for reminder in reminders {
            var bucket = temp[reminder.calendar.title] ?? (0, 0, 0, 0)
            bucket.total += 1
            if reminder.isCompleted {
                bucket.completed += 1
            }
            if isReminderOverdue(reminder, referenceDate: now) {
                bucket.overdue += 1
            }
            if isRecurring(reminder) {
                bucket.recurring += 1
            }
            temp[reminder.calendar.title] = bucket
        }

        return temp
            .map { key, value in
                AnalyzeListBreakdown(
                    list: key,
                    total: value.total,
                    completed: value.completed,
                    overdue: value.overdue,
                    recurring: value.recurring
                )
            }
            .sorted { $0.total > $1.total }
    }

    private func buildPriorityBreakdown(_ reminders: [EKReminder]) -> [AnalyzePriorityBreakdown] {
        var temp: [String: (total: Int, completed: Int, overdue: Int)] = [:]
        let now = Date()

        for reminder in reminders {
            let bucketName = priorityBucket(for: reminder)
            var bucket = temp[bucketName] ?? (0, 0, 0)
            bucket.total += 1
            if reminder.isCompleted {
                bucket.completed += 1
            }
            if isReminderOverdue(reminder, referenceDate: now) {
                bucket.overdue += 1
            }
            temp[bucketName] = bucket
        }

        return temp
            .map { key, value in
                AnalyzePriorityBreakdown(
                    priority: key,
                    total: value.total,
                    completed: value.completed,
                    overdue: value.overdue
                )
            }
            .sorted { $0.priority < $1.priority }
    }

    private func buildDueWindowBreakdown(_ reminders: [EKReminder], windowDays: Int) -> [AnalyzeDueWindow] {
        let clamp = max(1, min(30, windowDays))
        let startOfDay = calendar.startOfDay(for: Date())
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let windowEnd = calendar.date(byAdding: .day, value: clamp, to: startOfDay)!

        var counts: [String: Int] = [
            "overdue": 0,
            "today": 0,
            "next": 0,
            "later": 0,
            "unscheduled": 0
        ]

        for reminder in reminders where !reminder.isCompleted {
            guard let dueDate = reminder.dueDateComponents?.date else {
                counts["unscheduled", default: 0] += 1
                continue
            }

            if dueDate < startOfDay {
                counts["overdue", default: 0] += 1
            } else if dueDate < todayEnd {
                counts["today", default: 0] += 1
            } else if dueDate < windowEnd {
                counts["next", default: 0] += 1
            } else {
                counts["later", default: 0] += 1
            }
        }

        let upcomingLabel = clamp == 1 ? "Next day" : "Next \(clamp) days"

        return [
            AnalyzeDueWindow(label: "Overdue", count: counts["overdue", default: 0]),
            AnalyzeDueWindow(label: "Today", count: counts["today", default: 0]),
            AnalyzeDueWindow(label: upcomingLabel, count: counts["next", default: 0]),
            AnalyzeDueWindow(label: "Later", count: counts["later", default: 0]),
            AnalyzeDueWindow(label: "Unscheduled", count: counts["unscheduled", default: 0])
        ]
    }

    private func buildRecurrenceStats(_ reminders: [EKReminder]) -> AnalyzeRecurrenceStats {
        var recurring = 0
        var frequencyCounts: [String: Int] = [:]

        for reminder in reminders {
            guard let frequency = reminder.recurrenceRules?.first?.frequency else { continue }
            recurring += 1
            let key = frequencyDisplayName(frequency)
            frequencyCounts[key, default: 0] += 1
        }

        return AnalyzeRecurrenceStats(
            recurring: recurring,
            nonRecurring: reminders.count - recurring,
            byFrequency: frequencyCounts
        )
    }

    private func isReminderOverdue(_ reminder: EKReminder, referenceDate: Date) -> Bool {
        guard !reminder.isCompleted, let dueDate = reminder.dueDateComponents?.date else {
            return false
        }
        return dueDate < referenceDate
    }

    private func isRecurring(_ reminder: EKReminder) -> Bool {
        !(reminder.recurrenceRules?.isEmpty ?? true)
    }

    private func frequencyDisplayName(_ frequency: EKRecurrenceFrequency) -> String {
        switch frequency {
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        case .yearly: return "yearly"
        @unknown default: return "custom"
        }
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

private extension RecurrenceFrequency {
    var ekFrequency: EKRecurrenceFrequency {
        switch self {
        case .daily: return .daily
        case .weekly: return .weekly
        case .monthly: return .monthly
        case .yearly: return .yearly
        }
    }
}
