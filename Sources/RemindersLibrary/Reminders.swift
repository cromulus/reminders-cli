import ArgumentParser
import EventKit
import Foundation

public let sharedEventStore = EKEventStore()
private let dateFormatter = RelativeDateTimeFormatter()
private func formattedDueDate(from reminder: EKReminder) -> String? {
    return reminder.dueDateComponents?.date.map {
        dateFormatter.localizedString(for: $0, relativeTo: Date())
    }
}

extension EKReminder {
    var mappedPriority: EKReminderPriority {
        UInt(exactly: self.priority).flatMap(EKReminderPriority.init) ?? EKReminderPriority.none
    }
}

private func format(_ reminder: EKReminder, at index: Int?, listName: String? = nil, showUUID: Bool = false) -> String {
    let dateString = formattedDueDate(from: reminder).map { " (\($0))" } ?? ""
    let priorityString = Priority(reminder.mappedPriority).map { " (priority: \($0))" } ?? ""
    let listString = listName.map { "\($0): " } ?? ""
    let notesString = reminder.notes.map { " (\($0))" } ?? ""
    let indexString = index.map { "\($0): " } ?? ""
    let uuidString = showUUID ? " [UUID: \(reminder.calendarItemExternalIdentifier ?? "unknown")]" : ""
    return "\(listString)\(indexString)\(reminder.title ?? "<unknown>")\(notesString)\(dateString)\(priorityString)\(uuidString)"
}

public enum OutputFormat: String, ExpressibleByArgument {
    case json, plain
}

public enum DisplayOptions: String, Decodable {
    case all
    case incomplete
    case complete
}

public enum Priority: String, ExpressibleByArgument {
    case none
    case low
    case medium
    case high

    public var value: EKReminderPriority {
        switch self {
            case .none: return .none
            case .low: return .low
            case .medium: return .medium
            case .high: return .high
        }
    }

    init?(_ priority: EKReminderPriority) {
        switch priority {
            case .none: return nil
            case .low: self = .low
            case .medium: self = .medium
            case .high: self = .high
        @unknown default:
            return nil
        }
    }
}

public final class Reminders {
    let store: EKEventStore
    
    public init(store: EKEventStore = sharedEventStore) {
        self.store = store
    }
    
    public static func requestAccess() -> (Bool, Error?) {
        let semaphore = DispatchSemaphore(value: 0)
        var grantedAccess = false
        var returnError: Error? = nil
        if #available(macOS 14.0, *) {
            sharedEventStore.requestFullAccessToReminders { granted, error in
                grantedAccess = granted
                returnError = error
                semaphore.signal()
            }
        } else {
            sharedEventStore.requestAccess(to: .reminder) { granted, error in
                grantedAccess = granted
                returnError = error
                semaphore.signal()
            }
        }

