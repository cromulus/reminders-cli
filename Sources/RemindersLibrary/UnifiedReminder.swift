import Foundation
import EventKit

/// Unified reminder model that bridges public EventKit and private APIs
public struct UnifiedReminder: Codable {
    public let id: String
    public let title: String
    public let notes: String?
    public let dueDate: Date?
    public let isCompleted: Bool
    public let priority: Int
    public let listName: String
    public let listUUID: String
    public let creationDate: Date?
    public let completionDate: Date?
    public let lastModifiedDate: Date?
    public let url: String?
    
    // Private API specific fields
    public let isSubtask: Bool
    public let parentID: String?
    public let tags: [String]?
    public let attachments: [UnifiedAttachment]?
    public let flags: [String]?
    public let subtaskCount: Int?
    
    /// Initialize from EventKit reminder (public API)
    public init(from ekReminder: EKReminder) {
        self.id = ekReminder.calendarItemExternalIdentifier ?? ""
        self.title = ekReminder.title ?? ""
        self.notes = ekReminder.notes
        self.dueDate = ekReminder.dueDateComponents?.date
        self.isCompleted = ekReminder.isCompleted
        self.priority = ekReminder.priority
        self.listName = ekReminder.calendar.title
        self.listUUID = ekReminder.calendar.calendarIdentifier
        self.creationDate = ekReminder.creationDate
        self.completionDate = ekReminder.completionDate
        self.lastModifiedDate = ekReminder.lastModifiedDate
        self.url = ekReminder.url?.absoluteString
        
        // Private API fields are nil for EventKit reminders
        self.isSubtask = false
        self.parentID = nil
        self.tags = nil
        self.attachments = nil
        self.flags = nil
        self.subtaskCount = nil
    }
    
    #if PRIVATE_REMINDERS_ENABLED
    /// Initialize from private API reminder
    public init?(from remReminder: Any) {
        // We'll implement this when we have access to the private API classes
        // For now, fallback to EventKit initialization
        return nil
    }
    #endif
    
    /// Get formatted display string
    public func formatted(at index: Int? = nil, showUUID: Bool = false, showTags: Bool = false) -> String {
        let dateString = dueDate.map { " (\(RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date())))" } ?? ""
        let priorityString = priority > 0 ? " (priority: \(Priority(EKReminderPriority(rawValue: UInt(priority)) ?? .none)?.rawValue ?? "none"))" : ""
        let notesString = notes.map { " (\($0))" } ?? ""
        let indexString = index.map { "\($0): " } ?? ""
        let uuidString = showUUID ? " [UUID: \(id)]" : ""
        let tagString = (showTags && tags != nil && !tags!.isEmpty) ? " [Tags: \(tags!.joined(separator: ", "))]" : ""
        let subtaskIndicator = isSubtask ? "  ↳ " : ""
        let subtaskCountString = (subtaskCount ?? 0) > 0 ? " (\(subtaskCount!) subtasks)" : ""
        
        return "\(subtaskIndicator)\(indexString)\(title)\(notesString)\(dateString)\(priorityString)\(subtaskCountString)\(tagString)\(uuidString)"
    }
}

/// Attachment information from private APIs
public struct UnifiedAttachment: Codable {
    public let id: String
    public let type: String
    public let filename: String?
    public let url: String?
    public let size: Int?
}

