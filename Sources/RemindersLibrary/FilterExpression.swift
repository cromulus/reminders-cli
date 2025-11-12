import Foundation
import EventKit

// MARK: - Operators & Conditions

public enum FilterOperator: String {
    case equals = "="
    case notEquals = "!="
    case lessThan = "<"
    case greaterThan = ">"
    case lessOrEqual = "<="
    case greaterOrEqual = ">="
    case contains = "CONTAINS"
    case notContains = "NOT CONTAINS"
    case like = "LIKE"
    case notLike = "NOT LIKE"
    case matches = "MATCHES"
    case notMatches = "NOT MATCHES"
    case `in` = "IN"
    case notIn = "NOT IN"
}

public struct FilterCondition {
    public let field: String
    public let op: FilterOperator
    public let value: String

    public init(field: String, op: FilterOperator, value: String) {
        self.field = field
        self.op = op
        self.value = value
    }

    public func evaluate(_ reminder: EKReminder, calendar: Calendar) -> Bool {
        let actualValue = getFieldValue(from: reminder)
        let result: Bool

        switch op {
        case .equals:
            result = actualValue.caseInsensitiveCompare(value) == .orderedSame
        case .notEquals:
            result = actualValue.caseInsensitiveCompare(value) != .orderedSame
        case .contains:
            result = actualValue.range(of: value, options: .caseInsensitive) != nil
        case .notContains:
            result = actualValue.range(of: value, options: .caseInsensitive) == nil
        case .like:
            result = matchWildcard(pattern: value, text: actualValue)
        case .notLike:
            result = !matchWildcard(pattern: value, text: actualValue)
        case .matches:
            result = matchRegex(pattern: value, text: actualValue)
        case .notMatches:
            result = !matchRegex(pattern: value, text: actualValue)
        case .in:
            result = value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .contains { $0.caseInsensitiveCompare(actualValue) == .orderedSame }
        case .notIn:
            result = !value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .contains { $0.caseInsensitiveCompare(actualValue) == .orderedSame }
        case .lessThan, .greaterThan, .lessOrEqual, .greaterOrEqual:
            result = evaluateDateComparison(reminder, op: op, value: value, calendar: calendar)
        }

        return result
    }

    private func getFieldValue(from reminder: EKReminder) -> String {
        switch field.lowercased() {
        case "title":
            return reminder.title ?? ""
        case "notes":
            return reminder.notes ?? ""
        case "list":
            return reminder.calendar.title
        case "priority":
            return priorityBucket(for: reminder)
        case "completed", "iscompleted":
            return reminder.isCompleted ? "true" : "false"
        case "hasnotes":
            let hasNotes = (reminder.notes?.isEmpty == false)
            return hasNotes ? "true" : "false"
        case "hasduedate":
            return reminder.dueDateComponents != nil ? "true" : "false"
        case "duedate":
            return reminder.dueDateComponents?.date?.description ?? ""
        default:
            return ""
        }
    }

    private func priorityBucket(for reminder: EKReminder) -> String {
        switch reminder.priority {
        case 0:
            return "none"
        case 1...4:
            return "high"
        case 5:
            return "medium"
        case 6...9:
            return "low"
        default:
            return "none"
        }
    }

    private func evaluateDateComparison(_ reminder: EKReminder, op: FilterOperator, value: String, calendar: Calendar) -> Bool {
        guard let dueDate = reminder.dueDateComponents?.date else { return false }
        guard let compareDate = parseDate(value, calendar: calendar) else { return false }

        switch op {
        case .lessThan:
            return dueDate < compareDate
        case .greaterThan:
            return dueDate > compareDate
        case .lessOrEqual:
            return dueDate <= compareDate
        case .greaterOrEqual:
            return dueDate >= compareDate
        default:
            return false
        }
    }

