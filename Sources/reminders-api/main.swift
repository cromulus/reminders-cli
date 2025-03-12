import Darwin
import Hummingbird
import HummingbirdFoundation
import RemindersLibrary
import Foundation
import EventKit
import ArgumentParser

// MARK: - Configuration

struct Configuration: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "reminders-api",
        abstract: "Run a REST API server for macOS Reminders",
        discussion: "Provides HTTP API access to your macOS Reminders data."
    )
    
    @Option(name: [.customLong("host")], help: "The hostname to bind to")
    var hostname: String = "127.0.0.1"
    
    @Option(name: [.customShort("p"), .customLong("port")], help: "The port to listen on")
    var port: Int = 8080
    
    @Option(name: [.customLong("token")], help: "API authentication token (overrides REMINDERS_API_TOKEN environment variable)")
    var token: String?
    
    @Flag(name: [.customLong("auth-required")], help: "Require authentication for all API endpoints")
    var requireAuth = false
    
    @Flag(name: [.customLong("generate-token")], help: "Generate a new API token and exit")
    var generateToken = false
    
    func run() throws {
        // Handle token generation mode
        if generateToken {
            let authManager = AuthManager()
            let token = authManager.generateToken()
            print("Generated API token: \(token)")
            print("Use this token as the REMINDERS_API_TOKEN environment variable or --token option")
            print("Example: REMINDERS_API_TOKEN=\(token) reminders-api")
            print("Example: reminders-api --token \(token)")
            Foundation.exit(0)
        }
        
        // Set up the API token, with precedence:
        // 1. Command line argument
        // 2. Environment variable
        let apiToken = token ?? ProcessInfo.processInfo.environment["REMINDERS_API_TOKEN"]
        
        // Check if reminders access is granted before starting server
        switch Reminders.requestAccess() {
        case (true, _):
            print("Reminders access granted. Starting API server...")
            startServer(hostname: hostname, port: port, token: apiToken, requireAuth: requireAuth)
        case (false, let error):
            print("Error: You need to grant reminders access to use the API server")
            if let error {
                print("Error: \(error.localizedDescription)")
            }
            Foundation.exit(1)
        }
    }
}

// Response structs for API responses
struct WebhookTestResponse: Codable {
    let success: Bool
    let message: String
}

