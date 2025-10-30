import Foundation
import EventKit
import Hummingbird

// WebhookFilter defines criteria for filtering reminders that trigger webhooks
public struct WebhookFilter: Codable {
    public var listNames: [String]?
    public var listUUIDs: [String]?
    public var completed: String?
    public var priorityLevels: [Int]?
    public var hasQuery: String?
    
    // For matching, we convert the string to DisplayOptions
    private var completedOption: DisplayOptions? {
        guard let completed = completed else { return nil }
        
        switch completed.lowercased() {
        case "all": return .all
        case "complete", "completed": return .complete
        case "incomplete": return .incomplete
        default: return nil
        }
    }
    
    public init(listNames: [String]? = nil, listUUIDs: [String]? = nil, 
                completed: DisplayOptions? = nil, priorityLevels: [Int]? = nil, 
                hasQuery: String? = nil) {
        self.listNames = listNames
        self.listUUIDs = listUUIDs
        
        // Convert DisplayOptions to String
        if let completed = completed {
            switch completed {
            case .all: self.completed = "all"
            case .complete: self.completed = "complete"
            case .incomplete: self.completed = "incomplete"
            }
        } else {
            self.completed = nil
        }
        
        self.priorityLevels = priorityLevels
        self.hasQuery = hasQuery
    }
    
    public func matches(reminder: EKReminder, remindersService: Reminders) -> Bool {
        // Match list names
        if let listNames = self.listNames, !listNames.isEmpty {
            if !listNames.contains(where: { $0.lowercased() == reminder.calendar.title.lowercased() }) {
                return false
            }
        }
        
        // Match list UUIDs
        if let listUUIDs = self.listUUIDs, !listUUIDs.isEmpty {
            if !listUUIDs.contains(reminder.calendar.calendarIdentifier) {
                return false
            }
        }
        
        // Match completion status
        if let completedOption = self.completedOption {
            if !remindersService.shouldDisplay(reminder: reminder, displayOptions: completedOption) {
                return false
            }
        }
        
        // Match priority levels
        if let priorityLevels = self.priorityLevels, !priorityLevels.isEmpty {
            if !priorityLevels.contains(reminder.priority) {
                return false
            }
        }
        
        // Match query text
        if let query = self.hasQuery, !query.isEmpty {
            if let title = reminder.title, title.localizedCaseInsensitiveContains(query) {
                return true
            }
            
            if let notes = reminder.notes, notes.localizedCaseInsensitiveContains(query) {
                return true
            }
            
            // If we have a query but didn't match title or notes, this reminder doesn't match
            return false
        }
        
        return true
    }
}

// Import Hummingbird to conform to HBResponseGenerator
#if canImport(Hummingbird)
import Hummingbird
#endif

// WebhookConfig represents a single webhook configuration
public struct WebhookConfig: Codable {
    public let id: UUID
    public let url: URL
    public let filter: WebhookFilter
    public var isActive: Bool
    public var name: String

    public init(url: URL, filter: WebhookFilter, name: String = "Untitled Webhook", isActive: Bool = true) {
        self.id = UUID()
        self.url = url
        self.filter = filter
        self.isActive = isActive
        self.name = name
    }

    // Internal initializer that preserves the UUID (for updates)
    internal init(id: UUID, url: URL, filter: WebhookFilter, name: String, isActive: Bool) {
        self.id = id
        self.url = url
        self.filter = filter
        self.isActive = isActive
        self.name = name
    }
}

// Extend WebhookConfig to conform to HBResponseGenerator
extension WebhookConfig: HBResponseGenerator {
    public func response(from request: HBRequest) throws -> HBResponse {
        let data = try JSONEncoder().encode(self)
        return HBResponse(
            status: .ok,
            headers: ["content-type": "application/json"],
            body: .byteBuffer(ByteBuffer(data: data))
        )
    }
}

// WebhookEvent describes the type of event that triggered the webhook
public enum WebhookEvent: String, Codable {
    case created
    case updated
    case deleted
    case completed
    case uncompleted
}

// WebhookPayload is the data structure sent to webhook endpoints
public struct WebhookPayload: Codable {
    public let event: WebhookEvent
    public let timestamp: String
    public let reminder: ReminderData
    
    public struct ReminderData: Codable {
        public let uuid: String
        public let title: String
        public let notes: String?
        public let dueDate: String?
        public let isCompleted: Bool
        public let priority: Int
        public let listName: String
        public let listUUID: String
        public let creationDate: String?
        public let lastModifiedDate: String?
        public let completionDate: String?
    }
    
