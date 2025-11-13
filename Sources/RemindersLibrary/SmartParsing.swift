import Foundation
import EventKit

// MARK: - Priority Parsing

extension Priority {
    /// Parse priority from various natural formats
    /// Supports: high, urgent, critical, medium, important, low, normal, none, or numbers 0-3
    public init?(fromString string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces).lowercased()

        // Empty string → none
        if trimmed.isEmpty {
            self = .none
            return
        }

        // Word and number based priorities
        switch trimmed {
        case "high", "urgent", "critical", "3":
            self = .high
        case "medium", "important", "2":
            self = .medium
        case "low", "normal", "1":
            self = .low
        case "none", "0":
            self = .none
        default:
            // Try the standard rawValue init as fallback
            if let priority = Priority(rawValue: trimmed) {
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

    public let recurrencePattern: String?

    public init(cleanedTitle: String,
                priority: Priority? = nil,
                listName: String? = nil,
                tags: [String] = [],
                dueDate: DateComponents? = nil,
                recurrencePattern: String? = nil) {
        self.cleanedTitle = cleanedTitle
        self.priority = priority
        self.listName = listName
        self.tags = tags
        self.dueDate = dueDate
        self.recurrencePattern = recurrencePattern
    }
}

/// Parser for extracting metadata from reminder titles
public struct TitleParser {
    /// Parse a title and extract metadata markers
    ///
    /// Markers:
    /// - `!high`, `!3`, `!urgent`, `!medium`, `!2`, `!low`, `!1`, `!none`, `!0` → priority
    /// - `@listname` → list
    /// - `#tag` → tags
    /// - Natural language dates → due date
    ///
    /// Example: "Buy milk tomorrow @Groceries !high #shopping"
    /// Returns: ReminderMetadata(cleanedTitle: "Buy milk", priority: .high, listName: "Groceries", tags: ["shopping"], dueDate: tomorrow)
    public static func parse(_ title: String) -> ReminderMetadata {
        var cleanedTitle = title
        var priority: Priority?
        var listName: String?
        var tags: [String] = []
        var dueDate: DateComponents?
        var recurrencePattern: String?

        // Regular expressions for metadata markers
        // Priority with ! prefix: !high, !3, !urgent, !medium, !2, !low, !1, !none, !0
        let priorityPattern = #"!(high|urgent|critical|medium|important|low|normal|none|\d+)"#
        if let match = cleanedTitle.range(of: priorityPattern, options: [.regularExpression, .caseInsensitive]) {
            let matchedText = String(cleanedTitle[match])
            // Extract the word/number part after !
            let value = String(matchedText.dropFirst())
            priority = Priority(fromString: value)
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
        // Note: A reminder can only be in ONE list, so we only extract the first @list marker
        // and leave any additional ones in the title as a visual indicator of the issue
        let listPattern = #"@([^\s#^]+)"#
        let listMatches = cleanedTitle.ranges(of: listPattern, options: .regularExpression)

        if let firstMatch = listMatches.first {
            let matchedText = String(cleanedTitle[firstMatch])
            listName = String(matchedText.dropFirst()) // Remove @
            cleanedTitle.removeSubrange(firstMatch)
            // If there are additional @list markers, leave them in the title
            // so the user can see there's an issue
        }

        // Clean up multiple spaces and trim before date detection
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        cleanedTitle = cleanedTitle.trimmingCharacters(in: .whitespaces)

        // Recurrence marker using ~ syntax (eg: ~weekly, ~every 2 weeks)
        if let regex = try? NSRegularExpression(pattern: #"~([^@#!^]+)"#, options: [.caseInsensitive]) {
            let range = NSRange(cleanedTitle.startIndex..<cleanedTitle.endIndex, in: cleanedTitle)
            if let match = regex.firstMatch(in: cleanedTitle, options: [], range: range),
               match.numberOfRanges > 1,
               let fullRange = Range(match.range(at: 0), in: cleanedTitle),
               let captureRange = Range(match.range(at: 1), in: cleanedTitle) {
                let value = cleanedTitle[captureRange].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    recurrencePattern = value
                }
                cleanedTitle.removeSubrange(fullRange)
                cleanedTitle = cleanedTitle.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                cleanedTitle = cleanedTitle.trimmingCharacters(in: .whitespaces)
            }
        }

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
            dueDate: dueDate,
            recurrencePattern: recurrencePattern
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