    private func parseDate(_ dateStr: String, calendar: Calendar) -> Date? {
        let trimmed = dateStr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let offsetMatch = trimmed.range(of: #"^[a-zA-Z_ ]+\s*[+-]\s*\d+$"#, options: .regularExpression) {
            let expression = trimmed[offsetMatch].replacingOccurrences(of: "_", with: " ")
            if let date = FilterCondition.baseDate(from: expression, calendar: calendar) {
                return date
            }
        }

        var keyword = trimmed.lowercased()
        if keyword.hasSuffix("()") {
            keyword = String(keyword.dropLast(2))
        }
        keyword = keyword.replacingOccurrences(of: "_", with: " ")

        if let keywordDate = Self.dateFromKeyword(keyword, calendar: calendar) {
            return keywordDate
        }

        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: trimmed) {
            return date
        }

        if let components = DateComponents(argument: trimmed) {
            return calendar.date(from: components)
        }

        return nil
    }

    private static func baseDate(from input: String, calendar: Calendar) -> Date? {
        let parts = input.components(separatedBy: CharacterSet(charactersIn: "+-"))
        guard parts.count == 2,
              let base = dateFromKeyword(parts[0].trimmingCharacters(in: .whitespaces), calendar: calendar),
              let offsetValue = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }

        let sign: Int = input.contains("-") ? -1 : 1
        return calendar.date(byAdding: .day, value: offsetValue * sign, to: base)
    }

    private static func dateFromKeyword(_ keyword: String, calendar: Calendar) -> Date? {
        let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        switch normalized {
        case "now":
            return now
        case "today":
            return startOfToday
        case "tomorrow":
            return calendar.date(byAdding: .day, value: 1, to: startOfToday)
        case "yesterday":
            return calendar.date(byAdding: .day, value: -1, to: startOfToday)
        case "start of week":
            return calendar.dateInterval(of: .weekOfYear, for: startOfToday)?.start
        case "end of week":
            if let start = calendar.dateInterval(of: .weekOfYear, for: startOfToday)?.start {
                return calendar.date(byAdding: .day, value: 7, to: start)
            }
            return nil
        case "start of month":
            return calendar.dateInterval(of: .month, for: startOfToday)?.start
        case "end of month":
            if let start = calendar.dateInterval(of: .month, for: startOfToday)?.start {
                return calendar.date(byAdding: .month, value: 1, to: start)
            }
            return nil
        case "next week":
            return calendar.date(byAdding: .day, value: 7, to: startOfToday)
        case "last week":
            return calendar.date(byAdding: .day, value: -7, to: startOfToday)
        case "next month":
            return calendar.date(byAdding: .month, value: 1, to: startOfToday)
        case "last month":
            return calendar.date(byAdding: .month, value: -1, to: startOfToday)
        default:
            break
        }

        if normalized.hasPrefix("next ") {
            let token = String(normalized.dropFirst(5))
            return dateForWeekday(named: token, direction: .forward, calendar: calendar)
        }

        if normalized.hasPrefix("last ") {
            let token = String(normalized.dropFirst(5))
            return dateForWeekday(named: token, direction: .backward, calendar: calendar)
        }

        if let weekdayDate = dateForWeekday(named: normalized, direction: .forward, calendar: calendar) {
            return weekdayDate
        }

        return nil
    }

    private static func dateForWeekday(named name: String, direction: Calendar.SearchDirection, calendar: Calendar) -> Date? {
        guard let weekday = weekdayNumber(from: name, calendar: calendar) else { return nil }
        var components = DateComponents()
        components.weekday = weekday
        return calendar.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime, direction: direction)
    }

    private static func weekdayNumber(from name: String, calendar: Calendar) -> Int? {
        let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let weekdays = calendar.weekdaySymbols.map { $0.lowercased() }
        if let index = weekdays.firstIndex(of: lower) {
            return index + 1
        }

        let shortWeekdays = calendar.shortWeekdaySymbols.map { $0.lowercased() }
        if let index = shortWeekdays.firstIndex(of: lower) {
            return index + 1
        }

        return nil
    }

    private func matchWildcard(pattern: String, text: String) -> Bool {
        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "?", with: ".")

        return matchRegex(pattern: "^\(regexPattern)$", text: text)
    }

    private func matchRegex(pattern: String, text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}

// MARK: - Expression Tree

