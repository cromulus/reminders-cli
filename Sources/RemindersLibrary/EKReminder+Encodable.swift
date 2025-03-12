import EventKit

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
        case startDate
        case dueDate
        case list
        case listUUID
        case calendarItemIdentifier
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
        try container.encode(self.priority, forKey: .priority)
        try container.encode(self.calendar.title, forKey: .list)
        try container.encode(self.calendar.calendarIdentifier, forKey: .listUUID)
        try container.encodeIfPresent(self.notes, forKey: .notes)
        
        // url field is nil
        // https://developer.apple.com/forums/thread/128140
        try container.encodeIfPresent(self.url, forKey: .url)
        try container.encodeIfPresent(format(self.completionDate), forKey: .completionDate)

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
            try container.encodeIfPresent(format(startDateComponents.date), forKey: .startDate)
        }

        if let dueDateComponents = self.dueDateComponents {
            try container.encodeIfPresent(format(dueDateComponents.date), forKey: .dueDate)
        }
        
        if let lastModifiedDate = self.lastModifiedDate {
            try container.encode(format(lastModifiedDate), forKey: .lastModified)
        }
        
        if let creationDate = self.creationDate {
            try container.encode(format(creationDate), forKey: .creationDate)
        }
    }
    
    private func format(_ date: Date?) -> String? {
        if #available(macOS 12.0, *) {
            return date?.ISO8601Format()
        } else {
            return date?.description(with: .current)
        }
    }
}
