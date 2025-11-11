import Foundation

enum SearchField: String, Decodable {
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

enum SearchOperator: String, Decodable {
    case equals
    case notEquals
    case contains
    case notContains
    case includes
    case excludes
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

enum SearchValue: Decodable {
    case string(String)
    case bool(Bool)
    case number(Double)
    case array([SearchValue])
    case null

    init(from decoder: Decoder) throws {
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

struct SearchClause: Decodable {
    let field: SearchField
    let op: SearchOperator
    let value: SearchValue?
}

struct LogicNode: Decodable {
    let clause: SearchClause?
    let all: [LogicNode]?
    let any: [LogicNode]?
    let xor: [LogicNode]?
    let not: LogicNode?

    var isEmpty: Bool {
        clause == nil && all == nil && any == nil && xor == nil && not == nil
    }
}

enum SearchGroupField: String, Decodable {
    case priority
    case list
    case tag
    case dueDate
}

enum SearchDateGranularity: String, Decodable {
    case day
    case week
    case month
}

struct SearchGrouping: Decodable {
    let field: SearchGroupField
    let granularity: SearchDateGranularity?
}

enum SearchSortField: String, Decodable {
    case priority
    case list
    case tag
    case title
    case dueDate
    case createdAt
    case updatedAt
}

enum SortDirection: String, Decodable {
    case asc
    case desc
}

struct SearchSortDescriptor: Decodable {
    let field: SearchSortField
    let direction: SortDirection
}

struct SearchPagination: Decodable {
    let limit: Int?
    let offset: Int?
}

struct SearchRequest: Decodable {
    let logic: LogicNode?
    let groupBy: [SearchGrouping]?
    let sort: [SearchSortDescriptor]?
    let pagination: SearchPagination?
    let includeCompleted: Bool?
    let lists: [String]?
    let query: String?
}

struct SearchGroup: Encodable {
    let field: String
    let value: String
    let count: Int
    let reminderUUIDs: [String]
    let children: [SearchGroup]?
}
