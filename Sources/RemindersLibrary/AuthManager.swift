import Foundation
import Hummingbird

// MARK: - Logging System

public enum LogLevel: String, CaseIterable, Comparable {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
    
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        let order: [LogLevel] = [.debug, .info, .warn, .error]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
    
    public init?(string: String) {
        switch string.uppercased() {
        case "DEBUG", "D": self = .debug
        case "INFO", "I": self = .info
        case "WARN", "WARNING", "W": self = .warn
        case "ERROR", "ERR", "E": self = .error
        default: return nil
        }
    }
}

public class Logger {
    public static var shared = Logger()
    public var level: LogLevel = .info
    
    private init() {
        // Check environment variable on initialization
        if let envLevel = ProcessInfo.processInfo.environment["LOG_LEVEL"],
           let logLevel = LogLevel(string: envLevel) {
            self.level = logLevel
        }
    }
    
    public func setLevel(_ level: LogLevel) {
        self.level = level
    }
    
    private func log(_ level: LogLevel, _ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard level >= self.level else { return }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = (file as NSString).lastPathComponent
        print("[\(timestamp)] [\(level.rawValue)] [\(filename):\(line)] \(message)")
    }
    
    public func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message, file: file, function: function, line: line)
    }
    
    public func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message, file: file, function: function, line: line)
    }
    
    public func warn(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warn, message, file: file, function: function, line: line)
    }
    
    public func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message, file: file, function: function, line: line)
    }
}

/// Class for managing API authentication
public class AuthManager {
    private let configURL: URL
    private var adminToken: String?
    private var requireAuth: Bool
    
    /// Initialize the auth manager with config storage in user application support directory
    public init() {
        // Set up configuration storage path
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let remindersDirectory = appSupportURL.appendingPathComponent("reminders-cli", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: remindersDirectory, withIntermediateDirectories: true)
        
        // Set config file path
        self.configURL = remindersDirectory.appendingPathComponent("auth_config.json")
        
        // Default to not requiring auth
        self.requireAuth = false
        
        Logger.shared.debug("AuthManager initialized with config at: \(configURL.path)")
        
        // Load existing config
        loadConfig()
    }
    
    /// Initializes the auth manager with an environment variable or command line token
    public init(token: String?, requireAuth: Bool = false) {
        // Set up configuration storage path (same as default init)
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let remindersDirectory = appSupportURL.appendingPathComponent("reminders-cli", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: remindersDirectory, withIntermediateDirectories: true)
        
        // Set config file path
        self.configURL = remindersDirectory.appendingPathComponent("auth_config.json")
        
        // Set the admin token if provided
        self.adminToken = token
        self.requireAuth = requireAuth
        
        Logger.shared.info("AuthManager initialized - token: \(token != nil ? "provided" : "none"), requireAuth: \(requireAuth)")
        
        // Save config
        saveConfig()
    }
    
    /// Check if authentication is required
    public var isAuthRequired: Bool {
        return requireAuth
    }
    
    /// Set whether authentication is required
    public func setAuthRequired(_ required: Bool) {
        Logger.shared.info("Setting auth requirement to: \(required)")
        self.requireAuth = required
        saveConfig()
    }
    
    /// Validate a token
    /// - Parameter token: The token to validate
    /// - Returns: True if the token is valid
    public func isValidToken(_ token: String) -> Bool {
        guard let adminToken = self.adminToken else {
            // If no admin token is set, authentication is disabled
            Logger.shared.debug("Token validation failed: no admin token configured")
            return false
        }
        
        // Simple comparison - the token must match exactly
        let isValid = token == adminToken
        Logger.shared.debug("Token validation: \(isValid ? "successful" : "failed")")
        return isValid
    }
    
    /// Generate a secure random token
    /// - Returns: A cryptographically secure random token
    public func generateToken() -> String {
        // Generate a cryptographically secure random token
        let tokenLength = 32
        var randomBytes = [UInt8](repeating: 0, count: tokenLength)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        let token = Data(randomBytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        // Store the token
        self.adminToken = token
        saveConfig()
        
        Logger.shared.info("Generated new API token")
        
        return token
    }
    
    // MARK: - Private Methods
    
    private struct AuthConfig: Codable {
        var adminToken: String?
        var requireAuth: Bool
    }
    
    private func saveConfig() {
        let config = AuthConfig(adminToken: adminToken, requireAuth: requireAuth)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(config)
            try data.write(to: configURL)
            Logger.shared.debug("Auth config saved successfully")
        } catch {
            Logger.shared.error("Error saving auth config: \(error.localizedDescription)")
            print("Error saving auth config: \(error.localizedDescription)")
        }
    }
    
