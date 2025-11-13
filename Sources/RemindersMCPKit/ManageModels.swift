import Foundation
import EventKit
import SwiftMCP

public enum RecurrenceFrequency: String, Decodable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly
}

public enum RecurrenceEndType: String, Decodable, Sendable {
    case never
    case count
    case date
}

@Schema
public struct RecurrenceEndPayload: Decodable, Sendable {
    public let type: RecurrenceEndType?
    public let value: String?

    public init(type: RecurrenceEndType? = nil, value: String? = nil) {
        self.type = type
        self.value = value
    }
}

@Schema
public struct RecurrencePayload: Decodable, Sendable {
    public let frequency: RecurrenceFrequency?
    public let interval: Int?
    public let daysOfWeek: [String]?
    public let dayOfMonth: Int?
    public let end: RecurrenceEndPayload?
    public let pattern: String?
    public let remove: Bool?

    public init(
        frequency: RecurrenceFrequency? = nil,
        interval: Int? = nil,
        daysOfWeek: [String]? = nil,
        dayOfMonth: Int? = nil,
        end: RecurrenceEndPayload? = nil,
        pattern: String? = nil,
        remove: Bool? = nil
    ) {
        self.frequency = frequency
        self.interval = interval
        self.daysOfWeek = daysOfWeek
        self.dayOfMonth = dayOfMonth
        self.end = end
        self.pattern = pattern
        self.remove = remove
    }

    private enum CodingKeys: String, CodingKey {
        case frequency
        case interval
        case daysOfWeek
        case dayOfMonth
        case end
        case pattern
        case remove
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            let frequency = try container.decodeIfPresent(RecurrenceFrequency.self, forKey: .frequency)
            let interval = try container.decodeIfPresent(Int.self, forKey: .interval)
            let daysOfWeek = try container.decodeIfPresent([String].self, forKey: .daysOfWeek)
            let dayOfMonth = try container.decodeIfPresent(Int.self, forKey: .dayOfMonth)
            let end = try container.decodeIfPresent(RecurrenceEndPayload.self, forKey: .end)
            let pattern = try container.decodeIfPresent(String.self, forKey: .pattern)
            let remove = try container.decodeIfPresent(Bool.self, forKey: .remove)
            self.init(
                frequency: frequency,
                interval: interval,
                daysOfWeek: daysOfWeek,
                dayOfMonth: dayOfMonth,
                end: end,
                pattern: pattern,
                remove: remove
            )
            return
        }

        let singleValue = try decoder.singleValueContainer()
        let patternString = try singleValue.decode(String.self)
        self.init(pattern: patternString)
    }
}

public enum AlarmProximity: String, Decodable, Sendable {
    case arrival
    case departure
    case any
}

@Schema
public struct LocationAlarmPayload: Decodable, Sendable {
    /// Human-friendly label shown in Reminders.app.
    public let title: String
    /// Latitude in decimal degrees.
    public let latitude: Double
    /// Longitude in decimal degrees.
    public let longitude: Double
    /// Optional geofence radius in meters.
    public let radius: Double?
    /// Trigger when arriving, departing, or either.
    public let proximity: AlarmProximity?
    /// Optional note to append when parsing titles.
    public let note: String?
    /// Set to `true` to remove any structured-location alarms.
    public let remove: Bool?

    public init(
        title: String,
        latitude: Double,
        longitude: Double,
        radius: Double? = nil,
        proximity: AlarmProximity? = nil,
        note: String? = nil,
        remove: Bool? = nil
    ) {
        self.title = title
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.proximity = proximity
        self.note = note
        self.remove = remove
    }
}

public enum ManageAction: String, Decodable, Sendable {
    case create
    case read
    case update
    case delete
    case complete
    case uncomplete
    case move
    case archive
}

/// Entry point for single reminder operations. Select an `action` and include the corresponding payload.
@Schema
public struct ManageRequest: Decodable, Sendable {
    /// Operation to perform.
    public let action: ManageAction
    /// Payload for `create` action.
    public let create: ManageCreatePayload?
    /// Payload for `read` action.
    public let read: ManageIdentifierPayload?
    /// Payload for `update` action.
    public let update: ManageUpdatePayload?
    /// Payload for `delete` action.
    public let delete: ManageIdentifierPayload?
    /// Payload for `complete` action.
    public let complete: ManageIdentifierPayload?
    /// Payload for `uncomplete` action.
    public let uncomplete: ManageIdentifierPayload?
    /// Payload for `move` action.
    public let move: ManageMovePayload?
    /// Payload for `archive` action.
    public let archive: ManageArchivePayload?