        semaphore.wait()
        return (grantedAccess, returnError)
    }

    public func getListNames() -> [String] {
        return self.getCalendars().map { $0.title }
    }
    
    // Make getCalendars and calendar(withName:) public for API access
    public func getCalendars() -> [EKCalendar] {
        return store.calendars(for: .reminder)
                    .filter { $0.allowsContentModifications }
    }
    
    public func calendar(withName name: String) -> EKCalendar {
        // First check if the name is actually a UUID
        if let calendar = self.getCalendars().find(where: { $0.calendarIdentifier == name }) {
            return calendar
        }
        
        // Then check by name
        if let calendar = self.getCalendars().find(where: { $0.title.lowercased() == name.lowercased() }) {
            return calendar
        } else {
            print("No reminders list matching \(name)")
            exit(1)
        }
    }
    
    public func calendar(withUUID uuid: String) -> EKCalendar? {
        return self.getCalendars().find(where: { $0.calendarIdentifier == uuid })
    }
    
    // Make reminders function public and allow passing custom calendars
    public func reminders(
        on calendars: [EKCalendar],
        displayOptions: DisplayOptions,
        completion: @escaping (_ reminders: [EKReminder]) -> Void)
    {
        let predicate = store.predicateForReminders(in: calendars)
        store.fetchReminders(matching: predicate) { reminders in
            let reminders = reminders?
                .filter { reminder in
                    switch displayOptions {
                    case .all:
                        return true
                    case .incomplete:
                        return !reminder.isCompleted
                    case .complete:
                        return reminder.isCompleted
                    }
                }
            completion(reminders ?? [])
        }
    }
    
    // Helper function for filtering reminders based on display options
    public func shouldDisplay(reminder: EKReminder, displayOptions: DisplayOptions) -> Bool {
        switch displayOptions {
        case .all:
            return true
        case .incomplete:
            return !reminder.isCompleted
        case .complete:
            return reminder.isCompleted
        }
    }
    
    // Add functions for creating, deleting, and updating reminders for API
    public func createReminder(
        title: String,
        notes: String?,
        calendar: EKCalendar,
        dueDateComponents: DateComponents?,
        priority: Priority
    ) -> EKReminder {
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = title
        reminder.notes = notes
        reminder.dueDateComponents = dueDateComponents
        reminder.priority = Int(priority.value.rawValue)
        if let dueDate = dueDateComponents?.date, dueDateComponents?.hour != nil {
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        }
        
        do {
            try store.save(reminder, commit: true)
            return reminder
        } catch let error {
            print("Failed to save reminder with error: \(error)")
            exit(1)
        }
    }
    
    public func deleteReminder(_ reminder: EKReminder) throws {
        try store.remove(reminder, commit: true)
    }
    
    public func setReminderComplete(_ reminder: EKReminder, complete: Bool) throws {
        reminder.isCompleted = complete
        try store.save(reminder, commit: true)
    }
    
    public func updateReminder(_ reminder: EKReminder) throws {
        try store.save(reminder, commit: true)
    }

    func showLists(outputFormat: OutputFormat, showUUIDs: Bool = false) {
        switch (outputFormat) {
        case .json:
            print(encodeToJson(data: self.getCalendars()))
        default:
            for calendar in self.getCalendars() {
                if showUUIDs {
                    print("\(calendar.title) [\(calendar.calendarIdentifier)]")
                } else {
                    print(calendar.title)
                }
            }
        }
    }

    func showAllReminders(dueOn dueDate: DateComponents?, includeOverdue: Bool,
        displayOptions: DisplayOptions, outputFormat: OutputFormat, showUUIDs: Bool = false
    ) {
        let semaphore = DispatchSemaphore(value: 0)
        let calendar = Calendar.current

        self.reminders(on: self.getCalendars(), displayOptions: displayOptions) { reminders in
            var matchingReminders = [(EKReminder, Int, String)]()
            for (i, reminder) in reminders.enumerated() {
                let listName = reminder.calendar.title
                guard let dueDate = dueDate?.date else {
                    matchingReminders.append((reminder, i, listName))
                    continue
                }

                guard let reminderDueDate = reminder.dueDateComponents?.date else {
                    continue
                }

                let sameDay = calendar.compare(
                    reminderDueDate, to: dueDate, toGranularity: .day) == .orderedSame
                let earlierDay = calendar.compare(
                    reminderDueDate, to: dueDate, toGranularity: .day) == .orderedAscending

                if sameDay || (includeOverdue && earlierDay) {
                    matchingReminders.append((reminder, i, listName))
                }
            }

            switch outputFormat {
            case .json:
                print(encodeToJson(data: matchingReminders.map { $0.0 }))
            case .plain:
                for (reminder, i, listName) in matchingReminders {
                    print(format(reminder, at: i, listName: listName, showUUID: showUUIDs))
                }
            }

            semaphore.signal()
        }

        semaphore.wait()
    }

    func showListItems(withName name: String, dueOn dueDate: DateComponents?, includeOverdue: Bool,
        displayOptions: DisplayOptions, outputFormat: OutputFormat, sort: Sort, sortOrder: CustomSortOrder,
        showUUIDs: Bool = false)
    {
        let semaphore = DispatchSemaphore(value: 0)
        let calendar = Calendar.current

        self.reminders(on: [self.calendar(withName: name)], displayOptions: displayOptions) { reminders in
            var matchingReminders = [(EKReminder, Int?)]()
            let reminders = sort == .none ? reminders : reminders.sorted(by: sort.sortFunction(order: sortOrder))
            for (i, reminder) in reminders.enumerated() {
                let index = sort == .none ? i : nil
                guard let dueDate = dueDate?.date else {
                    matchingReminders.append((reminder, index))
                    continue
                }

                guard let reminderDueDate = reminder.dueDateComponents?.date else {
                    continue
                }

                let sameDay = calendar.compare(
                    reminderDueDate, to: dueDate, toGranularity: .day) == .orderedSame
                let earlierDay = calendar.compare(
                    reminderDueDate, to: dueDate, toGranularity: .day) == .orderedAscending

                if sameDay || (includeOverdue && earlierDay) {
                    matchingReminders.append((reminder, index))
                }
            }

            switch outputFormat {
            case .json:
                print(encodeToJson(data: matchingReminders.map { $0.0 }))
            case .plain:
                for (reminder, i) in matchingReminders {
                    print(format(reminder, at: i, showUUID: showUUIDs))
                }
            }

            semaphore.signal()
        }

        semaphore.wait()
    }

    func newList(with name: String, source requestedSourceName: String?) {
        let store = EKEventStore()
        let sources = store.sources
        guard var source = sources.first else {
            print("No existing list sources were found, please create a list in Reminders.app")
            exit(1)
        }

        if let requestedSourceName = requestedSourceName {
            guard let requestedSource = sources.first(where: { $0.title == requestedSourceName }) else
            {
                print("No source named '\(requestedSourceName)'")
                exit(1)
            }

            source = requestedSource
        } else {
            let uniqueSources = Set(sources.map { $0.title })
            if uniqueSources.count > 1 {
                print("Multiple sources were found, please specify one with --source:")
                for source in uniqueSources {
                    print("  \(source)")
                }

                exit(1)
            }
        }

        let newList = EKCalendar(for: .reminder, eventStore: self.store)
        newList.title = name
        newList.source = source

        do {
            try self.store.saveCalendar(newList, commit: true)
            print("Created new list '\(newList.title)'!")
        } catch let error {
            print("Failed create new list with error: \(error)")
            exit(1)
        }
    }

    func edit(itemAtIndex index: String, onListNamed name: String, newText: String?, newNotes: String?) {
        let calendar = self.calendar(withName: name)
        let semaphore = DispatchSemaphore(value: 0)

        self.reminders(on: [calendar], displayOptions: .incomplete) { reminders in
            guard let reminder = self.getReminder(from: reminders, at: index) else {
                print("No reminder at index \(index) on \(name)")
                exit(1)
            }

            do {
                reminder.title = newText ?? reminder.title
                reminder.notes = newNotes ?? reminder.notes
                try self.store.save(reminder, commit: true)
                print("Updated reminder '\(reminder.title!)'")
            } catch let error {
                print("Failed to update reminder with error: \(error)")
                exit(1)
            }

            semaphore.signal()
        }

        semaphore.wait()
    }

    func setComplete(_ complete: Bool, itemAtIndex index: String, onListNamed name: String) {
        let calendar = self.calendar(withName: name)
        let semaphore = DispatchSemaphore(value: 0)
        let displayOptions = complete ? DisplayOptions.incomplete : .complete
        let action = complete ? "Completed" : "Uncompleted"

        self.reminders(on: [calendar], displayOptions: displayOptions) { reminders in
            print(reminders.map { $0.title! })
            guard let reminder = self.getReminder(from: reminders, at: index) else {
                print("No reminder at index \(index) on \(name)")
                exit(1)
            }

            do {
                reminder.isCompleted = complete
                try self.store.save(reminder, commit: true)
                print("\(action) '\(reminder.title!)'")
            } catch let error {
                print("Failed to save reminder with error: \(error)")
                exit(1)
            }

            semaphore.signal()
        }

        semaphore.wait()
    }

    func delete(itemAtIndex index: String, onListNamed name: String) {
        let calendar = self.calendar(withName: name)
        let semaphore = DispatchSemaphore(value: 0)

        self.reminders(on: [calendar], displayOptions: .incomplete) { reminders in
            guard let reminder = self.getReminder(from: reminders, at: index) else {
                print("No reminder at index \(index) on \(name)")
                exit(1)
            }

            do {
                try self.store.remove(reminder, commit: true)
                print("Deleted '\(reminder.title!)'")
            } catch let error {
                print("Failed to delete reminder with error: \(error)")
                exit(1)
            }

            semaphore.signal()
        }

        semaphore.wait()
    }

    func addReminder(
        string: String,
        notes: String?,
        toListNamed name: String,
        dueDateComponents: DateComponents?,
        priority: Priority,
        outputFormat: OutputFormat,
        showUUID: Bool = false)
    {
        let calendar = self.calendar(withName: name)
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = string
        reminder.notes = notes
        reminder.dueDateComponents = dueDateComponents
        reminder.priority = Int(priority.value.rawValue)
        if let dueDate = dueDateComponents?.date, dueDateComponents?.hour != nil {
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        }

        do {
            try store.save(reminder, commit: true)
            switch (outputFormat) {
            case .json:
                // Always include UUID in the JSON output
                print(encodeToJson(data: reminder))
            default:
                // Always show UUID after creating a reminder for easy reference
                let uuid = reminder.calendarItemExternalIdentifier ?? "unknown"
                print("Added '\(reminder.title!)' to '\(calendar.title)'")
                print("UUID: \(uuid)")
                print("You can access this reminder directly with: reminders get-by-uuid \(uuid) --show")
            }
        } catch let error {
            print("Failed to save reminder with error: \(error)")
            exit(1)
        }
    }

    // MARK: - Private functions

    func getReminder(from reminders: [EKReminder], at indexOrUUID: String) -> EKReminder? {
        precondition(!indexOrUUID.isEmpty, "Index/UUID cannot be empty, argument parser must be misconfigured")
        
        // First check if it's a numeric index
        if let index = Int(indexOrUUID) {
            return reminders[safe: index]
        } 
        
        // If not numeric, check if it's a UUID
        // Try with calendarItemExternalIdentifier (the one that starts with x-apple-reminder://)
        if let reminder = reminders.first(where: { $0.calendarItemExternalIdentifier == indexOrUUID }) {
            return reminder
        }
        
        // Try with calendarItemIdentifier
        return reminders.first(where: { $0.calendarItemIdentifier == indexOrUUID })
    }
    
    // Function to get a reminder by UUID directly from the store
    public func getReminderByUUID(_ uuid: String) -> EKReminder? {
        // Try to get it directly if we can
        if let reminder = store.calendarItem(withIdentifier: uuid) as? EKReminder {
            return reminder
        }
        
        // If that fails, search through all calendars
        var foundReminder: EKReminder? = nil
        let semaphore = DispatchSemaphore(value: 0)
        
        reminders(on: getCalendars(), displayOptions: .all) { reminders in
            foundReminder = reminders.first(where: { 
                $0.calendarItemExternalIdentifier == uuid || $0.calendarItemIdentifier == uuid
            })
            semaphore.signal()
        }
        
        semaphore.wait()
        return foundReminder
    }

}