// Initialize and start the server
func startServer(hostname: String, port: Int, token: String?, requireAuth: Bool) {
    let remindersService = Reminders()
    let webhookManager = WebhookManager(remindersService: remindersService)
    let authManager = AuthManager(token: token, requireAuth: requireAuth)
    
    // Create application with the provided hostname and port
    let app = HBApplication(configuration: .init(
        address: .hostname(hostname, port: port),
        serverName: "RemindersAPI"
    ))
    
    // Set auth required status on the application
    app.authRequired = authManager.isAuthRequired
    
    // Middleware for JSON response encoding
    let jsonEncoder = JSONEncoder()
    jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    app.encoder = jsonEncoder
    
    // Add CORS middleware
    app.middleware.add(
        HBCORSMiddleware(
            allowOrigin: .all,
            allowHeaders: ["Content-Type", "Authorization"],
            allowMethods: [.GET, .POST, .PUT, .DELETE, .PATCH]
        )
    )
    
    // Add token authentication middleware
    app.middleware.add(TokenAuthMiddleware(authManager: authManager))
    
    // Define middleware to check authentication for all routes
    struct AuthCheckMiddleware: HBMiddleware {
        func apply(to request: HBRequest, next: HBResponder) -> EventLoopFuture<HBResponse> {
            // Check if global auth is required
            let requireAuth = request.application.requireAuth
            if requireAuth && !request.isAuthenticated {
                return request.failure(.unauthorized, message: "Authentication required")
            }
            
            return next.respond(to: request)
        }
    }
    
    // Add auth check middleware
    app.middleware.add(AuthCheckMiddleware())
    
    // MARK: - Authentication Settings Routes
    
    // POST /auth/settings - Configure authentication settings
    app.router.post("auth/settings") { request -> HBResponse in
        // Always require authentication for settings management
        if !request.isAuthenticated {
            throw HBHTTPError(.unauthorized, message: "Authentication required")
        }
        
        struct AuthSettingsRequest: Decodable {
            let requireAuth: Bool
        }
        
        let settings = try request.decode(as: AuthSettingsRequest.self)
        
        // Update global auth requirement
        app.authRequired = settings.requireAuth
        authManager.setAuthRequired(settings.requireAuth)
        
        // Return confirmation
        let message = "Authentication settings updated. Required: \(settings.requireAuth)"
        let responseData = try JSONEncoder().encode(["message": message])
        
        return HBResponse(
            status: .ok,
            headers: ["content-type": "application/json"],
            body: .byteBuffer(ByteBuffer(data: responseData))
        )
    }
    
    // MARK: - Resource Routes
    
    // GET /lists - Get all reminder lists
    app.router.get("lists") { request -> HBResponse in
        let lists = remindersService.getCalendars()
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let listsData = try jsonEncoder.encode(lists)
        return HBResponse(status: .ok, headers: ["content-type": "application/json"], body: .byteBuffer(ByteBuffer(data: listsData)))
    }
    
    // GET /lists/:name - Get reminders from a specific list
    app.router.get("lists/:name") { request -> HBResponse in
        guard let listName = request.parameters.get("name") else {
            throw HBHTTPError(.badRequest, message: "Missing list name")
        }
        
        let displayOptions = request.uri.queryParameters.get("completed") == "true" ? 
            DisplayOptions.all : DisplayOptions.incomplete
            
        let reminders = try await fetchReminders(from: listName, displayOptions: displayOptions, remindersService: remindersService)
        let reminderData = try JSONEncoder().encode(reminders)
        return HBResponse(status: .ok, headers: ["content-type": "application/json"], body: .byteBuffer(ByteBuffer(data: reminderData)))
    }
    
    // GET /reminders - Get all reminders across all lists
    app.router.get("reminders") { request -> HBResponse in
        let displayOptions = request.uri.queryParameters.get("completed") == "true" ? 
            DisplayOptions.all : DisplayOptions.incomplete
            
        let reminders = try await fetchAllReminders(displayOptions: displayOptions, remindersService: remindersService)
        let reminderData = try JSONEncoder().encode(reminders)
        return HBResponse(status: .ok, headers: ["content-type": "application/json"], body: .byteBuffer(ByteBuffer(data: reminderData)))
    }
    
    // POST /lists/:name/reminders - Add a new reminder to a list
    app.router.post("lists/:name/reminders") { request -> HBResponse in
        
        guard let listName = request.parameters.get("name") else {
            throw HBHTTPError(.badRequest, message: "Missing list name")
        }
        
        struct ReminderRequest: Decodable {
            let title: String
            let notes: String?
            let dueDate: String?
            let priority: String?
        }
        
        let reminderRequest = try request.decode(as: ReminderRequest.self)
        
        var dueDateComponents: DateComponents? = nil
        if let dueDateString = reminderRequest.dueDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dueDateString) {
                dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            }
        }
        
        let priority = reminderRequest.priority.flatMap { Priority(rawValue: $0) } ?? .none
        
        let reminder = try await addReminder(
            title: reminderRequest.title,
            notes: reminderRequest.notes,
            listName: listName,
            dueDateComponents: dueDateComponents,
            priority: priority,
            remindersService: remindersService
        )
        
        let reminderData = try JSONEncoder().encode(reminder)
        return HBResponse(status: .created, headers: ["content-type": "application/json"], body: .byteBuffer(ByteBuffer(data: reminderData)))
    }
    
    // DELETE /lists/:listName/reminders/:id - Delete a reminder
    app.router.delete("lists/:listName/reminders/:id") { request -> HBResponse in
        guard let listName = request.parameters.get("listName") else {
            throw HBHTTPError(.badRequest, message: "Missing list name")
        }
        
        guard let reminderId = request.parameters.get("id") else {
            throw HBHTTPError(.badRequest, message: "Missing reminder ID")
        }
        
        try await deleteReminder(id: reminderId, listName: listName, remindersService: remindersService)
        
        return HBResponse(status: .noContent)
    }
    
    // PATCH /lists/:listName/reminders/:id/complete - Mark a reminder as complete
    app.router.patch("lists/:listName/reminders/:id/complete") { request -> HBResponse in
        guard let listName = request.parameters.get("listName") else {
            throw HBHTTPError(.badRequest, message: "Missing list name")
        }
        
        guard let reminderId = request.parameters.get("id") else {
            throw HBHTTPError(.badRequest, message: "Missing reminder ID")
        }
        
        try await setReminderComplete(id: reminderId, listName: listName, complete: true, remindersService: remindersService)
        
        return HBResponse(status: .ok)
    }
    
    // PATCH /lists/:listName/reminders/:id/uncomplete - Mark a reminder as incomplete
    app.router.patch("lists/:listName/reminders/:id/uncomplete") { request -> HBResponse in
        guard let listName = request.parameters.get("listName") else {
            throw HBHTTPError(.badRequest, message: "Missing list name")
        }
        
        guard let reminderId = request.parameters.get("id") else {
            throw HBHTTPError(.badRequest, message: "Missing reminder ID")
        }
        
        try await setReminderComplete(id: reminderId, listName: listName, complete: false, remindersService: remindersService)
        
        return HBResponse(status: .ok)
    }
    
    // New direct UUID-based endpoints
    
    // GET /reminders/:uuid - Get a reminder by UUID
    app.router.get("reminders/:uuid") { request -> HBResponse in
        guard let uuid = request.parameters.get("uuid") else {
            throw HBHTTPError(.badRequest, message: "Missing reminder UUID")
        }
        
        guard let reminder = remindersService.getReminderByUUID(uuid) else {
            throw HBHTTPError(.notFound, message: "Reminder not found")
        }
        
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reminderData = try jsonEncoder.encode(reminder)
        
        return HBResponse(status: .ok, headers: ["content-type": "application/json"], body: .byteBuffer(ByteBuffer(data: reminderData)))
    }
    
    // DELETE /reminders/:uuid - Delete a reminder by UUID
    app.router.delete("reminders/:uuid") { request -> HBResponse in
        guard let uuid = request.parameters.get("uuid") else {
            throw HBHTTPError(.badRequest, message: "Missing reminder UUID")
        }
        
        guard let reminder = remindersService.getReminderByUUID(uuid) else {
            throw HBHTTPError(.notFound, message: "Reminder not found")
        }
        
        try remindersService.deleteReminder(reminder)
        
        return HBResponse(status: .noContent)
    }
    
    // PATCH /reminders/:uuid/complete - Mark a reminder as complete by UUID
    app.router.patch("reminders/:uuid/complete") { request -> HBResponse in
        guard let uuid = request.parameters.get("uuid") else {
            throw HBHTTPError(.badRequest, message: "Missing reminder UUID")
        }
        
        guard let reminder = remindersService.getReminderByUUID(uuid) else {
            throw HBHTTPError(.notFound, message: "Reminder not found")
        }
        
        try remindersService.setReminderComplete(reminder, complete: true)
        
        return HBResponse(status: .ok)
    }
    
    // PATCH /reminders/:uuid/uncomplete - Mark a reminder as incomplete by UUID
    app.router.patch("reminders/:uuid/uncomplete") { request -> HBResponse in
        guard let uuid = request.parameters.get("uuid") else {
            throw HBHTTPError(.badRequest, message: "Missing reminder UUID")
        }
        
        guard let reminder = remindersService.getReminderByUUID(uuid) else {
            throw HBHTTPError(.notFound, message: "Reminder not found")
        }
        
        try remindersService.setReminderComplete(reminder, complete: false)
        
        return HBResponse(status: .ok)
    }
    
    // PATCH /reminders/:uuid - Update a reminder by UUID
    app.router.patch("reminders/:uuid") { request -> HBResponse in
        guard let uuid = request.parameters.get("uuid") else {
            throw HBHTTPError(.badRequest, message: "Missing reminder UUID")
        }
        
        guard let reminder = remindersService.getReminderByUUID(uuid) else {
            throw HBHTTPError(.notFound, message: "Reminder not found")
        }
        
        struct ReminderUpdateRequest: Decodable {
            let title: String?
            let notes: String?
            let dueDate: String?
            let priority: String?
            let isCompleted: Bool?
        }
        
        let updateRequest = try request.decode(as: ReminderUpdateRequest.self)
        
        if let title = updateRequest.title {
            reminder.title = title
        }
        
        if let notes = updateRequest.notes {
            reminder.notes = notes
        }
        
        if let dueDateString = updateRequest.dueDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dueDateString) {
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            }
        }
        
        if let priorityString = updateRequest.priority {
            if let priority = Priority(rawValue: priorityString) {
                reminder.priority = Int(priority.value.rawValue)
            }
        }
        
        if let isCompleted = updateRequest.isCompleted {
            reminder.isCompleted = isCompleted
        }
        
        try remindersService.updateReminder(reminder)
        
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reminderData = try jsonEncoder.encode(reminder)
        
        return HBResponse(status: .ok, headers: ["content-type": "application/json"], body: .byteBuffer(ByteBuffer(data: reminderData)))
    }
    
    // GET /search - Search for reminders with complex filtering
    app.router.get("search") { request -> HBResponse in
        // Parse query parameters
        let searchParams = parseSearchParameters(request)
        
        // Perform the search
        let searchResults = try await searchReminders(
            params: searchParams,
            remindersService: remindersService
        )
        
        // Encode and return results
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reminderData = try jsonEncoder.encode(searchResults)
        
        return HBResponse(
            status: .ok, 
            headers: ["content-type": "application/json"], 
            body: .byteBuffer(ByteBuffer(data: reminderData))
        )
    }
    
    // MARK: - Webhook Endpoints
    
    // GET /webhooks - Get all webhook configurations
    app.router.get("webhooks") { _ -> [WebhookConfig] in
        return webhookManager.getWebhooks()
    }
    
    // GET /webhooks/:id - Get a specific webhook configuration
    app.router.get("webhooks/:id") { request -> WebhookConfig in
        guard let idString = request.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw HBHTTPError(.badRequest, message: "Invalid webhook ID format")
        }
        
        guard let webhook = webhookManager.getWebhook(id: id) else {
            throw HBHTTPError(.notFound, message: "Webhook not found")
        }
        
        return webhook
    }
    
    // POST /webhooks - Create a new webhook
    app.router.post("webhooks") { request -> WebhookConfig in
        struct WebhookRequest: Decodable {
            let url: String
            let name: String
            let filter: WebhookFilterRequest
            
            struct WebhookFilterRequest: Decodable {
                let listNames: [String]?
                let listUUIDs: [String]?
                let completed: String?
                let priorityLevels: [Int]?
                let hasQuery: String?
            }
        }
        
        let webhookRequest = try request.decode(as: WebhookRequest.self)
        
        // Validate URL
        guard let url = URL(string: webhookRequest.url) else {
            throw HBHTTPError(.badRequest, message: "Invalid webhook URL")
        }
        
        // Parse completed filter
        var completedFilter: DisplayOptions? = nil
        if let completedString = webhookRequest.filter.completed {
            switch completedString.lowercased() {
            case "all": completedFilter = .all
            case "complete", "completed": completedFilter = .complete
            case "incomplete": completedFilter = .incomplete
            default: throw HBHTTPError(.badRequest, message: "Invalid 'completed' value: must be 'all', 'complete', or 'incomplete'")
            }
        }
        
        // Create filter
        let filter = WebhookFilter(
            listNames: webhookRequest.filter.listNames,
            listUUIDs: webhookRequest.filter.listUUIDs,
            completed: completedFilter,
            priorityLevels: webhookRequest.filter.priorityLevels,
            hasQuery: webhookRequest.filter.hasQuery
        )
        
        // Create webhook configuration
        let webhook = webhookManager.addWebhook(
            url: url,
            filter: filter,
            name: webhookRequest.name
        )
        
        return webhook
    }
    
    // PATCH /webhooks/:id - Update a webhook configuration
    app.router.patch("webhooks/:id") { request -> WebhookConfig in
        guard let idString = request.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw HBHTTPError(.badRequest, message: "Invalid webhook ID format")
        }
        
        guard webhookManager.getWebhook(id: id) != nil else {
            throw HBHTTPError(.notFound, message: "Webhook not found")
        }
        
        struct WebhookUpdateRequest: Decodable {
            let url: String?
            let name: String?
            let isActive: Bool?
            let filter: WebhookFilterRequest?
            
            struct WebhookFilterRequest: Decodable {
                let listNames: [String]?
                let listUUIDs: [String]?
                let completed: String?
                let priorityLevels: [Int]?
                let hasQuery: String?
            }
        }
        
        let updateRequest = try request.decode(as: WebhookUpdateRequest.self)
        
        // Parse URL if provided
        var updateURL: URL? = nil
        if let urlString = updateRequest.url {
            guard let url = URL(string: urlString) else {
                throw HBHTTPError(.badRequest, message: "Invalid webhook URL")
            }
            updateURL = url
        }
        
        // Parse filter if provided
        var updateFilter: WebhookFilter? = nil
        if let filterRequest = updateRequest.filter {
            // Parse completed filter
            var completedFilter: DisplayOptions? = nil
            if let completedString = filterRequest.completed {
                switch completedString.lowercased() {
                case "all": completedFilter = .all
                case "complete", "completed": completedFilter = .complete
                case "incomplete": completedFilter = .incomplete
                default: throw HBHTTPError(.badRequest, message: "Invalid 'completed' value: must be 'all', 'complete', or 'incomplete'")
                }
            }
            
            updateFilter = WebhookFilter(
                listNames: filterRequest.listNames,
                listUUIDs: filterRequest.listUUIDs,
                completed: completedFilter,
                priorityLevels: filterRequest.priorityLevels,
                hasQuery: filterRequest.hasQuery
            )
        }
        
        // Update the webhook
        let success = webhookManager.updateWebhook(
            id: id,
            isActive: updateRequest.isActive,
            filter: updateFilter,
            url: updateURL,
            name: updateRequest.name
        )
        
        if !success {
            throw HBHTTPError(.internalServerError, message: "Failed to update webhook")
        }
        
        // Return the updated webhook
        guard let updatedWebhook = webhookManager.getWebhook(id: id) else {
            throw HBHTTPError(.internalServerError, message: "Failed to retrieve updated webhook")
        }
        
        return updatedWebhook
    }
    
    // DELETE /webhooks/:id - Delete a webhook configuration
    app.router.delete("webhooks/:id") { request -> HBResponse in
        guard let idString = request.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw HBHTTPError(.badRequest, message: "Invalid webhook ID format")
        }
        
        let success = webhookManager.removeWebhook(id: id)
        
        if !success {
            throw HBHTTPError(.notFound, message: "Webhook not found")
        }
        
        return HBResponse(status: .noContent)
    }
    
    // POST /webhooks/:id/test - Test a webhook by sending a test event
    app.router.post("webhooks/:id/test") { request -> HBResponse in
        guard let idString = request.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw HBHTTPError(.badRequest, message: "Invalid webhook ID format")
        }
        
        guard let webhook = webhookManager.getWebhook(id: id) else {
            throw HBHTTPError(.notFound, message: "Webhook not found")
        }
        
        // Get a test reminder - use the first one that matches the filter
        let testReminders = try await fetchAllReminders(displayOptions: .all, remindersService: remindersService)
        
        // Find a reminder that matches the webhook filter
        let matchingReminder = testReminders.first { reminderWrapper in
            guard let reminder = remindersService.getReminderByUUID(reminderWrapper.uuid) else {
                return false
            }
            return webhook.filter.matches(reminder: reminder, remindersService: remindersService)
        }
        
        if let reminderWrapper = matchingReminder,
           let reminder = remindersService.getReminderByUUID(reminderWrapper.uuid) {
            // Create a test payload with a special "test" event
            let payload = WebhookPayload(event: .updated, reminder: reminder)
            
            // Send the test webhook
            let url = webhook.url
            let payloadData = try JSONEncoder().encode(payload)
            
            // Create HTTP request
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = payloadData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Send the test request synchronously
            var testSuccess = false
            let group = DispatchGroup()
            group.enter()
            
            let task = URLSession.shared.dataTask(with: request) { _, response, error in
                if let httpResponse = response as? HTTPURLResponse {
                    testSuccess = (200...299).contains(httpResponse.statusCode)
                }
                group.leave()
            }
            task.resume()
            
            // Wait with timeout (5 seconds)
            _ = group.wait(timeout: .now() + 5)
            
            // Use the WebhookTestResponse struct defined at the top of the file
            
            if testSuccess {
                let response = WebhookTestResponse(
                    success: true,
                    message: "Test webhook sent successfully"
                )
                return HBResponse(
                    status: .ok,
                    headers: ["content-type": "application/json"], 
                    body: .byteBuffer(ByteBuffer(data: try JSONEncoder().encode(response)))
                )
            } else {
                let response = WebhookTestResponse(
                    success: false,
                    message: "Test webhook failed to deliver"
                )
                return HBResponse(
                    status: .internalServerError,
                    headers: ["content-type": "application/json"], 
                    body: .byteBuffer(ByteBuffer(data: try JSONEncoder().encode(response)))
                )
            }
        } else {
            let response = WebhookTestResponse(
                success: false,
                message: "No matching reminders found to test webhook with"
            )
            return HBResponse(
                status: .notFound,
                headers: ["content-type": "application/json"], 
                body: .byteBuffer(ByteBuffer(data: try JSONEncoder().encode(response)))
            )
        }
    }
    
    // Authentication is handled by AuthCheckMiddleware
    
    // Print server information
    let tokenStatus = token != nil ? "configured" : "not configured"
    let authStatus = requireAuth ? "required" : "optional"
    
    print("RemindersAPI server starting on http://\(hostname):\(port) with webhook support")
    print("API token: \(tokenStatus)")
    print("Authentication: \(authStatus)")
    print("Set API token using --token option or REMINDERS_API_TOKEN environment variable")
    print("Generate a new token with: reminders-api --generate-token")
    
    // Run the application
    try! app.start()
    
    // Wait for the application to close
    app.wait()
}

