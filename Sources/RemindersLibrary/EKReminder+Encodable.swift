import EventKit
import Foundation

/// Structured date format for API responses
private struct FormattedDate: Encodable {
    let iso: String
    let formatted: String
    let relative: String
    let timezone: String

    init?(from date: Date?) {
        guard let date = date else { return nil }

        // ISO format
        if #available(macOS 12.0, *) {
            self.iso = date.ISO8601Format()
        } else {
            let formatter = ISO8601DateFormatter()
            self.iso = formatter.string(from: date)
        }

        // Human-friendly format with timezone
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.doesRelativeDateFormatting = false
        let formattedWithoutTz = dateFormatter.string(from: date)

        // Get timezone abbreviation
        let timeZone = TimeZone.current
        let abbreviation = timeZone.abbreviation() ?? timeZone.identifier
        self.formatted = "\(formattedWithoutTz) \(abbreviation)"
        self.timezone = timeZone.identifier

        // Relative format
        let now = Date()
        let interval = date.timeIntervalSince(now)
        let days = Int(interval / 86400)
        let hours = Int((interval.truncatingRemainder(dividingBy: 86400)) / 3600)

        if abs(days) == 0 {
            if abs(hours) < 1 {
                self.relative = "now"
            } else if hours > 0 {
                self.relative = "in \(hours) hour\(hours == 1 ? "" : "s")"
            } else {
                self.relative = "\(abs(hours)) hour\(abs(hours) == 1 ? "" : "s") ago"
            }
        } else if days > 0 {
            if days == 1 {
                self.relative = "tomorrow"
            } else if days < 7 {
                self.relative = "in \(days) days"
            } else if days < 14 {
                self.relative = "next week"
            } else if days < 30 {
                let weeks = days / 7
                self.relative = "in \(weeks) weeks"
            } else if days < 60 {
                self.relative = "next month"
            } else {
                let months = days / 30
                self.relative = "in \(months) months"
            }
        } else {
            if days == -1 {
                self.relative = "yesterday"
            } else if days > -7 {
                self.relative = "\(abs(days)) days ago"
            } else if days > -14 {
                self.relative = "last week"
            } else if days > -30 {
                let weeks = abs(days) / 7
                self.relative = "\(weeks) weeks ago"
            } else if days > -60 {
                self.relative = "last month"
            } else {
                let months = abs(days) / 30
                self.relative = "\(months) months ago"
            }
        }
    }
}

extension EKCalendar: @retroactive Encodable {
    private enum CalendarEncodingKeys: String, CodingKey {
        case title
        case uuid
        case allowsContentModifications
        case type
        case source
        case isPrimary
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CalendarEncodingKeys.self)
        try container.encode(self.title, forKey: .title)
        try container.encode(self.calendarIdentifier, forKey: .uuid)
        try container.encode(self.allowsContentModifications, forKey: .allowsContentModifications)
        try container.encode(self.type.rawValue, forKey: .type)
        try container.encode(self.source.title, forKey: .source)
        try container.encode(self.isImmutable ? false : true, forKey: .isPrimary)
    }
}

extension EKReminder: @retroactive Encodable {
    private enum EncodingKeys: String, CodingKey {
        case uuid
        case externalId
        case lastModified
        case creationDate
        case title
        case notes
        case url
        case location
        case locationTitle
        case completionDate
        case isCompleted
        case priority
        case _priorityValue
        case startDate
        case dueDate
        case list
        case listUUID
        case calendarItemIdentifier
        case attachedUrl
        case mailUrl
        case parentId
        case isSubtask
    }

    /// Convert EKReminderPriority to human-readable string
    private func priorityString(_ priority: Int) -> String {
        switch priority {
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

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: EncodingKeys.self)
        
        // Strip the protocol prefix from UUIDs for the API
        let externalId = self.calendarItemExternalIdentifier.replacingOccurrences(
            of: "x-apple-reminder://", 
            with: ""
        )
        
        try container.encode(externalId, forKey: .externalId)
        try container.encode(externalId, forKey: .uuid)
        try container.encode(self.calendarItemIdentifier, forKey: .calendarItemIdentifier)
        try container.encode(self.title, forKey: .title)
        try container.encode(self.isCompleted, forKey: .isCompleted)
        try container.encode(priorityString(self.priority), forKey: .priority)
        try container.encode(self.priority, forKey: ._priorityValue)
        try container.encode(self.calendar.title, forKey: .list)
        try container.encode(self.calendar.calendarIdentifier, forKey: .listUUID)
        try container.encodeIfPresent(self.notes, forKey: .notes)
        
        // url field is nil
        // https://developer.apple.com/forums/thread/128140
        try container.encodeIfPresent(self.url, forKey: .url)
        
        // Private API fields
        try container.encodeIfPresent(self.attachedUrl?.absoluteString, forKey: .attachedUrl)
        try container.encodeIfPresent(self.mailUrl?.absoluteString, forKey: .mailUrl)
        try container.encodeIfPresent(self.parentId, forKey: .parentId)
        try container.encode(self.isSubtask, forKey: .isSubtask)

        // Use structured date format for all dates
        if let completionDate = self.completionDate {
            try container.encodeIfPresent(FormattedDate(from: completionDate), forKey: .completionDate)
        }

        for alarm in self.alarms ?? [] {
            if let location = alarm.structuredLocation {
                try container.encodeIfPresent(location.title, forKey: .locationTitle)
                if let geoLocation = location.geoLocation {
                    let geo = "\(geoLocation.coordinate.latitude), \(geoLocation.coordinate.longitude)"
                    try container.encode(geo, forKey: .location)
                }
                break
            }
        }

        if let startDateComponents = self.startDateComponents {
            try container.encodeIfPresent(FormattedDate(from: startDateComponents.date), forKey: .startDate)
        }

        if let dueDateComponents = self.dueDateComponents {
            try container.encodeIfPresent(FormattedDate(from: dueDateComponents.date), forKey: .dueDate)
        }

        if let lastModifiedDate = self.lastModifiedDate {
            try container.encodeIfPresent(FormattedDate(from: lastModifiedDate), forKey: .lastModified)
        }

        if let creationDate = self.creationDate {
            try container.encodeIfPresent(FormattedDate(from: creationDate), forKey: .creationDate)
        }
    }
}
