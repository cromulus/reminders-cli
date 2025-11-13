import EventKit
import Foundation
import CoreLocation

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

private struct EncodedRecurrenceEnd: Encodable {
    let type: String
    let value: String?
}

private struct EncodedRecurrence: Encodable {
    let frequency: String
    let interval: Int
    let daysOfWeek: [String]?
    let dayOfMonth: Int?
    let end: EncodedRecurrenceEnd
    let summary: String
}

private struct EncodedAlarmLocation: Encodable {
    let title: String
    let latitude: Double?
    let longitude: Double?
    let radius: Double?
}

private struct EncodedAlarm: Encodable {
    let kind: String
    let absoluteDate: FormattedDate?
    let relativeOffsetMinutes: Double?
    let location: EncodedAlarmLocation?
    let proximity: String?
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
        case alarms
        case recurrence
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

        if let rule = self.recurrenceRules?.first,
           let recurrence = buildRecurrenceDescription(from: rule) {
            try container.encode(recurrence, forKey: .recurrence)
        }

        if let alarms = encodeAlarms(self.alarms), !alarms.isEmpty {
            try container.encode(alarms, forKey: .alarms)
        }

        if let lastModifiedDate = self.lastModifiedDate {
            try container.encodeIfPresent(FormattedDate(from: lastModifiedDate), forKey: .lastModified)
        }

        if let creationDate = self.creationDate {
            try container.encodeIfPresent(FormattedDate(from: creationDate), forKey: .creationDate)
        }
    }

    private func buildRecurrenceDescription(from rule: EKRecurrenceRule) -> EncodedRecurrence? {
        let interval = max(rule.interval, 1)
        let frequencyString = recurrenceFrequencyString(rule.frequency)
        let days = rule.daysOfTheWeek?.compactMap { weekdayString(for: $0.dayOfTheWeek.rawValue) }
        let dayOfMonth = rule.daysOfTheMonth?.first?.intValue
        let encodedEnd = encodeRecurrenceEnd(rule.recurrenceEnd)
        let summary = summarizeRecurrence(
            frequency: rule.frequency,
            interval: interval,
            daysOfWeek: days,
            dayOfMonth: dayOfMonth,
            rawEnd: rule.recurrenceEnd
        )

        return EncodedRecurrence(
            frequency: frequencyString,
            interval: interval,
            daysOfWeek: days,
            dayOfMonth: dayOfMonth,
            end: encodedEnd,
            summary: summary
        )
    }

    private func recurrenceFrequencyString(_ frequency: EKRecurrenceFrequency) -> String {
        switch frequency {
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        case .yearly: return "yearly"
        @unknown default: return "custom"
        }
    }

    private func weekdayString(for rawValue: Int) -> String? {
        guard let weekday = EKWeekday(rawValue: rawValue) else { return nil }
        switch weekday {
        case .sunday: return "sunday"
        case .monday: return "monday"
        case .tuesday: return "tuesday"
        case .wednesday: return "wednesday"
        case .thursday: return "thursday"
        case .friday: return "friday"
        case .saturday: return "saturday"
        @unknown default: return nil
        }
    }

    private func encodeRecurrenceEnd(_ end: EKRecurrenceEnd?) -> EncodedRecurrenceEnd {
        guard let end = end else {
            return EncodedRecurrenceEnd(type: "never", value: nil)
        }

        if end.occurrenceCount > 0 {
            return EncodedRecurrenceEnd(type: "count", value: String(end.occurrenceCount))
        }

        if let date = end.endDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return EncodedRecurrenceEnd(type: "date", value: formatter.string(from: date))
        }

        return EncodedRecurrenceEnd(type: "never", value: nil)
    }

    private func summarizeRecurrence(
        frequency: EKRecurrenceFrequency,
        interval: Int,
        daysOfWeek: [String]?,
        dayOfMonth: Int?,
        rawEnd: EKRecurrenceEnd?
    ) -> String {
        var parts: [String] = []
        let everyPrefix = interval == 1 ? "Every" : "Every \(interval)"

        switch frequency {
        case .daily:
            parts.append("\(everyPrefix) day" + (interval == 1 ? "" : "s"))
        case .weekly:
            parts.append("\(everyPrefix) week" + (interval == 1 ? "" : "s"))
            if let days = daysOfWeek, !days.isEmpty {
                let prettyDays = days.map { $0.prefix(1).uppercased() + $0.dropFirst() }
                parts.append("on " + prettyDays.joined(separator: ", "))
            }
        case .monthly:
            parts.append("\(everyPrefix) month" + (interval == 1 ? "" : "s"))
            if let day = dayOfMonth {
                parts.append("on day \(day)")
            }
        case .yearly:
            parts.append("\(everyPrefix) year" + (interval == 1 ? "" : "s"))
        @unknown default:
            parts.append("Custom cadence")
        }

        if let end = rawEnd {
            if end.occurrenceCount > 0 {
                let count = end.occurrenceCount
                parts.append("for \(count) occurrence\(count == 1 ? "" : "s")")
            } else if let endDate = end.endDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                parts.append("until \(formatter.string(from: endDate))")
            }
        }

        return parts.joined(separator: ", ")
    }

    private func encodeAlarms(_ alarms: [EKAlarm]?) -> [EncodedAlarm]? {
        guard let alarms, !alarms.isEmpty else { return nil }
        var encoded: [EncodedAlarm] = []
        for alarm in alarms {
            if let structured = alarm.structuredLocation {
                let geo = structured.geoLocation
                let location = EncodedAlarmLocation(
                    title: structured.title ?? "",
                    latitude: geo?.coordinate.latitude,
                    longitude: geo?.coordinate.longitude,
                    radius: structured.radius
                )
                encoded.append(
                    EncodedAlarm(
                        kind: "location",
                        absoluteDate: nil,
                        relativeOffsetMinutes: nil,
                        location: location,
                        proximity: encodeProximity(alarm.proximity)
                    )
                )
            } else if let absolute = alarm.absoluteDate, let formatted = FormattedDate(from: absolute) {
                encoded.append(
                    EncodedAlarm(
                        kind: "time",
                        absoluteDate: formatted,
                        relativeOffsetMinutes: nil,
                        location: nil,
                        proximity: nil
                    )
                )
            } else if alarm.relativeOffset != 0 {
                encoded.append(
                    EncodedAlarm(
                        kind: "time",
                        absoluteDate: nil,
                        relativeOffsetMinutes: alarm.relativeOffset / 60.0,
                        location: nil,
                        proximity: nil
                    )
                )
            }
        }
        return encoded.isEmpty ? nil : encoded
    }

    private func encodeProximity(_ value: EKAlarmProximity) -> String? {
        switch value {
        case .enter:
            return "arrival"
        case .leave:
            return "departure"
        case .none:
            return "any"
        @unknown default:
            return nil
        }
    }
}
