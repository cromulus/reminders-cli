import Foundation

enum BulkAction: String, Decodable {
    case update
    case complete
    case uncomplete
    case move
    case archive
    case delete
}

struct BulkFieldChanges: Decodable {
    let title: String?
    let notes: String?
    let dueDate: String?
    let priority: String?
    let isCompleted: Bool?
    let targetList: String?
    let archiveList: String?
    let createArchiveIfMissing: Bool?
}

struct BulkRequest: Decodable {
    let action: BulkAction
    let uuids: [String]
    let fields: BulkFieldChanges?
    let dryRun: Bool?
}

struct BulkItemResult: Encodable {
    let uuid: String
    let success: Bool
    let message: String?
    let changes: [ChangeRecord]
}
