import Foundation
import Hummingbird

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
        
        // Save config
        saveConfig()
    }
    
    /// Check if authentication is required
    public var isAuthRequired: Bool {
        return requireAuth
    }
    
    /// Set whether authentication is required
    public func setAuthRequired(_ required: Bool) {
        self.requireAuth = required
        saveConfig()
    }
    
    /// Validate a token
    /// - Parameter token: The token to validate
    /// - Returns: True if the token is valid
    public func isValidToken(_ token: String) -> Bool {
        guard let adminToken = self.adminToken else {
            // If no admin token is set, authentication is disabled
            return false
        }
        
        // Simple comparison - the token must match exactly
        return token == adminToken
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
        } catch {
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
            }
        } catch {
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
    
    public init(authManager: AuthManager, requireAuth: Bool = true) {
        self.authManager = authManager
        self.requireAuth = requireAuth
    }
    
    public func apply(to request: HBRequest, next: HBResponder) -> EventLoopFuture<HBResponse> {
        // Skip auth check if not required
        if !requireAuth && !authManager.isAuthRequired {
            // Store authentication status in the extensions
            var requestCopy = request
            var ext = requestCopy.extensions
            ext.set(\.authenticated, value: false)
            requestCopy.extensions = ext
            return next.respond(to: requestCopy)
        }
        
        // Get the authorization header
        guard let authHeader = request.headers.first(name: "Authorization") else {
            return request.failure(.unauthorized, message: "Authentication required")
        }
        
        // Check if it's a Bearer token
        let components = authHeader.split(separator: " ")
        guard components.count == 2,
              components[0].lowercased() == "bearer",
              let token = components.last else {
            return request.failure(.unauthorized, message: "Invalid authorization format")
        }
        
        // Validate the token
        if authManager.isValidToken(String(token)) {
            // Store authentication status in the extensions
            var requestCopy = request
            var ext = requestCopy.extensions
            ext.set(\.authenticated, value: true)
            requestCopy.extensions = ext
            return next.respond(to: requestCopy)
        } else {
            return request.failure(.unauthorized, message: "Invalid token")
        }
    }
}