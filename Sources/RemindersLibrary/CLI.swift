import ArgumentParser
import Foundation

private let reminders = Reminders()

private struct ShowLists: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print the name of lists to pass to other commands")
    @Option(
        name: .shortAndLong,
        help: "format, either of 'plain' or 'json'")
    var format: OutputFormat = .plain
        
    @Flag(help: "Show list UUIDs in addition to names")
    var showUUIDs = false

    func run() throws {
        reminders.showLists(outputFormat: format, showUUIDs: showUUIDs)
    }
}

private struct ShowAll: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print all reminders")

    @Flag(help: "Show completed items only")
    var onlyCompleted = false

    @Flag(help: "Include completed items in output")
    var includeCompleted = false

    @Flag(help: "When using --due-date, also include items due before the due date")
    var includeOverdue = false
    
    @Flag(help: "Show reminder UUIDs in the output")
    var showUUIDs = false

    @Option(
        name: .shortAndLong,
        help: "Show only reminders due on this date")
    var dueDate: DateComponents?

    @Option(
        name: .shortAndLong,
        help: "format, either of 'plain' or 'json'")
    var format: OutputFormat = .plain

    func validate() throws {
        if self.onlyCompleted && self.includeCompleted {
            throw ValidationError(
                "Cannot specify both --show-completed and --only-completed")
        }
    }

    func run() throws {
        var displayOptions = DisplayOptions.incomplete
        if self.onlyCompleted {
            displayOptions = .complete
        } else if self.includeCompleted {
            displayOptions = .all
        }

        reminders.showAllReminders(
            dueOn: self.dueDate, includeOverdue: self.includeOverdue,
            displayOptions: displayOptions, outputFormat: format, showUUIDs: self.showUUIDs)
    }
}

private struct ShowSubtasks: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print all subtasks (reminders with parent reminders)")

    @Flag(help: "Show completed subtasks only")
    var onlyCompleted = false

    @Flag(help: "Include completed subtasks in output")
    var includeCompleted = false

    @Option(
        name: .shortAndLong,
        help: "format, either of 'plain' or 'json'")
    var format: OutputFormat = .plain

    func validate() throws {
        if self.onlyCompleted && self.includeCompleted {
            throw ValidationError(
                "Cannot specify both --show-completed and --only-completed")
        }
    }

    func run() throws {
        var displayOptions = DisplayOptions.incomplete
        if self.onlyCompleted {
            displayOptions = .complete
        } else if self.includeCompleted {
            displayOptions = .all
        }

        reminders.showSubtasks(displayOptions: displayOptions, outputFormat: format)
    }
}

private struct Show: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print the items on the given list")

    @Argument(
        help: "The list to print items from, see 'show-lists' for names or UUIDs",
        completion: .custom(listNameCompletion))
    var listName: String

    @Flag(help: "Show completed items only")
    var onlyCompleted = false

    @Flag(help: "Include completed items in output")
    var includeCompleted = false

    @Flag(help: "When using --due-date, also include items due before the due date")
    var includeOverdue = false
    
    @Flag(help: "Show reminder UUIDs in the output")
    var showUUIDs = false

    @Option(
        name: .shortAndLong,
        help: "Show the reminders in a specific order, one of: \(Sort.commaSeparatedCases)")
    var sort: Sort = .none

    @Option(
        name: [.customShort("o"), .long],
        help: "How the sort order should be applied, one of: \(CustomSortOrder.commaSeparatedCases)")
    var sortOrder: CustomSortOrder = .ascending

    @Option(
        name: .shortAndLong,
        help: "Show only reminders due on this date")
    var dueDate: DateComponents?

    @Option(
        name: .shortAndLong,
        help: "format, either of 'plain' or 'json'")
    var format: OutputFormat = .plain

    func validate() throws {
        if self.onlyCompleted && self.includeCompleted {
            throw ValidationError(
                "Cannot specify both --show-completed and --only-completed")
        }
    }

    func run() throws {
        var displayOptions = DisplayOptions.incomplete
        if self.onlyCompleted {
            displayOptions = .complete
        } else if self.includeCompleted {
            displayOptions = .all
        }

        try reminders.showListItems(
            withName: self.listName, dueOn: self.dueDate, includeOverdue: self.includeOverdue,
            displayOptions: displayOptions, outputFormat: format, sort: sort, sortOrder: sortOrder,
            showUUIDs: self.showUUIDs)
    }
}

private struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add a reminder to a list")

    @Argument(
        help: "The list to add to, see 'show-lists' for names or UUIDs",
        completion: .custom(listNameCompletion))
    var listName: String

    @Argument(
        parsing: .remaining,
        help: "The reminder contents")
    var reminder: [String]

    @Option(
        name: .shortAndLong,
        help: "The date the reminder is due")
    var dueDate: DateComponents?

    @Option(
        name: .shortAndLong,
        help: "The priority of the reminder")
    var priority: Priority = .none

    @Option(
        name: .shortAndLong,
        help: "format, either of 'plain' or 'json'")
    var format: OutputFormat = .plain

    @Option(
        name: .shortAndLong,
        help: "The notes to add to the reminder")
    var notes: String?
    
    @Flag(help: "Show UUID of the created reminder")
    var showUUID = false

    func run() throws {
        try reminders.addReminder(
            string: self.reminder.joined(separator: " "),
            notes: self.notes,
            toListNamed: self.listName,
            dueDateComponents: self.dueDate,
            priority: priority,
            outputFormat: format,
            showUUID: showUUID)
    }
}

private struct Complete: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Complete a reminder")

    @Argument(
        help: "The list to complete a reminder on, see 'show-lists' for names",
        completion: .custom(listNameCompletion))
    var listName: String

    @Argument(
        help: "The index or id of the reminder to delete, see 'show' for indexes")
    var index: String

    func run() throws {
        try reminders.setComplete(true, itemAtIndex: self.index, onListNamed: self.listName)
    }
}

private struct Uncomplete: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Uncomplete a reminder")

    @Argument(
        help: "The list to uncomplete a reminder on, see 'show-lists' for names",
        completion: .custom(listNameCompletion))
    var listName: String

    @Argument(
        help: "The index or id of the reminder to delete, see 'show' for indexes")
    var index: String

    func run() throws {
        try reminders.setComplete(false, itemAtIndex: self.index, onListNamed: self.listName)
    }
}

private struct Delete: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Delete a reminder")

    @Argument(
        help: "The list to delete a reminder on, see 'show-lists' for names",
        completion: .custom(listNameCompletion))
    var listName: String

    @Argument(
        help: "The index or id of the reminder to delete, see 'show' for indexes")
    var index: String

    func run() throws {
        try reminders.delete(itemAtIndex: self.index, onListNamed: self.listName)
    }
}

func listNameCompletion(_ arguments: [String]) -> [String] {
    // NOTE: A list name with ':' was separated in zsh completion, there might be more of these or
    // this might break other shells
    return reminders.getListNames().map { $0.replacingOccurrences(of: ":", with: "\\:") }
}

private struct Edit: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Edit the text of a reminder")

    @Argument(
        help: "The list to edit a reminder on, see 'show-lists' for names",
        completion: .custom(listNameCompletion))
    var listName: String

    @Argument(
        help: "The index or id of the reminder to delete, see 'show' for indexes")
    var index: String

    @Option(
        name: .shortAndLong,
        help: "The notes to set on the reminder, overwriting previous notes")
    var notes: String?

    @Argument(
        parsing: .remaining,
        help: "The new reminder contents")
    var reminder: [String] = []

    func validate() throws {
        if self.reminder.isEmpty && self.notes == nil {
            throw ValidationError("Must specify either new reminder content or new notes")
        }
    }

    func run() throws {
        let newText = self.reminder.joined(separator: " ")
        try reminders.edit(
            itemAtIndex: self.index,
            onListNamed: self.listName,
            newText: newText.isEmpty ? nil : newText,
            newNotes: self.notes
        )
    }
}


