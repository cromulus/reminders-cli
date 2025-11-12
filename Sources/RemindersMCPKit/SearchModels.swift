import Foundation
import SwiftMCP

public enum SearchField: String, Decodable, Sendable {
    case title
    case notes
    case list
    case listId
    case priority
    case tag
    case dueDate
    case createdAt
    case updatedAt
    case completed
    case hasDueDate
    case hasNotes
}

public enum SearchOperator: String, Decodable, Sendable {
    case equals
    case notEquals
    case contains
    case notContains
    case like
    case notLike
    case includes
    case excludes
    case `in`
    case notIn
    case before
    case after
    case greaterThan
    case lessThan
    case greaterOrEqual
    case lessOrEqual
    case exists
    case notExists
    case matches
    case notMatches
}

public enum SearchValue: Decodable, Sendable {
    case string(String)
    case bool(Bool)
    case number(Double)
    case array([SearchValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let numberValue = try? container.decode(Double.self) {
            self = .number(numberValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([SearchValue].self) {
            self = .array(arrayValue)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported search value")
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .string(let value): return Bool(value)
        case .number(let value): return value != 0
        default: return nil
        }
    }
}

extension SearchValue {
    var stringArray: [String]? {
        switch self {
        case .array(let values):
            return values.compactMap { $0.stringValue }
        case .string(let value):
            return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        default:
            return nil
        }
    }
}

/// Atomic condition within a logic node.
@Schema
public struct SearchClause: Decodable, Sendable {
    public let field: SearchField
    public let op: SearchOperator
    public let value: SearchValue?
}

/// Recursive structure that expresses AND/OR/NOT logic for searches.
public final class LogicNode: Decodable, @unchecked Sendable {
    public let clause: SearchClause?
    public let all: [LogicNode]?
    public let any: [LogicNode]?
    public let xor: [LogicNode]?
    public let not: LogicNode?

    public init(
        clause: SearchClause? = nil,
        all: [LogicNode]? = nil,
        any: [LogicNode]? = nil,
        xor: [LogicNode]? = nil,
        not: LogicNode? = nil
    ) {
        self.clause = clause
        self.all = all
        self.any = any
        self.xor = xor
        self.not = not
    }

    public var isEmpty: Bool {
        clause == nil && (all?.isEmpty ?? true) && (any?.isEmpty ?? true) &&
        (xor?.isEmpty ?? true) && not == nil
    }
}

public enum SearchGroupField: String, Decodable, Sendable {
    case priority
    case list
    case tag
    case dueDate
}

public enum SearchDateGranularity: String, Decodable, Sendable {
    case day
    case week
    case month
}

/// Grouping descriptor used to aggregate search results.
@Schema
public struct SearchGrouping: Decodable, Sendable {
    public let field: SearchGroupField
    public let granularity: SearchDateGranularity?
}

public enum SearchSortField: String, Decodable, Sendable {
    case priority
    case list
    case tag
    case title
    case dueDate
    case createdAt
    case updatedAt
}

public enum SortDirection: String, Decodable, Sendable {
    case asc
    case desc
}

/// Sort descriptor applied to search results.
@Schema
public struct SearchSortDescriptor: Decodable, Sendable {
    public let field: SearchSortField
    public let direction: SortDirection
}

/// Pagination block for search results.
@Schema
public struct SearchPagination: Decodable, Sendable {
    public let limit: Int?
    public let offset: Int?
}

/// Rich search payload for reminders.
@Schema
public struct SearchRequest: Decodable, Sendable {
    /// Structured logic tree. Use `all` (AND), `any` (OR), `not`.
    public let logic: LogicNode?
    /// Optional grouping descriptors for aggregation.
    public let groupBy: [SearchGrouping]?
    /// Sort descriptors evaluated in order.
    public let sort: [SearchSortDescriptor]?
    /// Pagination information (limit/offset).
    public let pagination: SearchPagination?
    /// Include completed reminders (default: false).
    public let includeCompleted: Bool?
    /// Restrict to specific lists (names or identifiers).
    public let lists: [String]?
    /// Lightweight fuzzy query applied to title/notes.
    public let query: String?

    public init(logic: LogicNode? = nil,
                groupBy: [SearchGrouping]? = nil,
                sort: [SearchSortDescriptor]? = nil,
                pagination: SearchPagination? = nil,
                includeCompleted: Bool? = nil,
                lists: [String]? = nil,
                query: String? = nil) {
        self.logic = logic
        self.groupBy = groupBy
        self.sort = sort
        self.pagination = pagination
        self.includeCompleted = includeCompleted
        self.lists = lists
        self.query = query
    }

    private init(dto: SearchRequestDTO) {
        self.init(
            logic: dto.logic,
            groupBy: dto.groupBy,
            sort: dto.sort,
            pagination: dto.pagination,
            includeCompleted: dto.includeCompleted,
            lists: dto.lists,
            query: dto.query
        )
    }

    public init(from decoder: Decoder) throws {
        if let dto = try? SearchRequestDTO(from: decoder) {
            self.init(dto: dto)
            return
        }

        if let stringValue = try? decoder.singleValueContainer().decode(String.self) {
            let data = Data(stringValue.utf8)
            let dto = try JSONDecoder().decode(SearchRequestDTO.self, from: data)
            self.init(dto: dto)
            return
        }

        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self),
           let requestKey = container.allKeys.first(where: { $0.stringValue == "request" }) {
            let nested = try container.superDecoder(forKey: requestKey)
            let dto = try SearchRequestDTO(from: nested)
            self.init(dto: dto)
            return
        }

        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unable to decode SearchRequest"))
    }
}

private struct SearchRequestDTO: Decodable {
    let logic: LogicNode?
    let groupBy: [SearchGrouping]?
    let sort: [SearchSortDescriptor]?
    let pagination: SearchPagination?
    let includeCompleted: Bool?
    let lists: [String]?
    let query: String?
}

public struct SearchGroup: Encodable {
    public let field: String
    public let value: String
    public let count: Int
    public let reminderUUIDs: [String]
    public let children: [SearchGroup]?
}
