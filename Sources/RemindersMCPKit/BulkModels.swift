import Foundation
import SwiftMCP

public enum BulkAction: String, Decodable, Sendable {
    case update
    case complete
    case uncomplete
    case move
    case archive
    case delete
}

/// Optional field overrides applied to each reminder in a bulk operation.
@Schema
public struct BulkFieldChanges: Decodable, Sendable {
    /// Replace the reminder title.
    public let title: String?
    /// Replace notes/body text.
    public let notes: String?
    /// Set due date (ISO8601 or natural language).
    public let dueDate: String?
    /// Update priority bucket.
    public let priority: String?
    /// Toggle completion.
    public let isCompleted: Bool?
    /// Target list for `move` action.
    public let targetList: String?
    /// Destination archive list for `archive` action.
    public let archiveList: String?
    /// Create archive list when missing.
    public let createArchiveIfMissing: Bool?
}

/// Request payload for high-volume reminder operations.
@Schema
public struct BulkRequest: Decodable, Sendable {
    /// Operation applied to every UUID.
    public let action: BulkAction
    /// Reminder identifiers to mutate.
    public let uuids: [String]
    /// Optional field overrides depending on action.
    public let fields: BulkFieldChanges?
    /// When true, report results without persisting changes.
    public let dryRun: Bool?

    public init(action: BulkAction, uuids: [String], fields: BulkFieldChanges? = nil, dryRun: Bool? = nil) {
        self.action = action
        self.uuids = uuids
        self.fields = fields
        self.dryRun = dryRun
    }

    private init(dto: BulkRequestDTO) {
        self.init(action: dto.action, uuids: dto.uuids, fields: dto.fields, dryRun: dto.dryRun)
    }

    public init(from decoder: Decoder) throws {
        if let dto = try? BulkRequestDTO(from: decoder) {
            self.init(dto: dto)
            return
        }

        if let stringValue = try? decoder.singleValueContainer().decode(String.self) {
            let data = Data(stringValue.utf8)
            let dto = try JSONDecoder().decode(BulkRequestDTO.self, from: data)
            self.init(dto: dto)
            return
        }

        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self),
           let requestKey = container.allKeys.first(where: { $0.stringValue == "request" }) {
            let nested = try container.superDecoder(forKey: requestKey)
            let dto = try BulkRequestDTO(from: nested)
            self.init(dto: dto)
            return
        }

        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unable to decode BulkRequest"))
    }
}

private struct BulkRequestDTO: Decodable {
    let action: BulkAction
    let uuids: [String]
    let fields: BulkFieldChanges?
    let dryRun: Bool?
}

public struct BulkItemResult: Encodable {
    public let uuid: String
    public let success: Bool
    public let message: String?
    public let changes: [ChangeRecord]
}