fileprivate indirect enum FilterExpressionNode {
    case condition(FilterCondition)
    case not(FilterExpressionNode)
    case and(FilterExpressionNode, FilterExpressionNode)
    case or(FilterExpressionNode, FilterExpressionNode)
}

// MARK: - Public Expression API

public struct FilterExpression {
    private let root: FilterExpressionNode?

    fileprivate init(root: FilterExpressionNode? = nil) {
        self.root = root
    }

    public static var empty: FilterExpression { FilterExpression(root: nil) }

    public var isEmpty: Bool { root == nil }

    public func evaluate(_ reminder: EKReminder, calendar: Calendar) -> Bool {
        guard let root else { return true }
        return Self.evaluate(node: root, reminder: reminder, calendar: calendar)
    }

    private static func evaluate(node: FilterExpressionNode, reminder: EKReminder, calendar: Calendar) -> Bool {
        switch node {
        case .condition(let condition):
            return condition.evaluate(reminder, calendar: calendar)
        case .not(let next):
            return !evaluate(node: next, reminder: reminder, calendar: calendar)
        case .and(let lhs, let rhs):
            let leftResult = evaluate(node: lhs, reminder: reminder, calendar: calendar)
            if !leftResult { return false }
            return evaluate(node: rhs, reminder: reminder, calendar: calendar)
        case .or(let lhs, let rhs):
            let leftResult = evaluate(node: lhs, reminder: reminder, calendar: calendar)
            if leftResult { return true }
            return evaluate(node: rhs, reminder: reminder, calendar: calendar)
        }
    }

    public static func parse(_ filterString: String) throws -> FilterExpression {
        let trimmed = filterString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let expanded = expandShortcuts(trimmed)
        var parser = FilterParser(expanded)
        let node = try parser.parseExpression()
        return FilterExpression(root: node)
    }

    // MARK: - Shortcut Expansion

    private static func expandShortcuts(_ query: String) -> String {
        let shortcuts: [String: String] = [
            "overdue": "(dueDate < now AND completed = false)",
            "due_today": "(dueDate >= today AND dueDate < end_of_day)",
            "due_tomorrow": "(dueDate >= tomorrow AND dueDate < tomorrow+1)",
            "this_week": "(dueDate >= start_of_week AND dueDate < end_of_week)",
            "next_week": "(dueDate >= next week AND dueDate < next week+7)",
            "high_priority": "priority IN [high,medium]",
            "incomplete": "completed = false",
            "complete": "completed = true"
        ]

        var expanded = query
        for (shortcut, replacement) in shortcuts {
            let pattern = "\\b\(shortcut)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(expanded.startIndex..<expanded.endIndex, in: expanded)
                expanded = regex.stringByReplacingMatches(in: expanded, range: range, withTemplate: replacement)
            }
        }

        return expanded
    }

    // MARK: - Testing Helper

    static func parseConditionPublic(_ conditionStr: String) throws -> FilterCondition {
        var parser = FilterParser(conditionStr)
        guard let node = try parser.parseExpression() else {
            throw RemindersMCPError.invalidArguments("Unable to parse expression: \(conditionStr)")
        }

        switch node {
        case .condition(let condition):
            return condition
        default:
            throw RemindersMCPError.invalidArguments("Expression does not resolve to a single condition")
        }
    }
}

// MARK: - Lexer

fileprivate enum FilterToken: Equatable {
    case eof
    case identifier(String)
    case stringLiteral(String)
    case numberLiteral(String)
    case comma
    case lParen
    case rParen
    case lBracket
    case rBracket
    case equals
    case notEquals
    case lessThan
    case greaterThan
    case lessOrEqual
    case greaterOrEqual
}