// Helper function to fetch reminders from a specific list
func fetchReminders(from listName: String, displayOptions: DisplayOptions, remindersService: Reminders) async throws -> [EKReminderWrapper] {
    return try await withCheckedThrowingContinuation { continuation in
        let calendar = remindersService.calendar(withName: listName)
        
        remindersService.reminders(on: [calendar], displayOptions: displayOptions) { reminders in
            let wrappedReminders = reminders.map { EKReminderWrapper(reminder: $0) }
            continuation.resume(returning: wrappedReminders)
        }
    }
}

// Helper function to fetch all reminders
func fetchAllReminders(displayOptions: DisplayOptions, remindersService: Reminders) async throws -> [EKReminderWrapper] {
    return try await withCheckedThrowingContinuation { continuation in
        let calendars = remindersService.getCalendars()
        
        remindersService.reminders(on: calendars, displayOptions: displayOptions) { reminders in
            let wrappedReminders = reminders.map { EKReminderWrapper(reminder: $0) }
            continuation.resume(returning: wrappedReminders)
        }
    }
}

// Helper function to add a reminder
func addReminder(title: String, notes: String?, listName: String, dueDateComponents: DateComponents?, 
                priority: Priority, remindersService: Reminders) async throws -> EKReminderWrapper {
    return try await withCheckedThrowingContinuation { continuation in
        let calendar = remindersService.calendar(withName: listName)
        let reminder = remindersService.createReminder(
            title: title,
            notes: notes,
            calendar: calendar,
            dueDateComponents: dueDateComponents,
            priority: priority
        )
        
        continuation.resume(returning: EKReminderWrapper(reminder: reminder))
    }
}

