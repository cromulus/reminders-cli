import ArgumentParser
import EventKit
import Foundation

// Custom errors for Reminders operations
public enum RemindersError: Error, LocalizedError {
    case listNotFound(String)
    case reminderNotFound(String)
    case saveFailed(Error)
    case deleteFailed(Error)
    case noSources
    case sourceNotFound(String)
    case multipleSources([String])
    case invalidURL(String)
    case encodingFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .listNotFound(let name):
            return "No reminders list matching '\(name)'"
        case .reminderNotFound(let identifier):
            return "No reminder found with identifier '\(identifier)'"
        case .saveFailed(let error):
            return "Failed to save reminder: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete reminder: \(error.localizedDescription)"
        case .noSources:
            return "No existing list sources were found, please create a list in Reminders.app"
        case .sourceNotFound(let name):
            return "No source named '\(name)'"
        case .multipleSources(let sources):
            return "Multiple sources were found, please specify one with --source: \(sources.joined(separator: ", "))"
        case .invalidURL(let urlString):
            return "Invalid URL: \(urlString)"
        case .encodingFailed(let error):
            return "Failed to encode data: \(error.localizedDescription)"
        }
    }
}

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
    
    // Additional information from private APIs
    var additionalInfo: [String] = []
    
    if showUUID {
        additionalInfo.append("UUID: \(reminder.calendarItemExternalIdentifier ?? "unknown")")
    }
    
    if reminder.isSubtask {
        additionalInfo.append("subtask")
    }
    
    if let attachedUrl = reminder.attachedUrl {
        additionalInfo.append("url: \(attachedUrl.absoluteString)")
    }
    
    if let mailUrl = reminder.mailUrl {
        additionalInfo.append("mail: \(mailUrl.absoluteString)")
    }
    
    let additionalString = additionalInfo.isEmpty ? "" : " [\(additionalInfo.joined(separator: ", "))]"
    
    return "\(listString)\(indexString)\(reminder.title ?? "<unknown>")\(notesString)\(dateString)\(priorityString)\(additionalString)"
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
    public let store: EKEventStore
    
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
    
    public func calendar(withName name: String) throws -> EKCalendar {
        // First check if the name is actually a UUID
        if let calendar = self.getCalendars().find(where: { $0.calendarIdentifier == name }) {
            return calendar
        }

        // Then check by name
        if let calendar = self.getCalendars().find(where: { $0.title.lowercased() == name.lowercased() }) {
            return calendar
        } else {
            throw RemindersError.listNotFound(name)
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
    ) throws -> EKReminder {
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
        } catch {
            throw RemindersError.saveFailed(error)
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

    func showSubtasks(displayOptions: DisplayOptions, outputFormat: OutputFormat) {
        let semaphore = DispatchSemaphore(value: 0)

        self.reminders(on: self.getCalendars(), displayOptions: displayOptions) { reminders in
            let subtasks = reminders.filter { $0.isSubtask }
            
            switch outputFormat {
            case .json:
                print(encodeToJson(data: subtasks))
            case .plain:
                for (i, subtask) in subtasks.enumerated() {
                    let listName = subtask.calendar.title
                    print(format(subtask, at: i, listName: listName))
                }
            }

            semaphore.signal()
        }

        semaphore.wait()
    }

    func showListItems(withName name: String, dueOn dueDate: DateComponents?, includeOverdue: Bool,
        displayOptions: DisplayOptions, outputFormat: OutputFormat, sort: Sort, sortOrder: CustomSortOrder,
        showUUIDs: Bool = false) throws
    {
        let semaphore = DispatchSemaphore(value: 0)
        let calendar = Calendar.current

        self.reminders(on: [try self.calendar(withName: name)], displayOptions: displayOptions) { reminders in
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

    public func newList(with name: String, source requestedSourceName: String?) throws {
        let store = EKEventStore()
        let sources = store.sources
        guard var source = sources.first else {
            throw RemindersError.noSources
        }

        if let requestedSourceName = requestedSourceName {
            guard let requestedSource = sources.first(where: { $0.title == requestedSourceName }) else {
                throw RemindersError.sourceNotFound(requestedSourceName)
            }

            source = requestedSource
        } else {
            let uniqueSources = Set(sources.map { $0.title })
            if uniqueSources.count > 1 {
                throw RemindersError.multipleSources(Array(uniqueSources))
            }
        }

        let newList = EKCalendar(for: .reminder, eventStore: self.store)
        newList.title = name
        newList.source = source

        do {
            try self.store.saveCalendar(newList, commit: true)
            print("Created new list '\(newList.title)'!")
        } catch {
            throw RemindersError.saveFailed(error)
        }
    }

    func edit(itemAtIndex index: String, onListNamed name: String, newText: String?, newNotes: String?) throws {
        let calendar = try self.calendar(withName: name)
        let semaphore = DispatchSemaphore(value: 0)
        var thrownError: Error?

        self.reminders(on: [calendar], displayOptions: .incomplete) { reminders in
            do {
                guard let reminder = self.getReminder(from: reminders, at: index) else {
                    throw RemindersError.reminderNotFound("\(index) on \(name)")
                }

                reminder.title = newText ?? reminder.title
                reminder.notes = newNotes ?? reminder.notes
                try self.store.save(reminder, commit: true)
                print("Updated reminder '\(reminder.title!)'")
            } catch {
                thrownError = error
            }

            semaphore.signal()
        }

        semaphore.wait()
        if let error = thrownError {
            throw error is RemindersError ? error : RemindersError.saveFailed(error)
        }
    }

    func setComplete(_ complete: Bool, itemAtIndex index: String, onListNamed name: String) throws {
        let calendar = try self.calendar(withName: name)
        let semaphore = DispatchSemaphore(value: 0)
        let displayOptions = complete ? DisplayOptions.incomplete : .complete
        let action = complete ? "Completed" : "Uncompleted"
        var thrownError: Error?

        self.reminders(on: [calendar], displayOptions: displayOptions) { reminders in
            do {
                print(reminders.map { $0.title! })
                guard let reminder = self.getReminder(from: reminders, at: index) else {
                    throw RemindersError.reminderNotFound("\(index) on \(name)")
                }

                reminder.isCompleted = complete
                try self.store.save(reminder, commit: true)
                print("\(action) '\(reminder.title!)'")
            } catch {
                thrownError = error
            }

            semaphore.signal()
        }

        semaphore.wait()
        if let error = thrownError {
            throw error is RemindersError ? error : RemindersError.saveFailed(error)
        }
    }

    func delete(itemAtIndex index: String, onListNamed name: String) throws {
        let calendar = try self.calendar(withName: name)
        let semaphore = DispatchSemaphore(value: 0)
        var thrownError: Error?

        self.reminders(on: [calendar], displayOptions: .incomplete) { reminders in
            do {
                guard let reminder = self.getReminder(from: reminders, at: index) else {
                    throw RemindersError.reminderNotFound("\(index) on \(name)")
                }

                try self.store.remove(reminder, commit: true)
                print("Deleted '\(reminder.title!)'")
            } catch {
                thrownError = error
            }

            semaphore.signal()
        }

        semaphore.wait()
        if let error = thrownError {
            throw error is RemindersError ? error : RemindersError.deleteFailed(error)
        }
    }

    func addReminder(
        string: String,
        notes: String?,
        toListNamed name: String,
        dueDateComponents: DateComponents?,
        priority: Priority,
        outputFormat: OutputFormat,
        showUUID: Bool = false) throws
    {
        let calendar = try self.calendar(withName: name)
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
        } catch {
            throw RemindersError.saveFailed(error)
        }
    }

    func showItem(onListNamed listName: String, atIndex index: String, outputFormat: OutputFormat) throws {
        let calendar = try self.calendar(withName: listName)
        let semaphore = DispatchSemaphore(value: 0)
        var thrownError: Error?

        self.reminders(on: [calendar], displayOptions: .all) { reminders in
            do {
                guard let reminder = self.getReminder(from: reminders, at: index) else {
                    throw RemindersError.reminderNotFound("\(index) on \(listName)")
                }

                switch outputFormat {
                case .json:
                    print(encodeToJson(data: reminder))
                case .plain:
                    print(format(reminder, at: nil, listName: listName))
                }
            } catch {
                thrownError = error
            }

            semaphore.signal()
        }

        semaphore.wait()
        if let error = thrownError {
            throw error
        }
    }

    func showItem(withUUID uuid: String, outputFormat: OutputFormat) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var thrownError: Error?

        self.reminders(on: self.getCalendars(), displayOptions: .all) { reminders in
            do {
                guard let reminder = reminders.first(where: { $0.calendarItemExternalIdentifier == uuid }) else {
                    throw RemindersError.reminderNotFound(uuid)
                }

                switch outputFormat {
                case .json:
                    print(encodeToJson(data: reminder))
                case .plain:
                    print(format(reminder, at: nil, listName: reminder.calendar.title))
                }
            } catch {
                thrownError = error
            }

            semaphore.signal()
        }

        semaphore.wait()
        if let error = thrownError {
            throw error
        }
    }

    func moveReminder(identifier: String, fromList sourceListName: String, toList targetListName: String) throws {
        let sourceCalendar = try self.calendar(withName: sourceListName)
        let targetCalendar = try self.calendar(withName: targetListName)
        let semaphore = DispatchSemaphore(value: 0)
        var thrownError: Error?

        self.reminders(on: [sourceCalendar], displayOptions: .all) { reminders in
            do {
                guard let reminder = self.getReminder(from: reminders, at: identifier) else {
                    throw RemindersError.reminderNotFound("\(identifier) on \(sourceListName)")
                }

                reminder.calendar = targetCalendar
                try self.store.save(reminder, commit: true)
                print("Moved '\(reminder.title ?? "")' from '\(sourceListName)' to '\(targetListName)'")
            } catch {
                thrownError = error
            }

            semaphore.signal()
        }

        semaphore.wait()
        if let error = thrownError {
            throw error is RemindersError ? error : RemindersError.saveFailed(error)
        }
    }

    func setPriority(_ priority: Priority, onListNamed listName: String, atIndex index: String) throws {
        let calendar = try self.calendar(withName: listName)
        let semaphore = DispatchSemaphore(value: 0)
        var thrownError: Error?

        self.reminders(on: [calendar], displayOptions: .all) { reminders in
            do {
                guard let reminder = self.getReminder(from: reminders, at: index) else {
                    throw RemindersError.reminderNotFound("\(index) on \(listName)")
                }

                reminder.priority = Int(priority.value.rawValue)
                try self.store.save(reminder, commit: true)
                print("Set priority of '\(reminder.title ?? "")' to \(priority)")
            } catch {
                thrownError = error
            }

            semaphore.signal()
        }

        semaphore.wait()
        if let error = thrownError {
            throw error is RemindersError ? error : RemindersError.saveFailed(error)
        }
    }

    func setPriority(_ priority: Priority, forReminderWithUUID uuid: String) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var thrownError: Error?

        self.reminders(on: self.getCalendars(), displayOptions: .all) { reminders in
            do {
                guard let reminder = reminders.first(where: { $0.calendarItemExternalIdentifier == uuid }) else {
                    throw RemindersError.reminderNotFound(uuid)
                }

                reminder.priority = Int(priority.value.rawValue)
                try self.store.save(reminder, commit: true)
                print("Set priority of '\(reminder.title ?? "")' to \(priority)")
            } catch {
                thrownError = error
            }

            semaphore.signal()
        }

        semaphore.wait()
        if let error = thrownError {
            throw error is RemindersError ? error : RemindersError.saveFailed(error)
        }
    }

    func addURL(_ urlString: String, onListNamed listName: String, atIndex index: String) throws {
        guard let url = URL(string: urlString) else {
            throw RemindersError.invalidURL(urlString)
        }

        let calendar = try self.calendar(withName: listName)
        let semaphore = DispatchSemaphore(value: 0)
        var thrownError: Error?

        self.reminders(on: [calendar], displayOptions: .all) { reminders in
            do {
                guard let reminder = self.getReminder(from: reminders, at: index) else {
                    throw RemindersError.reminderNotFound("\(index) on \(listName)")
                }

                // Note: EventKit doesn't provide a public API to add URL attachments
                // This would require using private APIs similar to what we do for reading
                print("Warning: Adding URL attachments requires private APIs that may not be stable")
                print("URL to attach: \(url.absoluteString)")
                print("This feature is not yet implemented due to EventKit limitations")
            } catch {
                thrownError = error
            }

            semaphore.signal()
        }

        semaphore.wait()
        if let error = thrownError {
            throw error
        }
    }

    func addURL(_ urlString: String, toReminderWithUUID uuid: String) throws {
        guard let url = URL(string: urlString) else {
            throw RemindersError.invalidURL(urlString)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var thrownError: Error?

        self.reminders(on: self.getCalendars(), displayOptions: .all) { reminders in
            do {
                guard let reminder = reminders.first(where: { $0.calendarItemExternalIdentifier == uuid }) else {
                    throw RemindersError.reminderNotFound(uuid)
                }

                // Note: EventKit doesn't provide a public API to add URL attachments
                print("Warning: Adding URL attachments requires private APIs that may not be stable")
                print("URL to attach: \(url.absoluteString)")
                print("This feature is not yet implemented due to EventKit limitations")
            } catch {
                thrownError = error
            }

            semaphore.signal()
        }

        semaphore.wait()
        if let error = thrownError {
            throw error
        }
    }

    func makeSubtask(childList: String?, childIndex: String?, childUUID: String?,
                    parentList: String?, parentIndex: String?, parentUUID: String?) {
        // Note: EventKit doesn't provide a public API to create subtask relationships
        print("Warning: Creating subtask relationships requires private APIs that may not be stable")
        print("This feature is not yet implemented due to EventKit limitations")
        
        if let childUUID = childUUID {
            print("Child UUID: \(childUUID)")
        } else if let childList = childList, let childIndex = childIndex {
            print("Child: \(childList)[\(childIndex)]")
        }
        
        if let parentUUID = parentUUID {
            print("Parent UUID: \(parentUUID)")
        } else if let parentList = parentList, let parentIndex = parentIndex {
            print("Parent: \(parentList)[\(parentIndex)]")
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
        let prefix = "x-apple-reminder://"
        let fullUUID = indexOrUUID.hasPrefix(prefix) ? indexOrUUID : "\(prefix)\(indexOrUUID)"
        
        // Try with calendarItemExternalIdentifier
        if let reminder = reminders.first(where: { $0.calendarItemExternalIdentifier == fullUUID }) {
            return reminder
        }
        
        // For backward compatibility, try with the original string too
        if let reminder = reminders.first(where: { $0.calendarItemExternalIdentifier == indexOrUUID }) {
            return reminder
        }
        
        // Try with calendarItemIdentifier
        return reminders.first(where: { $0.calendarItemIdentifier == indexOrUUID })
    }
    
    // Function to get a reminder by UUID directly from the store
    public func getReminderByUUID(_ uuid: String) -> EKReminder? {
        // Handle both formats (with and without the protocol prefix)
        let prefix = "x-apple-reminder://"
        let fullUUID = uuid.hasPrefix(prefix) ? uuid : "\(prefix)\(uuid)"
        
        // Try to get it directly if we can
        if let reminder = self.store.calendarItem(withIdentifier: fullUUID) as? EKReminder {
            return reminder
        }
        
        // For backward compatibility, try with the original string too
        if let reminder = self.store.calendarItem(withIdentifier: uuid) as? EKReminder {
            return reminder
        }
        
        // If that fails, search through all calendars
        var foundReminder: EKReminder? = nil
        let semaphore = DispatchSemaphore(value: 0)
        
        self.reminders(on: self.getCalendars(), displayOptions: .all) { reminders in
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
            // Fall back to standard encoding if JSONSerialization fails
            fputs("Warning: JSONSerialization failed, falling back to JSONEncoder: \(error.localizedDescription)\n", stderr)
        }
    }

    do {
        let encoded = try encoder.encode(data)
        return String(data: encoded, encoding: .utf8) ?? ""
    } catch {
        // If encoding fails, return an error JSON object
        fputs("Error: Failed to encode data to JSON: \(error.localizedDescription)\n", stderr)
        return "{\"error\": \"Failed to encode data to JSON\"}"
    }
}