fileprivate struct FilterLexer {
    private let characters: [Character]
    private var index: Int = 0

    init(_ text: String) {
        self.characters = Array(text)
    }

    mutating func nextToken() throws -> FilterToken {
        skipWhitespace()
        guard !isAtEnd else { return .eof }

        let char = advance()
        switch char {
        case "(":
            return .lParen
        case ")":
            return .rParen
        case "[":
            return .lBracket
        case "]":
            return .rBracket
        case ",":
            return .comma
        case "=":
            if match("=") { return .equals }
            return .equals
        case "!":
            if match("=") { return .notEquals }
            throw RemindersMCPError.invalidArguments("Unexpected token !")
        case "<":
            if match("=") { return .lessOrEqual }
            return .lessThan
        case ">":
            if match("=") { return .greaterOrEqual }
            return .greaterThan
        case "\"", "'":
            return .stringLiteral(try readString(terminator: char))
        default:
            if char.isNumber {
                return .numberLiteral(readNumber(startingWith: char))
            } else if char.isLetter || char == "_" {
                return .identifier(readIdentifier(startingWith: char))
            }

            throw RemindersMCPError.invalidArguments("Unexpected character \(char)")
        }
    }

    private mutating func skipWhitespace() {
        while !isAtEnd, characters[index].isWhitespace {
            index += 1
        }
    }

    private var isAtEnd: Bool {
        index >= characters.count
    }

    @discardableResult
    private mutating func advance() -> Character {
        defer { index += 1 }
        return characters[index]
    }

    private mutating func peek() -> Character? {
        guard !isAtEnd else { return nil }
        return characters[index]
    }

    private mutating func match(_ expected: Character) -> Bool {
        guard !isAtEnd, characters[index] == expected else { return false }
        index += 1
        return true
    }

    private mutating func readString(terminator: Character) throws -> String {
        var value = ""
        var terminated = false
        while !isAtEnd {
            let current = advance()
            if current == terminator {
                terminated = true
                break
            }

            if current == "\\" {
                guard let next = peek() else { continue }
                value.append(next)
                index += 1
            } else {
                value.append(current)
            }
        }
        if !terminated {
            throw RemindersMCPError.invalidArguments("Unterminated string literal")
        }
        return value
    }

    private mutating func readNumber(startingWith first: Character) -> String {
        var value = String(first)
        while let next = peek(), next.isNumber || next == "." {
            value.append(next)
            index += 1
        }
        return value
    }

    private mutating func readIdentifier(startingWith first: Character) -> String {
        var value = String(first)
        while let next = peek(), next.isLetter || next.isNumber || next == "_" {
            value.append(next)
            index += 1
        }
        return value
    }
}

// MARK: - Parser