// Helper function to delete a reminder
func deleteReminder(id: String, listName: String, remindersService: Reminders) async throws {
    return try await withCheckedThrowingContinuation { continuation in
        let calendar = remindersService.calendar(withName: listName)
        
        // Handle both formats (with and without the protocol prefix)
        let prefix = "x-apple-reminder://"
        let fullId = id.hasPrefix(prefix) ? id : "\(prefix)\(id)"
        
        remindersService.reminders(on: [calendar], displayOptions: .all) { reminders in
            // Try with the fully qualified ID first
            if let reminder = reminders.first(where: { $0.calendarItemExternalIdentifier == fullId }) {
                do {
                    try remindersService.deleteReminder(reminder)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: HBHTTPError(.internalServerError, message: error.localizedDescription))
                }
                return
            }
            
            // For backward compatibility, try with the original ID string
            if let reminder = reminders.first(where: { $0.calendarItemExternalIdentifier == id }) {
                do {
                    try remindersService.deleteReminder(reminder)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: HBHTTPError(.internalServerError, message: error.localizedDescription))
                }
                return
            }
            
            continuation.resume(throwing: HBHTTPError(.notFound, message: "Reminder not found"))
        }
    }
}

// Helper function to mark a reminder as complete or incomplete
func setReminderComplete(id: String, listName: String, complete: Bool, remindersService: Reminders) async throws {
    return try await withCheckedThrowingContinuation { continuation in
        let calendar = remindersService.calendar(withName: listName)
        
        // Handle both formats (with and without the protocol prefix)
        let prefix = "x-apple-reminder://"
        let fullId = id.hasPrefix(prefix) ? id : "\(prefix)\(id)"
        
        remindersService.reminders(on: [calendar], displayOptions: .all) { reminders in
            // Try with the fully qualified ID first
            if let reminder = reminders.first(where: { $0.calendarItemExternalIdentifier == fullId }) {
                do {
                    try remindersService.setReminderComplete(reminder, complete: complete)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: HBHTTPError(.internalServerError, message: error.localizedDescription))
                }
                return
            }
            
            // For backward compatibility, try with the original ID string
            if let reminder = reminders.first(where: { $0.calendarItemExternalIdentifier == id }) {
                do {
                    try remindersService.setReminderComplete(reminder, complete: complete)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: HBHTTPError(.internalServerError, message: error.localizedDescription))
                }
                return
            }
            
            continuation.resume(throwing: HBHTTPError(.notFound, message: "Reminder not found"))
        }
    }
}

