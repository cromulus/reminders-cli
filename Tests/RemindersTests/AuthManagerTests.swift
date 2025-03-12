import XCTest
@testable import RemindersLibrary
import Foundation

final class AuthManagerTests: XCTestCase {
    // Test creating a new AuthManager instance with a token
    func testInitWithToken() {
        let token = "test-token-1234"
        let authManager = AuthManager(token: token)
        
        // Validate that the provided token is considered valid
        XCTAssertTrue(authManager.isValidToken(token))
        
        // Validate that a different token is invalid
        XCTAssertFalse(authManager.isValidToken("different-token"))
        
        // Validate that authentication is not required by default
        XCTAssertFalse(authManager.isAuthRequired)
    }
    
    // Test creating a new AuthManager with explicit nil token
    func testInitWithoutToken() {
        // Explicitly pass nil to ensure no existing token is loaded
        let authManager = AuthManager(token: nil)
        
        // Validate that authentication is not required by default
        XCTAssertFalse(authManager.isAuthRequired)
        
        // Any token should be invalid since no token is configured
        XCTAssertFalse(authManager.isValidToken("some-random-token"))
    }
    
    // Test setting auth required
    func testSetAuthRequired() {
        let authManager = AuthManager()
        
        // Check default value
        XCTAssertFalse(authManager.isAuthRequired)
        
        // Set auth required to true
        authManager.setAuthRequired(true)
        XCTAssertTrue(authManager.isAuthRequired)
        
        // Set auth required to false
        authManager.setAuthRequired(false)
        XCTAssertFalse(authManager.isAuthRequired)
    }
    
    // Test token generation
    func testGenerateToken() {
        let authManager = AuthManager()
        
        // Generate a token
        let token = authManager.generateToken()
        
        // Verify token is not empty
        XCTAssertFalse(token.isEmpty)
        
        // Verify token is valid
        XCTAssertTrue(authManager.isValidToken(token))
        
        // Verify token length is appropriate (at least 32 bytes = 43+ chars in base64)
        XCTAssertGreaterThan(token.count, 40)
    }
    
    // Test that consecutive calls to generateToken change the active token
    func testGenerateTokenChangesActiveToken() {
        let authManager = AuthManager()
        
        // Generate first token
        let token1 = authManager.generateToken()
        XCTAssertTrue(authManager.isValidToken(token1))
        
        // Generate second token
        let token2 = authManager.generateToken()
        XCTAssertTrue(authManager.isValidToken(token2))
        
        // First token should no longer be valid
        XCTAssertFalse(authManager.isValidToken(token1))
    }
    
    // Test token validation with nil token
    func testTokenValidationWithNilToken() {
        let authManager = AuthManager()
        
        // When no token is configured, validation should return false
        XCTAssertFalse(authManager.isValidToken("any-token"))
    }
    
    // Test initializing with custom values
    func testInitWithCustomValues() {
        let token = "custom-token"
        let requireAuth = true
        let authManager = AuthManager(token: token, requireAuth: requireAuth)
        
        XCTAssertTrue(authManager.isAuthRequired)
        XCTAssertTrue(authManager.isValidToken(token))
    }
    
    // Test token format - should be URL safe
    func testGeneratedTokenIsURLSafe() {
        let authManager = AuthManager()
        let token = authManager.generateToken()
        
        // Check that token doesn't contain URL-unsafe characters
        XCTAssertFalse(token.contains("+"))
        XCTAssertFalse(token.contains("/"))
        XCTAssertFalse(token.contains("="))
    }
}