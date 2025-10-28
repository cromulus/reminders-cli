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
    
    @Option(name: [.customLong("log-level")], help: "Set log level (DEBUG, INFO, WARN, ERROR)")
    var logLevel: String?
    
    @Flag(name: [.customLong("auth-required")], help: "Require authentication for all API endpoints")
    var requireAuth = false
    
    @Flag(name: [.customLong("no-auth")], help: "Explicitly disable authentication (overrides config file and other settings)")
    var noAuth = false
    
    @Flag(name: [.customLong("generate-token")], help: "Generate a new API token and exit")
    var generateToken = false
    
    func run() throws {
        // Set up logging first
        if let logLevelString = logLevel ?? ProcessInfo.processInfo.environment["LOG_LEVEL"],
           let level = LogLevel(string: logLevelString) {
            Logger.shared.setLevel(level)
            Logger.shared.info("Log level set to \(level.rawValue)")
        }
        
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
        Logger.shared.info("API token configuration: \(apiToken != nil ? "provided" : "not provided")")
        
        // Determine authentication requirement with precedence:
        // 1. --no-auth flag (disables auth completely)
        // 2. --auth-required flag (enables auth)
        // 3. Default to false (no auth required)
        let finalRequireAuth = noAuth ? false : requireAuth
        Logger.shared.info("Authentication requirement: \(finalRequireAuth ? "REQUIRED" : "OPTIONAL")")
        
        // Check if reminders access is granted before starting server
        Logger.shared.info("Requesting Reminders access...")
        switch Reminders.requestAccess() {
        case (true, _):
            Logger.shared.info("Reminders access granted. Starting API server...")
            print("Reminders access granted. Starting API server...")
            startServer(hostname: hostname, port: port, token: apiToken, requireAuth: finalRequireAuth)
        case (false, let error):
            Logger.shared.error("Reminders access denied")
            print("Error: You need to grant reminders access to use the API server")
            if let error {
                Logger.shared.error("Reminders access error: \(error.localizedDescription)")
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
    Logger.shared.info("Initializing server components...")
    
    let remindersService = Reminders()
    let webhookManager = WebhookManager(remindersService: remindersService)
    let authManager = AuthManager(token: token, requireAuth: requireAuth)
    let mcpHandler = RemindersMCPHTTPHandler(reminders: remindersService)
    
    Logger.shared.debug("Creating Hummingbird application...")
    
    // Create application with the provided hostname and port
    let app = HBApplication(configuration: .init(
        address: .hostname(hostname, port: port),
        serverName: "RemindersAPI"
    ))
    
    // Set auth required status on the application
    app.authRequired = authManager.isAuthRequired
    Logger.shared.debug("Application auth requirement set to: \(authManager.isAuthRequired)")
    
    // Middleware for JSON response encoding
    let jsonEncoder = JSONEncoder()
    jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    app.encoder = jsonEncoder
    Logger.shared.debug("JSON encoder configured")
    
    // Add CORS middleware
    app.middleware.add(
        HBCORSMiddleware(
            allowOrigin: .all,
            allowHeaders: ["Content-Type", "Authorization", "Mcp-Session-Id"],
            allowMethods: [.GET, .POST, .PUT, .DELETE, .PATCH]
        )
    )
    Logger.shared.debug("CORS middleware added")
    
    // Add token authentication middleware
    app.middleware.add(TokenAuthMiddleware(authManager: authManager, requireAuth: requireAuth))
    Logger.shared.debug("Token authentication middleware added")
    
    // Define middleware to check authentication for all routes
    struct AuthCheckMiddleware: HBMiddleware {
        func apply(to request: HBRequest, next: HBResponder) -> EventLoopFuture<HBResponse> {
            // Check if global auth is required
            let requireAuth = request.application.requireAuth
            if requireAuth && !request.isAuthenticated {
                Logger.shared.warn("Request \(request.method) \(request.uri.path) - authentication required but not provided")
                return request.failure(.unauthorized, message: "Authentication required")
            }
            
            Logger.shared.debug("Request \(request.method) \(request.uri.path) - auth check passed")
            return next.respond(to: request)
        }
    }
    
    // Add auth check middleware
    app.middleware.add(AuthCheckMiddleware())
    Logger.shared.debug("Auth check middleware added")

    // MCP Routes
    app.router.post("mcp") { request in
        try await mcpHandler.handlePost(request)
    }

    app.router.get("mcp") { request in
        try await mcpHandler.handleStream(request)
    }

    app.router.delete("mcp") { request in
        try await mcpHandler.handleDelete(request)
    }

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
    
    // GET /calendars - Get all calendars (reminder lists)
    app.router.get("calendars") { request -> HBResponse in
        Logger.shared.info("Fetching all calendars")
        let calendars = remindersService.getCalendars()
        Logger.shared.debug("Found \(calendars.count) calendars")
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let calendarsData = try jsonEncoder.encode(calendars)
        return HBResponse(status: .ok, headers: ["content-type": "application/json"], body: .byteBuffer(ByteBuffer(data: calendarsData)))
    }
    
    // GET /lists - Get all reminder lists (alias for calendars)
    app.router.get("lists") { request -> HBResponse in
        Logger.shared.info("Fetching all reminder lists")
        let lists = remindersService.getCalendars()
        Logger.shared.debug("Found \(lists.count) reminder lists")
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let listsData = try jsonEncoder.encode(lists)
        return HBResponse(status: .ok, headers: ["content-type": "application/json"], body: .byteBuffer(ByteBuffer(data: listsData)))
    }
    
    // GET /lists/:name - Get reminders from a specific list
    app.router.get("lists/:name") { request -> HBResponse in
        guard let listName = request.parameters.get("name") else {
            Logger.shared.warn("Missing list name parameter in request")
            throw HBHTTPError(.badRequest, message: "Missing list name")
        }
        
        Logger.shared.info("Fetching reminders from list: \(listName)")
        
        let displayOptions = request.uri.queryParameters.get("completed") == "true" ? 
            DisplayOptions.all : DisplayOptions.incomplete
        Logger.shared.debug("Display options: \(displayOptions)")
            
        let reminders = try await fetchReminders(from: listName, displayOptions: displayOptions, remindersService: remindersService)
        Logger.shared.debug("Found \(reminders.count) reminders in list \(listName)")
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reminderData = try jsonEncoder.encode(reminders)
        return HBResponse(status: .ok, headers: ["content-type": "application/json"], body: .byteBuffer(ByteBuffer(data: reminderData)))
    }
    
    // GET /reminders - Get all reminders across all lists
    app.router.get("reminders") { request -> HBResponse in
        Logger.shared.info("Fetching all reminders across all lists")
        
        let displayOptions = request.uri.queryParameters.get("completed") == "true" ? 
            DisplayOptions.all : DisplayOptions.incomplete
        Logger.shared.debug("Display options: \(displayOptions)")
            
        let reminders = try await fetchAllReminders(displayOptions: displayOptions, remindersService: remindersService)
        Logger.shared.debug("Found \(reminders.count) total reminders")
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reminderData = try jsonEncoder.encode(reminders)
        return HBResponse(status: .ok, headers: ["content-type": "application/json"], body: .byteBuffer(ByteBuffer(data: reminderData)))
    }
    
    // POST /lists/:name/reminders - Add a new reminder to a list
    app.router.post("lists/:name/reminders") { request -> HBResponse in
        
        guard let listName = request.parameters.get("name") else {
            Logger.shared.warn("Missing list name parameter in POST request")
            throw HBHTTPError(.badRequest, message: "Missing list name")
        }
        
        Logger.shared.info("Creating new reminder in list: \(listName)")
        
        struct ReminderRequest: Decodable {
            let title: String
            let notes: String?
            let dueDate: String?
            let priority: String?
        }
        
        let reminderRequest = try request.decode(as: ReminderRequest.self)
        Logger.shared.debug("New reminder title: \(reminderRequest.title)")
        
        var dueDateComponents: DateComponents? = nil
        if let dueDateString = reminderRequest.dueDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dueDateString) {
                dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                Logger.shared.debug("Due date parsed: \(dueDateString)")
            } else {
                Logger.shared.warn("Failed to parse due date: \(dueDateString)")
            }
        }
        
        let priority = reminderRequest.priority.flatMap { Priority(rawValue: $0) } ?? .none
        Logger.shared.debug("Priority set to: \(priority)")
        
        let reminder = try await addReminder(
            title: reminderRequest.title,
            notes: reminderRequest.notes,
            listName: listName,
            dueDateComponents: dueDateComponents,
            priority: priority,
            remindersService: remindersService
        )
        
        Logger.shared.info("Successfully created reminder: \(reminderRequest.title)")
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reminderData = try jsonEncoder.encode(reminder)
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

    // PATCH /lists/:listName/reminders/:id - Update a reminder
    app.router.patch("lists/:listName/reminders/:id") { request -> HBResponse in
        guard let listName = request.parameters.get("listName") else {
            throw HBHTTPError(.badRequest, message: "Missing list name")
        }

        guard let reminderId = request.parameters.get("id") else {
            throw HBHTTPError(.badRequest, message: "Missing reminder ID")
        }

        Logger.shared.info("Updating reminder \(reminderId) in list: \(listName)")

        struct ReminderUpdateRequest: Decodable {
            let title: String?
            let notes: String?
            let dueDate: String?
            let priority: String?
        }

        let updateRequest = try request.decode(as: ReminderUpdateRequest.self)

        let updatedReminder = try await updateReminder(
            id: reminderId,
            listName: listName,
            title: updateRequest.title,
            notes: updateRequest.notes,
            dueDateString: updateRequest.dueDate,
            priority: updateRequest.priority,
            remindersService: remindersService
        )

        Logger.shared.info("Successfully updated reminder: \(reminderId)")
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reminderData = try jsonEncoder.encode(updatedReminder)
        return HBResponse(status: .ok, headers: ["content-type": "application/json"], body: .byteBuffer(ByteBuffer(data: reminderData)))
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
        let matchingReminder = testReminders.first { reminder in
            return webhook.filter.matches(reminder: reminder, remindersService: remindersService)
        }
        
        if let reminder = matchingReminder {
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
            
            let testSucceeded: Bool
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    testSucceeded = (200...299).contains(httpResponse.statusCode)
                } else {
                    testSucceeded = false
                }
            } catch {
                Logger.shared.warn("Test webhook delivery failed: \(error.localizedDescription)")
                testSucceeded = false
            }

            if testSucceeded {
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
    
    // Get config file location for display
    let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let configDirectory = appSupportURL.appendingPathComponent("reminders-cli", isDirectory: true)
    let authConfigPath = configDirectory.appendingPathComponent("auth_config.json").path
    let webhookConfigPath = configDirectory.appendingPathComponent("webhooks.json").path
    
    // Get registered webhooks
    let webhooks = webhookManager.getWebhooks()
    
    // Print enhanced server information
    print("=====================================")
    print("RemindersAPI Server Starting")
    print("=====================================")
    print("Server URL: http://\(hostname):\(port)")
    print("Authentication: \(requireAuth ? "REQUIRED" : "OPTIONAL")")
    print("Log Level: \(Logger.shared.level.rawValue)")
    
    if let token = token {
        print("API Token: \(token)")
    } else {
        print("API Token: Not configured")
    }
    
    print("Auth Config: \(authConfigPath)")
    print("Webhook Config: \(webhookConfigPath)")
    
    if webhooks.isEmpty {
        print("Registered Webhooks: None")
    } else {
        print("Registered Webhooks: \(webhooks.count)")
        for webhook in webhooks {
            let status = webhook.isActive ? "ACTIVE" : "INACTIVE"
            print("  - \(webhook.name): \(webhook.url) [\(status)]")
        }
    }
    
    print("=====================================")
    print("Usage:")
    print("  Generate token: reminders-api --generate-token")
    print("  Require auth: reminders-api --auth-required")
    print("  Disable auth: reminders-api --no-auth")
    print("  Set token: reminders-api --token YOUR_TOKEN")
    print("  Set log level: reminders-api --log-level DEBUG")
    print("  Environment: REMINDERS_API_TOKEN=YOUR_TOKEN reminders-api")
    print("  Environment: LOG_LEVEL=DEBUG reminders-api")
    print("=====================================")
    
    Logger.shared.info("Starting Hummingbird server...")
    
    // Run the application
    try! app.start()
    
    // Wait for the application to close
    app.wait()
}

// Helper function to fetch reminders from a specific list
func fetchReminders(from listName: String, displayOptions: DisplayOptions, remindersService: Reminders) async throws -> [EKReminder] {
    return try await withCheckedThrowingContinuation { continuation in
        let calendar = remindersService.calendar(withName: listName)
        
        remindersService.reminders(on: [calendar], displayOptions: displayOptions) { reminders in
            continuation.resume(returning: reminders)
        }
    }
}

// Helper function to fetch all reminders
func fetchAllReminders(displayOptions: DisplayOptions, remindersService: Reminders) async throws -> [EKReminder] {
    return try await withCheckedThrowingContinuation { continuation in
        let calendars = remindersService.getCalendars()
        
        remindersService.reminders(on: calendars, displayOptions: displayOptions) { reminders in
            continuation.resume(returning: reminders)
        }
    }
}

// Helper function to add a reminder
func addReminder(title: String, notes: String?, listName: String, dueDateComponents: DateComponents?, 
                priority: Priority, remindersService: Reminders) async throws -> EKReminder {
    return try await withCheckedThrowingContinuation { continuation in
        let calendar = remindersService.calendar(withName: listName)
        let reminder = remindersService.createReminder(
            title: title,
            notes: notes,
            calendar: calendar,
            dueDateComponents: dueDateComponents,
            priority: priority
        )
        
        continuation.resume(returning: reminder)
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

// Helper function to update a reminder
func updateReminder(id: String, listName: String, title: String?, notes: String?,
                   dueDateString: String?, priority: String?, remindersService: Reminders) async throws -> EKReminder {
    return try await withCheckedThrowingContinuation { continuation in
        let calendar = remindersService.calendar(withName: listName)

        // Handle both formats (with and without the protocol prefix)
        let prefix = "x-apple-reminder://"
        let fullId = id.hasPrefix(prefix) ? id : "\(prefix)\(id)"

        remindersService.reminders(on: [calendar], displayOptions: .all) { reminders in
            // Try with the fully qualified ID first
            if let reminder = reminders.first(where: { $0.calendarItemExternalIdentifier == fullId }) {
                // Update fields if provided
                if let title = title {
                    reminder.title = title
                }

                if let notes = notes {
                    reminder.notes = notes
                }

                if let dueDateString = dueDateString {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime]
                    if let date = formatter.date(from: dueDateString) {
                        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                    }
                }

                if let priorityString = priority {
                    if let priority = Priority(rawValue: priorityString) {
                        reminder.priority = Int(priority.value.rawValue)
                    }
                }

                do {
                    try remindersService.updateReminder(reminder)
                    continuation.resume(returning: reminder)
                } catch {
                    continuation.resume(throwing: HBHTTPError(.internalServerError, message: error.localizedDescription))
                }
                return
            }

            // For backward compatibility, try with the original ID string
            if let reminder = reminders.first(where: { $0.calendarItemExternalIdentifier == id }) {
                // Update fields if provided
                if let title = title {
                    reminder.title = title
                }

                if let notes = notes {
                    reminder.notes = notes
                }

                if let dueDateString = dueDateString {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime]
                    if let date = formatter.date(from: dueDateString) {
                        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                    }
                }

                if let priorityString = priority {
                    if let priority = Priority(rawValue: priorityString) {
                        reminder.priority = Int(priority.value.rawValue)
                    }
                }

                do {
                    try remindersService.updateReminder(reminder)
                    continuation.resume(returning: reminder)
                } catch {
                    continuation.resume(throwing: HBHTTPError(.internalServerError, message: error.localizedDescription))
                }
                return
            }

            continuation.resume(throwing: HBHTTPError(.notFound, message: "Reminder not found"))
        }
    }
}

// Definition of SearchParameters struct
struct SearchParameters {
    var lists: [String]?  // Unified parameter for list names and UUIDs
    var excludeLists: [String]?  // Unified parameter for excluding list names and UUIDs
    var calendars: [String]?  // Unified parameter for calendar names and UUIDs
    var excludeCalendars: [String]?  // Unified parameter for excluding calendar names and UUIDs
    var query: String?
    var completed: DisplayOptions
    var dueBefore: Date?
    var dueAfter: Date?
    var modifiedAfter: Date?
    var createdAfter: Date?
    var hasNotes: Bool?
    var hasDueDate: Bool?
    var priorities: [Priority]?
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
    
    // Parse list and calendar parameters (unified)
    let lists = queryParams.get("lists")?.components(separatedBy: ",")
    let excludeLists = queryParams.get("exclude_lists")?.components(separatedBy: ",")
    let calendars = queryParams.get("calendars")?.components(separatedBy: ",")
    let excludeCalendars = queryParams.get("exclude_calendars")?.components(separatedBy: ",")
    
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
    
    // Parse priority filters - support multiple values and "any"
    let priorityParam = queryParams.get("priority")
    let priorities: [Priority]?
    
    if let priorityParam = priorityParam {
        if priorityParam == "any" {
            // "any" means low, medium, high (excludes none)
            priorities = [.low, .medium, .high]
        } else {
            // Parse comma-separated values
            priorities = priorityParam.components(separatedBy: ",")
                .compactMap { Priority(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
        }
    } else {
        priorities = nil // No filter = all priorities
    }
    
    let priorityMin = queryParams.get("priorityMin").flatMap { Int($0) }
    let priorityMax = queryParams.get("priorityMax").flatMap { Int($0) }
    
    // Parse sorting parameters
    let sortBy = queryParams.get("sortBy")
    let sortOrder = queryParams.get("sortOrder")
    
    // Parse limit
    let limit = queryParams.get("limit").flatMap { Int($0) }
    
    return SearchParameters(
        lists: lists,
        excludeLists: excludeLists,
        calendars: calendars,
        excludeCalendars: excludeCalendars,
        query: query,
        completed: completed,
        dueBefore: dueBefore,
        dueAfter: dueAfter,
        modifiedAfter: modifiedAfter,
        createdAfter: createdAfter,
        hasNotes: hasNotes,
        hasDueDate: hasDueDate,
        priorities: priorities,
        priorityMin: priorityMin,
        priorityMax: priorityMax,
        sortBy: sortBy,
        sortOrder: sortOrder,
        limit: limit
    )
}

// Helper function to resolve calendar by name or UUID
func resolveCalendar(identifier: String, remindersService: Reminders) -> EKCalendar? {
    // First try as UUID
    if let calendar = remindersService.calendar(withUUID: identifier) {
        return calendar
    }
    
    // Then try as name
    return remindersService.calendar(withName: identifier)
}

// Search reminders based on provided parameters
func searchReminders(params: SearchParameters, remindersService: Reminders) async throws -> [EKReminder] {
    return try await withCheckedThrowingContinuation { continuation in
        // Determine which calendars to search
        var calendarsToSearch: [EKCalendar] = []
        
        // Process lists parameter (unified names and UUIDs)
        if let lists = params.lists {
            for identifier in lists {
                if let calendar = resolveCalendar(identifier: identifier, remindersService: remindersService),
                   !calendarsToSearch.contains(where: { $0.calendarIdentifier == calendar.calendarIdentifier }) {
                    calendarsToSearch.append(calendar)
                }
            }
        }
        
        // Process calendars parameter (unified names and UUIDs)
        if let calendars = params.calendars {
            for identifier in calendars {
                if let calendar = resolveCalendar(identifier: identifier, remindersService: remindersService),
                   !calendarsToSearch.contains(where: { $0.calendarIdentifier == calendar.calendarIdentifier }) {
                    calendarsToSearch.append(calendar)
                }
            }
        }
        
        // If no specific calendars were requested, search all
        if calendarsToSearch.isEmpty {
            calendarsToSearch = remindersService.getCalendars()
        }
        
        // Apply exclude filters
        if let excludeLists = params.excludeLists {
            calendarsToSearch = calendarsToSearch.filter { calendar in
                !excludeLists.contains { identifier in
                    calendar.title == identifier || calendar.calendarIdentifier == identifier
                }
            }
        }
        
        if let excludeCalendars = params.excludeCalendars {
            calendarsToSearch = calendarsToSearch.filter { calendar in
                !excludeCalendars.contains { identifier in
                    calendar.title == identifier || calendar.calendarIdentifier == identifier
                }
            }
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
            
            // Filter by priority levels
            if let priorities = params.priorities {
                filteredReminders = filteredReminders.filter { reminder in
                    let reminderPriority = priorityFromRawValue(reminder.priority) ?? .none
                    return priorities.contains(reminderPriority)
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
            
            // Return the filtered reminders directly using EKReminder+Encodable
            continuation.resume(returning: filteredReminders)
        }
    }
}

// Helper function to convert raw priority value to Priority enum
func priorityFromRawValue(_ value: Int) -> Priority? {
    // Priority uses 0-3 scale
    switch value {
    case 0:
        return Priority.none
    case 1:
        return .low
    case 2:
        return .medium
    case 3:
        return .high
    default:
        return Priority.none
    }
}

// Run the Configuration command defined above
Configuration.main()