// Wrapper struct for EKReminder to provide Codable support
struct EKReminderWrapper: Encodable, HBResponseGenerator {
    // UUID is the primary identifier for all operations
    let uuid: String
    // Secondary identifiers for advanced usage
    let calendarItemIdentifier: String
    let externalId: String
    
    // Basic reminder data
    let title: String
    let notes: String?
    let dueDate: String?
    let isCompleted: Bool
    let priority: Int
    
    // List information, including the list UUID for cross-reference
    let listName: String
    let listUUID: String
    
    // Timestamps
    let creationDate: String?
    let lastModifiedDate: String?
    let completionDate: String?
    
    // Implement HBResponseGenerator protocol
    func response(from request: HBRequest) throws -> HBResponse {
        let data = try JSONEncoder().encode(self)
        return HBResponse(
            status: .ok,
            headers: ["content-type": "application/json"],
            body: .byteBuffer(ByteBuffer(data: data))
        )
    }
    
    init(reminder: EKReminder) {
        self.uuid = reminder.calendarItemExternalIdentifier
        self.calendarItemIdentifier = reminder.calendarItemIdentifier
        self.externalId = reminder.calendarItemExternalIdentifier
        self.title = reminder.title ?? "<unknown>"
        self.notes = reminder.notes
        self.isCompleted = reminder.isCompleted
        self.priority = reminder.priority
        self.listName = reminder.calendar.title
        self.listUUID = reminder.calendar.calendarIdentifier
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        
        if let date = reminder.dueDateComponents?.date {
            self.dueDate = formatter.string(from: date)
        } else {
            self.dueDate = nil
        }
        
        if let date = reminder.creationDate {
            self.creationDate = formatter.string(from: date)
        } else {
            self.creationDate = nil
        }
        
        if let date = reminder.lastModifiedDate {
            self.lastModifiedDate = formatter.string(from: date)
        } else {
            self.lastModifiedDate = nil
        }
        
        if let date = reminder.completionDate {
            self.completionDate = formatter.string(from: date)
        } else {
            self.completionDate = nil
        }
    }
}

