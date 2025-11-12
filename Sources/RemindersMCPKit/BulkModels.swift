import Foundation

public enum BulkAction: String, Decodable {
    case update
    case complete
    case uncomplete
    case move
    case archive
    case delete
}

public struct BulkFieldChanges: Decodable {
    public let title: String?
    public let notes: String?
    public let dueDate: String?
    public let priority: String?
    public let isCompleted: Bool?
    public let targetList: String?
    public let archiveList: String?
    public let createArchiveIfMissing: Bool?
}

public struct BulkRequest: Decodable {
    public let action: BulkAction
    public let uuids: [String]
    public let fields: BulkFieldChanges?
    public let dryRun: Bool?
}

public struct BulkItemResult: Encodable {
    public let uuid: String
    public let success: Bool
    public let message: String?
    public let changes: [ChangeRecord]
}
