import Foundation
import EventKit
import SwiftMCP

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