// Definition of SearchParameters struct
struct SearchParameters {
    var listNames: [String]?
    var listUUIDs: [String]?
    var query: String?
    var completed: DisplayOptions
    var dueBefore: Date?
    var dueAfter: Date?
    var modifiedAfter: Date?
    var createdAfter: Date?
    var hasNotes: Bool?
    var hasDueDate: Bool?
    var priority: Priority?
    var priorityMin: Int?
    var priorityMax: Int?
    var sortBy: String?
    var sortOrder: String?
    var limit: Int?
}

// Parse search parameters from the request
func parseSearchParameters(_ request: HBRequest) -> SearchParameters {
    let queryParams = request.uri.queryParameters
    
    // Define date formatter for parsing date strings
    let dateFormatter = ISO8601DateFormatter()
    dateFormatter.formatOptions = [.withInternetDateTime]
    
    // Parse list parameters
    let listNames = queryParams.get("lists")?.components(separatedBy: ",")
    let listUUIDs = queryParams.get("listUUIDs")?.components(separatedBy: ",")
    
    // Parse text search
    let query = queryParams.get("query")
    
    // Parse completion status
    let completionStatus = queryParams.get("completed")
    let completed: DisplayOptions
    if completionStatus == "true" {
        completed = .complete
    } else if completionStatus == "false" {
        completed = .incomplete
    } else {
        completed = .all
    }
    
    // Parse date filters
    let dueBefore = queryParams.get("dueBefore").flatMap { dateFormatter.date(from: $0) }
    let dueAfter = queryParams.get("dueAfter").flatMap { dateFormatter.date(from: $0) }
    let modifiedAfter = queryParams.get("modifiedAfter").flatMap { dateFormatter.date(from: $0) }
    let createdAfter = queryParams.get("createdAfter").flatMap { dateFormatter.date(from: $0) }
    
    // Parse flags
    let hasNotes = queryParams.get("hasNotes").flatMap { $0 == "true" ? true : ($0 == "false" ? false : nil) }
    let hasDueDate = queryParams.get("hasDueDate").flatMap { $0 == "true" ? true : ($0 == "false" ? false : nil) }
    
    // Parse priority filters
    let priority = queryParams.get("priority").flatMap { Priority(rawValue: $0) }
    let priorityMin = queryParams.get("priorityMin").flatMap { Int($0) }
    let priorityMax = queryParams.get("priorityMax").flatMap { Int($0) }
    
    // Parse sorting parameters
    let sortBy = queryParams.get("sortBy")
    let sortOrder = queryParams.get("sortOrder")
    
    // Parse limit
    let limit = queryParams.get("limit").flatMap { Int($0) }
    
    return SearchParameters(
        listNames: listNames,
        listUUIDs: listUUIDs,
        query: query,
        completed: completed,
        dueBefore: dueBefore,
        dueAfter: dueAfter,
        modifiedAfter: modifiedAfter,
        createdAfter: createdAfter,
        hasNotes: hasNotes,
        hasDueDate: hasDueDate,
        priority: priority,
        priorityMin: priorityMin,
        priorityMax: priorityMax,
        sortBy: sortBy,
        sortOrder: sortOrder,
        limit: limit
    )
}

