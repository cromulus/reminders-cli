import Foundation

public enum RemindersMCPError: Error, LocalizedError {
    case listNotFound(String)
    case listAlreadyExists(String)
    case listReadOnly(String)
    case reminderNotFound(String)
    case storeFailure(String)
    case permissionDenied
    case noReminderSources
    case multipleSources([String])
    case invalidArguments(String)

    public var errorDescription: String? {
        switch self {
        case .listNotFound(let id):
            return "List not found: \(id)"
        case .listAlreadyExists(let name):
            return "List '\(name)' already exists"
        case .listReadOnly(let id):
            return "List '\(id)' is read-only and cannot be modified"
        case .reminderNotFound(let uuid):
            return "Reminder not found: \(uuid)"
        case .storeFailure(let message):
            return "Store operation failed: \(message)"
        case .permissionDenied:
            return "Reminders access denied. Grant access in System Preferences > Privacy & Security > Reminders"
        case .noReminderSources:
            return "No reminder sources available"
        case .multipleSources(let sources):
            return "Multiple reminder sources available. Specify source: \(sources.joined(separator: ", "))"
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        }
    }
}