    private func loadConfig() {
        do {
            if FileManager.default.fileExists(atPath: configURL.path) {
                let data = try Data(contentsOf: configURL)
                let decoder = JSONDecoder()
                let config = try decoder.decode(AuthConfig.self, from: data)
                
                self.adminToken = config.adminToken
                self.requireAuth = config.requireAuth
                Logger.shared.debug("Auth config loaded - token: \(adminToken != nil ? "present" : "none"), requireAuth: \(requireAuth)")
            } else {
                Logger.shared.debug("No auth config file found, using defaults")
            }
        } catch {
            Logger.shared.error("Error loading auth config: \(error.localizedDescription)")
            print("Error loading auth config: \(error.localizedDescription)")
            // Start with default settings if loading fails
            self.adminToken = nil
            self.requireAuth = false
        }
    }
}

// Extensions for authentication
public extension HBRequest {
    // Property to check if a request is authenticated
    var isAuthenticated: Bool {
        get { return self.extensions.get(\.authenticated) ?? false }
    }
    
    // Internal property to set authentication status
    var authenticated: Bool? {
        get { return self.extensions.get(\.authenticated) }
        set { 
            var extensions = self.extensions
            extensions.set(\.authenticated, value: newValue)
            self.extensions = extensions
        }
    }
}

// Extension for application to store global auth requirement
public extension HBApplication {
    // Property to check if authentication is required globally
    var requireAuth: Bool {
        get { return self.extensions.get(\.authRequired) ?? false }
    }
    
    // Property to set if authentication is required globally
    var authRequired: Bool? {
        get { return self.extensions.get(\.authRequired) }
        set { 
            var extensions = self.extensions
            extensions.set(\.authRequired, value: newValue)
            self.extensions = extensions
        }
    }
}

/// Token authentication middleware for Hummingbird
public struct TokenAuthMiddleware: HBMiddleware {
    private let authManager: AuthManager
    private let requireAuth: Bool
    
    public init(authManager: AuthManager, requireAuth: Bool = false) {
        self.authManager = authManager
        self.requireAuth = requireAuth
    }
    
    public func apply(to request: HBRequest, next: HBResponder) -> EventLoopFuture<HBResponse> {
        // Skip auth check if not required by either the middleware setting or auth manager
        if !requireAuth && !authManager.isAuthRequired {
            // Store authentication status in the extensions
            var requestCopy = request
            var ext = requestCopy.extensions
            ext.set(\.authenticated, value: false)
            requestCopy.extensions = ext
            Logger.shared.debug("Request \(request.method) \(request.uri.path) - auth not required, proceeding without authentication")
            return next.respond(to: requestCopy)
        }
        
        // Get the authorization header
        guard let authHeader = request.headers.first(name: "Authorization") else {
            Logger.shared.warn("Request \(request.method) \(request.uri.path) - missing Authorization header")
            return request.failure(.unauthorized, message: "Authentication required")
        }
        
        // Check if it's a Bearer token
        let components = authHeader.split(separator: " ")
        guard components.count == 2,
              components[0].lowercased() == "bearer",
              let token = components.last else {
            Logger.shared.warn("Request \(request.method) \(request.uri.path) - invalid authorization format")
            return request.failure(.unauthorized, message: "Invalid authorization format")
        }
        
        // Validate the token
        if authManager.isValidToken(String(token)) {
            // Store authentication status in the extensions
            var requestCopy = request
            var ext = requestCopy.extensions
            ext.set(\.authenticated, value: true)
            requestCopy.extensions = ext
            Logger.shared.debug("Request \(request.method) \(request.uri.path) - authentication successful")
            return next.respond(to: requestCopy)
        } else {
            Logger.shared.warn("Request \(request.method) \(request.uri.path) - invalid token provided")
            return request.failure(.unauthorized, message: "Invalid token")
        }
    }
}