    public init(action: ManageAction,
                create: ManageCreatePayload? = nil,
                read: ManageIdentifierPayload? = nil,
                update: ManageUpdatePayload? = nil,
                delete: ManageIdentifierPayload? = nil,
                complete: ManageIdentifierPayload? = nil,
                uncomplete: ManageIdentifierPayload? = nil,
                move: ManageMovePayload? = nil,
                archive: ManageArchivePayload? = nil) {
        self.action = action
        self.create = create
        self.read = read
        self.update = update
        self.delete = delete
        self.complete = complete
        self.uncomplete = uncomplete
        self.move = move
        self.archive = archive
    }

    private init(dto: ManageRequestDTO) {
        self.init(
            action: dto.action,
            create: dto.create,
            read: dto.read,
            update: dto.update,
            delete: dto.delete,
            complete: dto.complete,
            uncomplete: dto.uncomplete,
            move: dto.move,
            archive: dto.archive
        )
    }

    public init(from decoder: Decoder) throws {
        if let dto = try? ManageRequestDTO(from: decoder) {
            self.init(dto: dto)
            return
        }

        if let stringValue = try? decoder.singleValueContainer().decode(String.self) {
            let data = Data(stringValue.utf8)
            let dto = try JSONDecoder().decode(ManageRequestDTO.self, from: data)
            self.init(dto: dto)
            return
        }

        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self),
           let requestKey = container.allKeys.first(where: { $0.stringValue == "request" }) {
            let nested = try container.superDecoder(forKey: requestKey)
            let dto = try ManageRequestDTO(from: nested)
            self.init(dto: dto)
            return
        }

        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unable to decode ManageRequest"))
    }
}

/// Fields accepted when creating a reminder.
@Schema
public struct ManageCreatePayload: Decodable, Sendable {
    /// Display title for the reminder.
    public let title: String
    /// Optional list name or identifier.
    public let list: String?
    /// Optional notes/body text.
    public let notes: String?
    /// Due date string (ISO8601 or natural language like `tomorrow 5pm`).
    public let dueDate: String?
    /// Priority bucket (`high|medium|low|none` or numeric `0-9`).
    public let priority: String?
    /// Recurrence descriptor (object or shorthand string). Use `{ "frequency": "weekly", "interval": 1 }` or `"weekly"`.
    public let recurrence: RecurrencePayload?
    /// Location-based alarm descriptor.
    public let location: LocationAlarmPayload?
}

/// Wrapper for simple UUID-only requests.
@Schema
public struct ManageIdentifierPayload: Decodable, Sendable {
    /// Reminder UUID (see `reminders_search` output).
    public let uuid: String
}

/// Patch-style updates; omit fields you do not want to change.
@Schema
public struct ManageUpdatePayload: Decodable, Sendable {
    public let uuid: String
    public let title: String?
    public let notes: String?
    public let dueDate: String?
    public let priority: String?
    public let isCompleted: Bool?
    /// Recurrence descriptor. Set `{ "remove": true }` to clear recurrence.
    public let recurrence: RecurrencePayload?
    /// Location alarm descriptor. Set `{ "remove": true }` to clear.
    public let location: LocationAlarmPayload?
}

/// Move an existing reminder to a different list.
@Schema
public struct ManageMovePayload: Decodable, Sendable {
    public let uuid: String
    public let targetList: String
}

/// Archive configuration when moving a reminder to an archive list.
@Schema
public struct ManageArchivePayload: Decodable, Sendable {
    public let uuid: String
    public let archiveList: String?
    public let createIfMissing: Bool?
    public let source: String?
}

private struct ManageRequestDTO: Decodable {
    let action: ManageAction
    let create: ManageCreatePayload?
    let read: ManageIdentifierPayload?
    let update: ManageUpdatePayload?
    let delete: ManageIdentifierPayload?
    let complete: ManageIdentifierPayload?
    let uncomplete: ManageIdentifierPayload?
    let move: ManageMovePayload?
    let archive: ManageArchivePayload?
}

public struct ManageResponse: Encodable {
    public let reminder: EKReminder?
    public let success: Bool
    public let message: String?
    public let parsed: ParsedMetadata?

    init(reminder: EKReminder? = nil, success: Bool = true, message: String? = nil, parsed: ParsedMetadata? = nil) {
        self.reminder = reminder
        self.success = success
        self.message = message
        self.parsed = parsed
    }
}
