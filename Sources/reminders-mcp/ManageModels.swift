import Foundation
import EventKit

enum ManageAction: String, Decodable {
    case create
    case read
    case update
    case delete
    case complete
    case uncomplete
    case move
    case archive
}

struct ManageRequest: Decodable {
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

struct ManageCreatePayload: Decodable {
    let title: String
    let list: String?
    let notes: String?
    let dueDate: String?
    let priority: String?
}

struct ManageIdentifierPayload: Decodable {
    let uuid: String
}

struct ManageUpdatePayload: Decodable {
    let uuid: String
    let title: String?
    let notes: String?
    let dueDate: String?
    let priority: String?
    let isCompleted: Bool?
}

struct ManageMovePayload: Decodable {
    let uuid: String
    let targetList: String
}

struct ManageArchivePayload: Decodable {
    let uuid: String
    let archiveList: String?
    let createIfMissing: Bool?
    let source: String?
}

struct ManageResponse: Encodable {
    let reminder: EKReminder?
    let success: Bool
    let message: String?
    let parsed: ParsedMetadata?

    init(reminder: EKReminder? = nil, success: Bool = true, message: String? = nil, parsed: ParsedMetadata? = nil) {
        self.reminder = reminder
        self.success = success
        self.message = message
        self.parsed = parsed
    }
}