fileprivate struct FilterParser {
    private var lexer: FilterLexer
    private var current: FilterToken

    init(_ text: String) {
        self.lexer = FilterLexer(text)
        self.current = .eof
        advance()
    }

    mutating func parseExpression() throws -> FilterExpressionNode? {
        if case .eof = current { return nil }
        let expr = try parseOr()
        try expect(.eof)
        return expr
    }

    private mutating func parseOr() throws -> FilterExpressionNode {
        var node = try parseAnd()
        while matchKeyword("OR") {
            let rhs = try parseAnd()
            node = .or(node, rhs)
        }
        return node
    }

    private mutating func parseAnd() throws -> FilterExpressionNode {
        var node = try parseUnary()
        while matchKeyword("AND") {
            let rhs = try parseUnary()
            node = .and(node, rhs)
        }
        return node
    }

    private mutating func parseUnary() throws -> FilterExpressionNode {
        if matchKeyword("NOT") {
            let operand = try parseUnary()
            return .not(operand)
        }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws -> FilterExpressionNode {
        if match(.lParen) {
            let expr = try parseOr()
            try expect(.rParen)
            return expr
        }

        return try parseConditionNode()
    }

    private mutating func parseConditionNode() throws -> FilterExpressionNode {
        let field = try expectIdentifier()

        if matchKeyword("BETWEEN") {
            let lower = try parseValue()
            guard matchKeyword("AND") else {
                throw RemindersMCPError.invalidArguments("BETWEEN clauses require AND")
            }
            let upper = try parseValue()

            let lowerCondition = FilterCondition(field: field, op: .greaterOrEqual, value: lower)
            let upperCondition = FilterCondition(field: field, op: .lessOrEqual, value: upper)
            return .and(.condition(lowerCondition), .condition(upperCondition))
        }

        var notModifier = false
        if matchKeyword("NOT") {
            notModifier = true
        }

        if matchKeyword("IN") {
            let values = try parseValueList()
            guard !values.isEmpty else {
                throw RemindersMCPError.invalidArguments("IN clauses require at least one value")
            }
            let valueString = values.joined(separator: ", ")
            let op: FilterOperator = notModifier ? .notIn : .in
            return .condition(FilterCondition(field: field, op: op, value: valueString))
        }

        if matchKeyword("CONTAINS") {
            let value = try parseValue()
            let op: FilterOperator = notModifier ? .notContains : .contains
            return .condition(FilterCondition(field: field, op: op, value: value))
        }

        if matchKeyword("LIKE") {
            let value = try parseValue()
            let op: FilterOperator = notModifier ? .notLike : .like
            return .condition(FilterCondition(field: field, op: op, value: value))
        }

        if matchKeyword("MATCHES") {
            let value = try parseValue()
            let op: FilterOperator = notModifier ? .notMatches : .matches
            return .condition(FilterCondition(field: field, op: op, value: value))
        }

        if notModifier {
            // A bare NOT with no operator is invalid at this level
            throw RemindersMCPError.invalidArguments("NOT must modify CONTAINS/LIKE/MATCHES/IN or a parenthesized expression")
        }

        if match(.equals) {
            let value = try parseValue()
            return .condition(FilterCondition(field: field, op: .equals, value: value))
        } else if match(.notEquals) {
            let value = try parseValue()
            return .condition(FilterCondition(field: field, op: .notEquals, value: value))
        } else if match(.lessOrEqual) {
            let value = try parseValue()
            return .condition(FilterCondition(field: field, op: .lessOrEqual, value: value))
        } else if match(.greaterOrEqual) {
            let value = try parseValue()
            return .condition(FilterCondition(field: field, op: .greaterOrEqual, value: value))
        } else if match(.lessThan) {
            let value = try parseValue()
            return .condition(FilterCondition(field: field, op: .lessThan, value: value))
        } else if match(.greaterThan) {
            let value = try parseValue()
            return .condition(FilterCondition(field: field, op: .greaterThan, value: value))
        }

        throw RemindersMCPError.invalidArguments("Invalid filter near field '\(field)'")
    }

    private mutating func parseValue() throws -> String {
        switch current {
        case .stringLiteral(let value):
            advance()
            return value
        case .numberLiteral(let value):
            advance()
            return value
        case .identifier(let ident):
            advance()
            switch ident.lowercased() {
            case "true":
                return "true"
            case "false":
                return "false"
            default:
                return ident
            }
        default:
            throw RemindersMCPError.invalidArguments("Expected value but found \(current)")
        }
    }

    private mutating func parseValueList() throws -> [String] {
        var values: [String] = []
        var closingToken: FilterToken?

        if match(.lParen) {
            closingToken = .rParen
        } else if match(.lBracket) {
            closingToken = .rBracket
        }

        repeat {
            let value = try parseValue()
            values.append(value)
        } while match(.comma)

        if let closing = closingToken {
            if !match(closing) {
                throw RemindersMCPError.invalidArguments("Unterminated IN list")
            }
        }

        return values
    }

    // MARK: - Token Helpers

    private mutating func advance() {
        if let next = try? lexer.nextToken() {
            current = next
        } else {
            current = .eof
        }
    }

    private mutating func expect(_ token: FilterToken) throws {
        if current == token {
            advance()
        } else if case .eof = token {
            if case .eof = current { return }
            throw RemindersMCPError.invalidArguments("Unexpected trailing tokens")
        } else {
            throw RemindersMCPError.invalidArguments("Unexpected token while parsing expression")
        }
    }

    private mutating func expectIdentifier() throws -> String {
        if case .identifier(let value) = current {
            advance()
            return value
        }
        throw RemindersMCPError.invalidArguments("Expected identifier for field name")
    }

    private mutating func match(_ token: FilterToken) -> Bool {
        if current == token {
            advance()
            return true
        }
        return false
    }

    private mutating func matchKeyword(_ word: String) -> Bool {
        if case .identifier(let value) = current, value.caseInsensitiveCompare(word) == .orderedSame {
            advance()
            return true
        }
        return false
    }
}