    public init(event: WebhookEvent, reminder: EKReminder) {
        self.event = event
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        self.timestamp = formatter.string(from: Date())
        
        var dueDate: String? = nil
        if let date = reminder.dueDateComponents?.date {
            dueDate = formatter.string(from: date)
        }
        
        var creationDate: String? = nil
        if let date = reminder.creationDate {
            creationDate = formatter.string(from: date)
        }
        
        var lastModifiedDate: String? = nil
        if let date = reminder.lastModifiedDate {
            lastModifiedDate = formatter.string(from: date)
        }
        
        var completionDate: String? = nil
        if let date = reminder.completionDate {
            completionDate = formatter.string(from: date)
        }
        
        // Strip the protocol prefix from UUIDs for API use
        let uuid = reminder.calendarItemExternalIdentifier.replacingOccurrences(
            of: "x-apple-reminder://", 
            with: ""
        )
        
        self.reminder = ReminderData(
            uuid: uuid,
            title: reminder.title ?? "<unknown>",
            notes: reminder.notes,
            dueDate: dueDate,
            isCompleted: reminder.isCompleted,
            priority: reminder.priority,
            listName: reminder.calendar.title,
            listUUID: reminder.calendar.calendarIdentifier,
            creationDate: creationDate,
            lastModifiedDate: lastModifiedDate,
            completionDate: completionDate
        )
    }
}

// Class that manages webhooks, including registration, storage, and dispatching
public class WebhookManager {
    private var webhooks: [WebhookConfig] = []
    private let configURL: URL
    private let remindersService: Reminders
    private var previousReminders: [String: EKReminder] = [:]

    // Serial queue for protecting access to webhooks and previousReminders
    private let stateQueue = DispatchQueue(label: "com.reminders-cli.webhook-state")

    // Queue for webhook delivery to avoid blocking main thread
    private let webhookQueue = DispatchQueue(label: "com.reminders-cli.webhook-delivery", attributes: .concurrent)
    
    public init(remindersService: Reminders) {
        self.remindersService = remindersService
        
        // Set up configuration storage path
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let remindersDirectory = appSupportURL.appendingPathComponent("reminders-cli", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: remindersDirectory, withIntermediateDirectories: true)
        
        // Set config file path
        self.configURL = remindersDirectory.appendingPathComponent("webhooks.json")
        
        Logger.shared.debug("WebhookManager initialized with config at: \(configURL.path)")
        
        // Load existing configurations
        loadConfigurations()
        
        // Register for EventKit change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reminderStoreChanged),
            name: NSNotification.Name.EKEventStoreChanged,
            object: remindersService.store
        )
        
        Logger.shared.info("WebhookManager registered for EventKit notifications")
        
        // Initialize previous reminders state
        updatePreviousRemindersState()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Configuration Management

    public func addWebhook(url: URL, filter: WebhookFilter, name: String) -> WebhookConfig {
        return stateQueue.sync {
            let config = WebhookConfig(url: url, filter: filter, name: name)
            webhooks.append(config)
            saveConfigurations()
            Logger.shared.info("Added webhook: \(name) -> \(url)")
            return config
        }
    }

    public func updateWebhook(id: UUID, isActive: Bool? = nil, filter: WebhookFilter? = nil, url: URL? = nil, name: String? = nil) -> Bool {
        return stateQueue.sync {
            guard let index = webhooks.firstIndex(where: { $0.id == id }) else {
                Logger.shared.warn("Attempted to update non-existent webhook: \(id)")
                return false
            }

            let config = webhooks[index]
            Logger.shared.debug("Updating webhook: \(config.name)")

            // Preserve the UUID when updating by using the internal initializer
            let updatedConfig = WebhookConfig(
                id: config.id,  // Preserve original UUID
                url: url ?? config.url,
                filter: filter ?? config.filter,
                name: name ?? config.name,
                isActive: isActive ?? config.isActive
            )

            webhooks[index] = updatedConfig
            saveConfigurations()
            Logger.shared.info("Updated webhook: \(webhooks[index].name)")
            return true
        }
    }

    public func removeWebhook(id: UUID) -> Bool {
        return stateQueue.sync {
            let initialCount = webhooks.count
            if let webhook = webhooks.first(where: { $0.id == id }) {
                Logger.shared.info("Removing webhook: \(webhook.name)")
            }

            webhooks.removeAll { $0.id == id }
            let removed = initialCount != webhooks.count

            if removed {
                saveConfigurations()
                Logger.shared.debug("Webhook removed successfully")
            } else {
                Logger.shared.warn("Attempted to remove non-existent webhook: \(id)")
            }

            return removed
        }
    }

    public func getWebhooks() -> [WebhookConfig] {
        return stateQueue.sync {
            return webhooks
        }
    }

    public func getWebhook(id: UUID) -> WebhookConfig? {
        return stateQueue.sync {
            return webhooks.first { $0.id == id }
        }
    }
    
    // MARK: - EventKit Notification Handling
    
    // This is called when EventKit notifies us of changes
    @objc private func reminderStoreChanged(_ notification: Notification) {
        // Use a dispatch group to ensure synchronous execution
        let group = DispatchGroup()
        group.enter()
        
        // Fetch all reminders to check for changes
        remindersService.reminders(on: remindersService.getCalendars(), displayOptions: .all) { reminders in
            self.processChangedReminders(reminders: reminders)
            group.leave()
        }
        
        // Wait with timeout (5 seconds)
        _ = group.wait(timeout: .now() + 5)
    }
    
