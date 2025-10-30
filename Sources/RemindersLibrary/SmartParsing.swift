import Foundation
import EventKit

// MARK: - Priority Parsing

extension Priority {
    /// Parse priority from various natural formats
    /// Supports: !!!, !!, !, ^high, ^urgent, ^critical, ^3, ^medium, ^important, ^2, ^low, ^normal, ^1, ^none, ^0, ^, or empty string
    public init?(fromString string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces).lowercased()

        // Empty string → none
        if trimmed.isEmpty {
            self = .none
            return
        }

        // Symbol-based priorities
        if trimmed == "!!!" {
            self = .high
            return
        }
        if trimmed == "!!" {
            self = .medium
            return
        }
        if trimmed == "!" {
            self = .low
            return
        }

        // Remove ^ prefix if present
        let value = trimmed.hasPrefix("^") ? String(trimmed.dropFirst()) : trimmed

        // Word and number based priorities
        switch value {
        case "high", "urgent", "critical", "3":
            self = .high
        case "medium", "important", "2":
            self = .medium
        case "low", "normal", "1":
            self = .low
        case "none", "0", "":
            self = .none
        default:
            // Try the standard rawValue init as fallback
            if let priority = Priority(rawValue: value) {
                self = priority
            } else {
                return nil
            }
        }
    }
}

// MARK: - Metadata Extraction

/// Metadata extracted from a reminder title
public struct ReminderMetadata {
    public let cleanedTitle: String
    public let priority: Priority?
    public let listName: String?
    public let tags: [String]
    public let dueDate: DateComponents?

    public init(cleanedTitle: String, priority: Priority? = nil, listName: String? = nil, tags: [String] = [], dueDate: DateComponents? = nil) {
        self.cleanedTitle = cleanedTitle
        self.priority = priority
        self.listName = listName
        self.tags = tags
        self.dueDate = dueDate
    }
}

/// Parser for extracting metadata from reminder titles
public struct TitleParser {
    /// Parse a title and extract metadata markers
    ///
    /// Markers:
    /// - `!!!`, `!!`, `!` or `^priority` → priority
    /// - `@listname` → list
    /// - `#tag` → tags
    /// - Natural language dates → due date
    ///
    /// Example: "Buy milk tomorrow @Groceries ^high #shopping"
    /// Returns: ReminderMetadata(cleanedTitle: "Buy milk", priority: .high, listName: "Groceries", tags: ["shopping"], dueDate: tomorrow)
    public static func parse(_ title: String) -> ReminderMetadata {
        var cleanedTitle = title
        var priority: Priority?
        var listName: String?
        var tags: [String] = []
        var dueDate: DateComponents?

        // Regular expressions for metadata markers
        // Priority symbols (!!!, !!, !) - match as separate tokens with optional surrounding whitespace
        let prioritySymbolPattern = #"(^|\s)(!!!|!!|!)(\s|$)"#
        if let match = cleanedTitle.range(of: prioritySymbolPattern, options: .regularExpression) {
            let matchedText = String(cleanedTitle[match])
            // Extract just the symbols
            let symbol = matchedText.trimmingCharacters(in: .whitespaces)
            priority = Priority(fromString: symbol)
            cleanedTitle.removeSubrange(match)
        }

        // Priority with ^ prefix: ^high, ^urgent, ^critical, ^3, etc.
        let priorityCaretPattern = #"\^(high|urgent|critical|medium|important|low|normal|none|\d+)"#
        if let match = cleanedTitle.range(of: priorityCaretPattern, options: [.regularExpression, .caseInsensitive]) {
            let priorityString = String(cleanedTitle[match])
            priority = Priority(fromString: priorityString)
            cleanedTitle.removeSubrange(match)
        }

        // Tags: #tag (captures alphabetic tags, not pure numbers like #123)
        // Must have at least one letter to be considered a tag
        let tagPattern = #"#([a-zA-Z][a-zA-Z0-9]*)"#
        let tagMatches = cleanedTitle.ranges(of: tagPattern, options: .regularExpression)
        for range in tagMatches.reversed() { // Remove in reverse to maintain indices
            let matchedText = String(cleanedTitle[range])
            tags.insert(String(matchedText.dropFirst()), at: 0) // Remove #
            cleanedTitle.removeSubrange(range)
        }

        // List name: @listname (captures until whitespace, #, ^, or end)
        let listPattern = #"@([^\s#^]+)"#
        if let match = cleanedTitle.range(of: listPattern, options: .regularExpression) {
            let matchedText = String(cleanedTitle[match])
            listName = String(matchedText.dropFirst()) // Remove @
            cleanedTitle.removeSubrange(match)
        }

        // Clean up multiple spaces and trim before date detection
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        cleanedTitle = cleanedTitle.trimmingCharacters(in: .whitespaces)

        // Natural language date - try to find dates in the remaining text
        // Use NSDataDetector to find date phrases
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let range = NSRange(cleanedTitle.startIndex..<cleanedTitle.endIndex, in: cleanedTitle)
            let matches = detector.matches(in: cleanedTitle, options: [], range: range)

            // Process matches in reverse order to maintain string indices
            for match in matches.reversed() {
                if let matchRange = Range(match.range, in: cleanedTitle),
                   match.date != nil {
                    // Parse the date string using our natural language parser
                    let dateString = String(cleanedTitle[matchRange])
                    if let parsedDate = DateComponents(argument: dateString) {
                        dueDate = parsedDate
                        // Remove the date phrase from the title
                        cleanedTitle.removeSubrange(matchRange)
                        break // Only use the first date found
                    }
                }
            }
        }

        // Final cleanup of multiple spaces and trim
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        cleanedTitle = cleanedTitle.trimmingCharacters(in: .whitespaces)

        return ReminderMetadata(
            cleanedTitle: cleanedTitle,
            priority: priority,
            listName: listName,
            tags: tags,
            dueDate: dueDate
        )
    }
}

// Helper extension for finding multiple ranges
extension String {
    func ranges(of searchString: String, options: String.CompareOptions = []) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var startIndex = self.startIndex

        while startIndex < self.endIndex {
            if let range = self.range(of: searchString, options: options, range: startIndex..<self.endIndex) {
                ranges.append(range)
                startIndex = range.upperBound
            } else {
                break
            }
        }

        return ranges
    }
}
