import Foundation

public enum SearchField: String, Decodable {
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

public enum SearchOperator: String, Decodable {
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

public enum SearchValue: Decodable {
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

public struct SearchClause: Decodable {
    public let field: SearchField
    public let op: SearchOperator
    public let value: SearchValue?
}

public final class LogicNode: Decodable {
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

public enum SearchGroupField: String, Decodable {
    case priority
    case list
    case tag
    case dueDate
}

public enum SearchDateGranularity: String, Decodable {
    case day
    case week
    case month
}

public struct SearchGrouping: Decodable {
    public let field: SearchGroupField
    public let granularity: SearchDateGranularity?
}

public enum SearchSortField: String, Decodable {
    case priority
    case list
    case tag
    case title
    case dueDate
    case createdAt
    case updatedAt
}

public enum SortDirection: String, Decodable {
    case asc
    case desc
}

public struct SearchSortDescriptor: Decodable {
    public let field: SearchSortField
    public let direction: SortDirection
}

public struct SearchPagination: Decodable {
    public let limit: Int?
    public let offset: Int?
}

public struct SearchRequest: Decodable {
    public let logic: LogicNode?
    public let groupBy: [SearchGrouping]?
    public let sort: [SearchSortDescriptor]?
    public let pagination: SearchPagination?
    public let includeCompleted: Bool?
    public let lists: [String]?
    public let query: String?
}

public struct SearchGroup: Encodable {
    public let field: String
    public let value: String
    public let count: Int
    public let reminderUUIDs: [String]
    public let children: [SearchGroup]?
}