    private func updatePreviousRemindersState() {
        let group = DispatchGroup()
        group.enter()

        remindersService.reminders(on: remindersService.getCalendars(), displayOptions: .all) { reminders in
            self.stateQueue.sync {
                // Reset the previous state
                self.previousReminders = [:]

                // Store all current reminders by UUID for future reference
                for reminder in reminders {
                    if let uuid = reminder.calendarItemExternalIdentifier {
                        self.previousReminders[uuid] = reminder
                    }
                }
            }

            group.leave()
        }

        // Wait with timeout (5 seconds)
        _ = group.wait(timeout: .now() + 5)
    }
    
    private func processChangedReminders(reminders: [EKReminder]) {
        stateQueue.sync {
            // Current reminders mapped by UUID
            var currentReminders: [String: EKReminder] = [:]
            for reminder in reminders {
                if let uuid = reminder.calendarItemExternalIdentifier {
                    currentReminders[uuid] = reminder
                }
            }

            // Detect created, updated, deleted, completed, and uncompleted reminders
            var created: [EKReminder] = []
            var updated: [EKReminder] = []
            var deleted: [String: EKReminder] = [:]
            var completed: [EKReminder] = []
            var uncompleted: [EKReminder] = []

            // Check for created and updated reminders
            for (uuid, reminder) in currentReminders {
                if let previousReminder = previousReminders[uuid] {
                    // Check if reminder was updated
                    if reminder.lastModifiedDate != previousReminder.lastModifiedDate {
                        updated.append(reminder)

                        // Check for completion status change
                        if reminder.isCompleted && !previousReminder.isCompleted {
                            completed.append(reminder)
                        } else if !reminder.isCompleted && previousReminder.isCompleted {
                            uncompleted.append(reminder)
                        }
                    }
                } else {
                    // This is a new reminder
                    created.append(reminder)
                }
            }

            // Check for deleted reminders
            for (uuid, reminder) in previousReminders {
                if currentReminders[uuid] == nil {
                    deleted[uuid] = reminder
                }
            }

            // Dispatch webhooks for each type of event
            // Note: dispatching happens outside the critical section to avoid holding the lock

            // Handle created reminders
            for reminder in created {
                dispatchWebhooks(for: reminder, event: .created)
            }

            // Handle updated reminders
            for reminder in updated {
                dispatchWebhooks(for: reminder, event: .updated)
            }

            // Handle deleted reminders
            for (_, reminder) in deleted {
                dispatchWebhooks(for: reminder, event: .deleted)
            }

            // Handle completed reminders
            for reminder in completed {
                dispatchWebhooks(for: reminder, event: .completed)
            }

            // Handle uncompleted reminders
            for reminder in uncompleted {
                dispatchWebhooks(for: reminder, event: .uncompleted)
            }

            // Update our previous state for next comparison
            previousReminders = currentReminders
        }
    }
    
    private func dispatchWebhooks(for reminder: EKReminder, event: WebhookEvent) {
        // Get a snapshot of active webhooks (thread-safe)
        let activeWebhooks = stateQueue.sync {
            return webhooks.filter { $0.isActive }
        }

        // For each active webhook configuration
        for webhook in activeWebhooks {
            // Check if this reminder matches the webhook's filter criteria
            if webhook.filter.matches(reminder: reminder, remindersService: self.remindersService) {
                // If it matches, send the webhook
                deliverWebhook(to: webhook.url, event: event, reminder: reminder)
            }
        }
    }
    
    // MARK: - Webhook Delivery
    
    private func deliverWebhook(to url: URL, event: WebhookEvent, reminder: EKReminder) {
        // Create the payload
        let payload = WebhookPayload(event: event, reminder: reminder)
        
        // Encode the payload as JSON
        guard let payloadData = try? JSONEncoder().encode(payload) else {
            print("Error: Failed to encode webhook payload")
            return
        }
        
        // Create the HTTP request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payloadData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Send the request asynchronously
        webhookQueue.async {
            let task = URLSession.shared.dataTask(with: request) { _, _, error in
                if let error = error {
                    print("Error delivering webhook to \(url): \(error.localizedDescription)")
                }
            }
            task.resume()
        }
    }
    
    // MARK: - Configuration Persistence
    
    private func saveConfigurations() {
        // Note: This is called from within stateQueue.sync blocks, so no additional locking needed
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(webhooks)
            try data.write(to: configURL)
        } catch {
            print("Error saving webhook configurations: \(error.localizedDescription)")
        }
    }

    private func loadConfigurations() {
        stateQueue.sync {
            do {
                if FileManager.default.fileExists(atPath: configURL.path) {
                    let data = try Data(contentsOf: configURL)
                    webhooks = try JSONDecoder().decode([WebhookConfig].self, from: data)
                }
            } catch {
                print("Error loading webhook configurations: \(error.localizedDescription)")
                // Start with empty configuration if loading fails
                webhooks = []
            }
        }
    }
}