private struct NewList: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a new list")

    @Argument(
        help: "The name of the new list")
    var listName: String

    @Option(
        name: .shortAndLong,
        help: "The name of the source of the list, if all your lists use the same source it will default to that")
    var source: String?

    func run() throws {
        try reminders.newList(with: self.listName, source: self.source)
    }
}

private struct GetByUUID: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Get, complete, or delete a reminder directly by UUID")
    
    @Argument(
        help: "The UUID of the reminder to access")
    var uuid: String
    
    @Flag(name: .shortAndLong, help: "Show the reminder")
    var show = false
    
    @Flag(name: .shortAndLong, help: "Complete the reminder")
    var complete = false
    
    @Flag(name: .shortAndLong, help: "Uncomplete the reminder")
    var uncomplete = false
    
    @Flag(name: .shortAndLong, help: "Delete the reminder")
    var delete = false
    
    @Option(
        name: .shortAndLong,
        help: "format, either of 'plain' or 'json'")
    var format: OutputFormat = .plain
    
    func validate() throws {
        let actionCount = [show, complete, uncomplete, delete].filter { $0 }.count
        if actionCount == 0 {
            throw ValidationError("Must specify at least one action: --show, --complete, --uncomplete, or --delete")
        }
    }
    
    func run() throws {
        guard let reminder = reminders.getReminderByUUID(uuid) else {
            print("No reminder found with UUID \(uuid)")
            throw ValidationError("No reminder found with UUID \(uuid)")
        }
        
        if show {
            switch format {
            case .json:
                print(encodeToJson(data: reminder))
            case .plain:
                print("UUID: \(reminder.calendarItemExternalIdentifier ?? "unknown")")
                print("List: \(reminder.calendar.title) [\(reminder.calendar.calendarIdentifier)]")
                print("Title: \(reminder.title ?? "<unknown>")")
                if let notes = reminder.notes, !notes.isEmpty {
                    print("Notes: \(notes)")
                }
                print("Completed: \(reminder.isCompleted ? "Yes" : "No")")
                if let dueDate = reminder.dueDateComponents?.date {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .short
                    print("Due: \(formatter.string(from: dueDate))")
                }
                if reminder.priority > 0 {
                    let priority = Priority(reminder.mappedPriority)?.rawValue ?? "none"
                    print("Priority: \(priority)")
                }
            }
        }
        
        if complete {
            do {
                try reminders.setReminderComplete(reminder, complete: true)
                print("Completed '\(reminder.title ?? "<unknown>")'")
            } catch {
                print("Failed to complete reminder: \(error.localizedDescription)")
                throw ValidationError("Failed to complete reminder: \(error.localizedDescription)")
            }
        }
        
        if uncomplete {
            do {
                try reminders.setReminderComplete(reminder, complete: false)
                print("Uncompleted '\(reminder.title ?? "<unknown>")'")
            } catch {
                print("Failed to uncomplete reminder: \(error.localizedDescription)")
                throw ValidationError("Failed to uncomplete reminder: \(error.localizedDescription)")
            }
        }
        
        if delete {
            do {
                try reminders.deleteReminder(reminder)
                print("Deleted '\(reminder.title ?? "<unknown>")'")
            } catch {
                print("Failed to delete reminder: \(error.localizedDescription)")
                throw ValidationError("Failed to delete reminder: \(error.localizedDescription)")
            }
        }
    }
}

private struct ShowItem: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show a specific reminder by UUID or list name and index")

    @Argument(help: "UUID of the reminder, or list name if using --index")
    var identifier: String

    @Option(
        name: .shortAndLong,
        help: "Index of the reminder in the specified list")
    var index: String?

    @Option(
        name: .shortAndLong,
        help: "format, either of 'plain' or 'json'")
    var format: OutputFormat = .plain

    func validate() throws {
        // If index is provided, identifier should be a list name
        // If index is not provided, identifier should be a UUID
        if index != nil {
            // identifier is list name, index is the reminder index
        } else {
            // identifier should be a UUID format
            if identifier.count != 36 || identifier.filter({ $0 == "-" }).count != 4 {
                throw ValidationError("When not using --index, identifier must be a valid UUID")
            }
        }
    }

    func run() throws {
        if let index = index {
            // Show by list name + index
            try reminders.showItem(onListNamed: identifier, atIndex: index, outputFormat: format)
        } else {
            // Show by UUID
            try reminders.showItem(withUUID: identifier, outputFormat: format)
        }
    }
}