// Search reminders based on provided parameters
func searchReminders(params: SearchParameters, remindersService: Reminders) async throws -> [EKReminderWrapper] {
    return try await withCheckedThrowingContinuation { continuation in
        // Determine which calendars to search
        var calendarsToSearch: [EKCalendar] = []
        
        if let listNames = params.listNames {
            for name in listNames {
                // This won't throw since the function calls exit(1) on error
                // We'll need to handle that differently in a real API context
                let calendar = remindersService.calendar(withName: name)
                calendarsToSearch.append(calendar)
            }
        }
        
        if let listUUIDs = params.listUUIDs {
            for uuid in listUUIDs {
                if let calendar = remindersService.calendar(withUUID: uuid),
                   !calendarsToSearch.contains(where: { $0.calendarIdentifier == calendar.calendarIdentifier }) {
                    calendarsToSearch.append(calendar)
                }
            }
        }
        
        // If no specific calendars were requested, search all
        if calendarsToSearch.isEmpty {
            calendarsToSearch = remindersService.getCalendars()
        }
        
        // Fetch reminders from selected calendars
        remindersService.reminders(on: calendarsToSearch, displayOptions: .all) { reminders in
            // Apply filters to reminders
            var filteredReminders = reminders
            
            // Filter by completion status
            filteredReminders = filteredReminders.filter { reminder in
                remindersService.shouldDisplay(reminder: reminder, displayOptions: params.completed)
            }
            
            // Filter by text query if provided
            if let query = params.query, !query.isEmpty {
                filteredReminders = filteredReminders.filter { reminder in
                    // Search in title
                    if let title = reminder.title, title.localizedCaseInsensitiveContains(query) {
                        return true
                    }
                    
                    // Search in notes
                    if let notes = reminder.notes, notes.localizedCaseInsensitiveContains(query) {
                        return true
                    }
                    
                    return false
                }
            }
            
            // Filter by due date criteria
            if let dueBefore = params.dueBefore {
                filteredReminders = filteredReminders.filter { reminder in
                    guard let reminderDueDate = reminder.dueDateComponents?.date else {
                        return false
                    }
                    return reminderDueDate < dueBefore
                }
            }
            
            if let dueAfter = params.dueAfter {
                filteredReminders = filteredReminders.filter { reminder in
                    guard let reminderDueDate = reminder.dueDateComponents?.date else {
                        return false
                    }
                    return reminderDueDate > dueAfter
                }
            }
            
            // Filter by modification date
            if let modifiedAfter = params.modifiedAfter {
                filteredReminders = filteredReminders.filter { reminder in
                    guard let modifiedDate = reminder.lastModifiedDate else {
                        return false
                    }
                    return modifiedDate > modifiedAfter
                }
            }
            
            // Filter by creation date
            if let createdAfter = params.createdAfter {
                filteredReminders = filteredReminders.filter { reminder in
                    guard let creationDate = reminder.creationDate else {
                        return false
                    }
                    return creationDate > createdAfter
                }
            }
            
            // Filter by presence of notes
            if let hasNotes = params.hasNotes {
                filteredReminders = filteredReminders.filter { reminder in
                    if hasNotes {
                        return reminder.notes != nil && !reminder.notes!.isEmpty
                    } else {
                        return reminder.notes == nil || reminder.notes!.isEmpty
                    }
                }
            }
            
            // Filter by presence of due date
            if let hasDueDate = params.hasDueDate {
                filteredReminders = filteredReminders.filter { reminder in
                    if hasDueDate {
                        return reminder.dueDateComponents != nil
                    } else {
                        return reminder.dueDateComponents == nil
                    }
                }
            }
            
            // Filter by exact priority
            if let priority = params.priority {
                filteredReminders = filteredReminders.filter { reminder in
                    return reminder.priority == Int(priority.value.rawValue)
                }
            }
            
            // Filter by minimum priority
            if let priorityMin = params.priorityMin {
                filteredReminders = filteredReminders.filter { reminder in
                    return reminder.priority >= priorityMin
                }
            }
            
            // Filter by maximum priority
            if let priorityMax = params.priorityMax {
                filteredReminders = filteredReminders.filter { reminder in
                    return reminder.priority <= priorityMax
                }
            }
            
            // Apply sorting
            if let sortBy = params.sortBy {
                let ascending = params.sortOrder?.lowercased() != "desc"
                
                filteredReminders.sort { first, second in
                    switch sortBy.lowercased() {
                    case "title":
                        let firstTitle = first.title ?? ""
                        let secondTitle = second.title ?? ""
                        return ascending ? firstTitle < secondTitle : firstTitle > secondTitle
                        
                    case "duedate":
                        let firstDate = first.dueDateComponents?.date
                        let secondDate = second.dueDateComponents?.date
                        
                        // Handle nil dates based on sort order
                        switch (firstDate, secondDate) {
                        case (nil, nil): return false
                        case (nil, _): return !ascending
                        case (_, nil): return ascending
                        case (let first?, let second?):
                            return ascending ? first < second : first > second
                        }
                        
                    case "created":
                        let firstDate = first.creationDate
                        let secondDate = second.creationDate
                        
                        switch (firstDate, secondDate) {
                        case (nil, nil): return false
                        case (nil, _): return !ascending
                        case (_, nil): return ascending
                        case (let first?, let second?):
                            return ascending ? first < second : first > second
                        }
                        
                    case "modified":
                        let firstDate = first.lastModifiedDate
                        let secondDate = second.lastModifiedDate
                        
                        switch (firstDate, secondDate) {
                        case (nil, nil): return false
                        case (nil, _): return !ascending
                        case (_, nil): return ascending
                        case (let first?, let second?):
                            return ascending ? first < second : first > second
                        }
                        
                    case "priority":
                        return ascending ? 
                            first.priority < second.priority : 
                            first.priority > second.priority
                        
                    case "list":
                        return ascending ? 
                            first.calendar.title < second.calendar.title : 
                            first.calendar.title > second.calendar.title
                            
                    default:
                        return false
                    }
                }
            }
            
            // Apply limit if specified
            if let limit = params.limit, limit > 0 && limit < filteredReminders.count {
                filteredReminders = Array(filteredReminders.prefix(limit))
            }
            
            // Map to wrapper objects and return
            let wrappedReminders = filteredReminders.map { EKReminderWrapper(reminder: $0) }
            continuation.resume(returning: wrappedReminders)
        }
    }
}

// Helper function to convert EKReminderPriority to Priority
func priorityFromRawValue(_ value: Int) -> Priority? {
    if let priority = UInt(exactly: value).flatMap(EKReminderPriority.init) {
        switch priority {
        case .low:
            return .low
        case .medium:
            return .medium
        case .high:
            return .high
        case .none:
            return Priority.none
        @unknown default:
            return Priority.none
        }
    }
    return nil
}

// Run the Configuration command defined above
Configuration.main()