public func encodeToJson(data: Encodable) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    
    // If we're encoding directly an array of reminders, ensure UUIDs are included
    if let reminders = data as? [EKReminder] {
        let reminderDicts = reminders.map { reminder -> [String: Any] in
            var dict: [String: Any] = [
                "uuid": reminder.calendarItemExternalIdentifier ?? "",
                "title": reminder.title ?? "",
                "isCompleted": reminder.isCompleted,
                "priority": reminder.priority,
                "list": reminder.calendar.title,
                "listUUID": reminder.calendar.calendarIdentifier
            ]
            
            if let notes = reminder.notes { dict["notes"] = notes }
            if let url = reminder.url?.absoluteString { dict["url"] = url }
            if let date = reminder.dueDateComponents?.date?.description { dict["dueDate"] = date }
            if let date = reminder.completionDate?.description { dict["completionDate"] = date }
            if let date = reminder.creationDate?.description { dict["creationDate"] = date }
            if let date = reminder.lastModifiedDate?.description { dict["lastModifiedDate"] = date }
            
            return dict
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: reminderDicts, options: [.prettyPrinted, .sortedKeys])
            return String(data: jsonData, encoding: .utf8) ?? ""
        } catch {
            // Fall back to standard encoding
        }
    }
    
    let encoded = try! encoder.encode(data)
    return String(data: encoded, encoding: .utf8) ?? ""
}
