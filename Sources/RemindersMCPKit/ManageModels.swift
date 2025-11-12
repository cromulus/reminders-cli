import Foundation
import EventKit

public enum ManageAction: String, Decodable {
    case create
    case read
    case update
    case delete
    case complete
    case uncomplete
    case move
    case archive
}

public struct ManageRequest: Decodable {
    public let action: ManageAction
    public let create: ManageCreatePayload?
    public let read: ManageIdentifierPayload?
    public let update: ManageUpdatePayload?
    public let delete: ManageIdentifierPayload?
    public let complete: ManageIdentifierPayload?
    public let uncomplete: ManageIdentifierPayload?
    public let move: ManageMovePayload?
    public let archive: ManageArchivePayload?
}

public struct ManageCreatePayload: Decodable {
    public let title: String
    public let list: String?
    public let notes: String?
    public let dueDate: String?
    public let priority: String?
}

public struct ManageIdentifierPayload: Decodable {
    public let uuid: String
}

public struct ManageUpdatePayload: Decodable {
    public let uuid: String
    public let title: String?
    public let notes: String?
    public let dueDate: String?
    public let priority: String?
    public let isCompleted: Bool?
}

public struct ManageMovePayload: Decodable {
    public let uuid: String
    public let targetList: String
}

public struct ManageArchivePayload: Decodable {
    public let uuid: String
    public let archiveList: String?
    public let createIfMissing: Bool?
    public let source: String?
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