private struct Move: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Move a reminder from one list to another")

    @Argument(help: "Source list name")
    var sourceList: String

    @Argument(help: "Index or UUID of the reminder to move")
    var reminderIdentifier: String

    @Argument(help: "Target list name")
    var targetList: String

    func run() throws {
        try reminders.moveReminder(
            identifier: reminderIdentifier,
            fromList: sourceList,
            toList: targetList)
    }
}

private struct SetPriority: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Set the priority of a reminder")

    @Argument(help: "List name or UUID if using --uuid")
    var listOrUUID: String

    @Argument(help: "Index of the reminder (not needed if using --uuid)")
    var index: String?

    @Argument(help: "Priority level")
    var priority: Priority

    @Flag(help: "Treat first argument as UUID instead of list name")
    var uuid = false

    func run() throws {
        if uuid {
            try reminders.setPriority(priority, forReminderWithUUID: listOrUUID)
        } else {
            guard let index = index else {
                print("Index is required when not using --uuid")
                Foundation.exit(1)
            }
            try reminders.setPriority(priority, 
                                onListNamed: listOrUUID, 
                                atIndex: index)
        }
    }
}

private struct AddUrl: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add a URL attachment to a reminder")

    @Argument(help: "List name or UUID if using --uuid")
    var listOrUUID: String

    @Argument(help: "Index of the reminder (not needed if using --uuid)")
    var index: String?

    @Argument(help: "URL to attach")
    var url: String

    @Flag(help: "Treat first argument as UUID instead of list name")
    var uuid = false

    func validate() throws {
        guard URL(string: url) != nil else {
            throw ValidationError("Invalid URL format")
        }
    }

    func run() throws {
        if uuid {
            try reminders.addURL(url, toReminderWithUUID: listOrUUID)
        } else {
            guard let index = index else {
                print("Index is required when not using --uuid")
                Foundation.exit(1)
            }
            try reminders.addURL(url, 
                           onListNamed: listOrUUID, 
                           atIndex: index)
        }
    }
}

private struct MakeSubtask: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Make a reminder a subtask of another reminder")

    @Argument(help: "Child list name or UUID if using --child-uuid")
    var childListOrUUID: String

    @Argument(help: "Child index (not needed if using --child-uuid)")
    var childIndex: String?

    @Argument(help: "Parent list name or UUID if using --parent-uuid")
    var parentListOrUUID: String

    @Argument(help: "Parent index (not needed if using --parent-uuid)")
    var parentIndex: String?

    @Flag(help: "Treat child argument as UUID")
    var childUuid = false

    @Flag(help: "Treat parent argument as UUID")
    var parentUuid = false

    func run() throws {
        reminders.makeSubtask(
            childList: childUuid ? nil : childListOrUUID,
            childIndex: childUuid ? nil : childIndex,
            childUUID: childUuid ? childListOrUUID : nil,
            parentList: parentUuid ? nil : parentListOrUUID,
            parentIndex: parentUuid ? nil : parentIndex,
            parentUUID: parentUuid ? parentListOrUUID : nil)
    }
}

public struct CLI: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "reminders",
        abstract: "Interact with macOS Reminders from the command line",
        subcommands: [
            Add.self,
            Complete.self,
            Uncomplete.self,
            Delete.self,
            Edit.self,
            Show.self,
            ShowLists.self,
            ShowSubtasks.self,
            NewList.self,
            ShowAll.self,
            GetByUUID.self,
            ShowItem.self,
            Move.self,
            SetPriority.self,
            AddUrl.self,
            MakeSubtask.self,
        ]
    )

    public init() {}
}
