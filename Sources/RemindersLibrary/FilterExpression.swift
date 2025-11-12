import Foundation
import EventKit

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

public enum LogicalOperator: String {
    case and = "AND"
    case or = "OR"
}

public struct FilterCondition {
    public let field: String
    public let op: FilterOperator
    public let value: String
    public let negate: Bool

    public init(field: String, op: FilterOperator, value: String, negate: Bool) {
        self.field = field
        self.op = op
        self.value = value
        self.negate = negate
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

        return negate ? !result : result
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
        case "completed":
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

        guard let compareDate = parseDate(value, calendar: calendar) else {
            return false
        }

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

    private static func dateFromKeyword(_ keyword: String, calendar: Calendar) -> Date? {
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        switch keyword {
        case "now":
            return now
        case "today":
            return startOfToday
        case "tomorrow":
            return calendar.date(byAdding: .day, value: 1, to: startOfToday)
        case "yesterday":
            return calendar.date(byAdding: .day, value: -1, to: startOfToday)
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

        if keyword.hasPrefix("next ") {
            let token = String(keyword.dropFirst(5))
            return dateForWeekday(named: token, direction: .forward, calendar: calendar)
        }

        if keyword.hasPrefix("last ") {
            let token = String(keyword.dropFirst(5))
            return dateForWeekday(named: token, direction: .backward, calendar: calendar)
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

public struct FilterExpression {
    public let conditions: [FilterCondition]
    public let logicalOps: [LogicalOperator]

    public func evaluate(_ reminder: EKReminder, calendar: Calendar) -> Bool {
        guard !conditions.isEmpty else { return true }

        if conditions.count == 1 {
            return conditions[0].evaluate(reminder, calendar: calendar)
        }

        var result = conditions[0].evaluate(reminder, calendar: calendar)

        for (index, logicalOp) in logicalOps.enumerated() {
            let nextCondition = conditions[index + 1]
            let nextResult = nextCondition.evaluate(reminder, calendar: calendar)

            switch logicalOp {
            case .and:
                result = result && nextResult
            case .or:
                result = result || nextResult
            }
        }

        return result
    }

    public static func parse(_ filterString: String) throws -> FilterExpression {
        let expandedFilter = expandShortcuts(filterString)

        var conditions: [FilterCondition] = []
        var logicalOps: [LogicalOperator] = []

        let parts = splitByLogicalOperators(expandedFilter)

        for (index, part) in parts.enumerated() {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if index % 2 == 0 {
                let condition = try parseCondition(trimmed)
                conditions.append(condition)
            } else {
                if let op = LogicalOperator(rawValue: trimmed.uppercased()) {
                    logicalOps.append(op)
                }
            }
        }

        try validateFilterLogic(conditions: conditions, logicalOps: logicalOps)

        return FilterExpression(conditions: conditions, logicalOps: logicalOps)
    }

    private static func expandShortcuts(_ query: String) -> String {
        let shortcuts: [String: String] = [
            "overdue": "(dueDate < now AND completed = false)",
            "due_today": "(dueDate >= today AND dueDate < tomorrow)",
            "due_tomorrow": "(dueDate >= tomorrow AND dueDate < tomorrow+1)",
            "this_week": "(dueDate < end_of_week)",
            "next_week": "(dueDate >= next_week AND dueDate < next_week+7)",
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

    private static func validateFilterLogic(conditions: [FilterCondition], logicalOps: [LogicalOperator]) throws {
        for i in 0..<conditions.count {
            guard i < logicalOps.count else { break }
            guard logicalOps[i] == .and else { continue }

            let current = conditions[i]
            let next = conditions[i + 1]

            guard current.field.lowercased() == next.field.lowercased() else { continue }

            let singleValueFields = ["list", "priority", "completed"]
            guard singleValueFields.contains(current.field.lowercased()) else { continue }

            if current.op == .equals && next.op == .equals {
                if current.value.lowercased() != next.value.lowercased() {
                    let fieldName = current.field.lowercased()
                    throw RemindersMCPError.invalidArguments(
                        "Impossible filter: \(fieldName)='\(current.value)' AND \(fieldName)='\(next.value)'. Did you mean to use OR?"
                    )
                }
            }
        }
    }

    private static func splitByLogicalOperators(_ input: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var i = input.startIndex

        while i < input.endIndex {
            if input[i...].hasPrefix(" AND ") {
                parts.append(current)
                parts.append("AND")
                current = ""
                i = input.index(i, offsetBy: 5)
                continue
            }

            if input[i...].hasPrefix(" OR ") {
                parts.append(current)
                parts.append("OR")
                current = ""
                i = input.index(i, offsetBy: 4)
                continue
            }

            current.append(input[i])
            i = input.index(after: i)
        }

        if !current.isEmpty {
            parts.append(current)
        }

        return parts
    }

    static func parseCondition(_ conditionStr: String) throws -> FilterCondition {
        var negate = false
        var workingStr = conditionStr.trimmingCharacters(in: .whitespaces)

        if workingStr.uppercased().hasPrefix("NOT ") {
            negate = true
            workingStr = String(workingStr.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        }

        let operators: [FilterOperator] = [.notContains, .notLike, .notMatches, .contains, .like, .matches, .notIn, .in, .lessOrEqual, .greaterOrEqual, .notEquals, .equals, .lessThan, .greaterThan]

        for op in operators {
            if let range = workingStr.range(of: " \(op.rawValue) ", options: .caseInsensitive) {
                let field = String(workingStr[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                var value = String(workingStr[range.upperBound...]).trimmingCharacters(in: .whitespaces)

                if op == .in || op == .notIn {
                    value = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]()"))
                }

                value = value.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))

                if op == .in || op == .notIn {
                    value = value.replacingOccurrences(of: "'", with: "")
                    value = value.replacingOccurrences(of: "\"", with: "")
                }

                value = decodeEscaped(value)

                return FilterCondition(field: field, op: op, value: value, negate: negate)
            }

            if op == .equals || op == .notEquals || op == .lessThan || op == .greaterThan {
                if let range = workingStr.range(of: op.rawValue, options: .caseInsensitive) {
                    let field = String(workingStr[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    var value = String(workingStr[range.upperBound...]).trimmingCharacters(in: .whitespaces)

                    value = value.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))

                    if !field.isEmpty && !value.isEmpty {
                        value = decodeEscaped(value)
                        return FilterCondition(field: field, op: op, value: value, negate: negate)
                    }
                }
            }
        }

        throw RemindersMCPError.invalidArguments("Could not parse filter condition: \(conditionStr)")
    }

    private static func decodeEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\\\", with: "\\")
    }
}
