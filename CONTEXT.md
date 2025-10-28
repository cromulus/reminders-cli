# Project Context Documentation

## Project Overview

**reminders-hassio-todo** (also known as reminders-cli) is a comprehensive Swift-based solution for programmatic access to macOS Reminders. It consists of two main components:

1. **reminders** - A command-line interface (CLI) tool for managing reminders from the terminal
2. **reminders-api** - A REST API server built with Hummingbird that exposes reminders functionality over HTTP

The project uniquely leverages private macOS APIs to access features not available through the standard EventKit framework, including subtasks, URL attachments, and mail links.

### Key Capabilities

- Full CRUD operations on reminders and lists
- Advanced search with complex filtering
- Real-time webhook notifications for reminder changes
- Private API access to subtasks, URL attachments, and mail links
- Optional token-based authentication
- n8n workflow integration nodes
- macOS service installation for background operation

## Project Structure

### Core Directories

```
/Users/bill/Dropbox/code/reminders-hassio-todo/
├── Sources/
│   ├── reminders/              # CLI application entry point
│   ├── reminders-api/          # REST API server entry point
│   └── RemindersLibrary/       # Shared business logic library
├── Tests/
│   └── RemindersTests/         # Test suite
├── .github/workflows/          # CI/CD automation
└── [Root configuration files]
```

### Key Files

**Entry Points:**
- `/Sources/reminders/main.swift` - CLI application
- `/Sources/reminders-api/main.swift` - REST API server (1282 lines)

**Core Library (`RemindersLibrary/`):**
- `Reminders.swift` - Core business logic, EventKit interactions (794 lines)
- `EKReminder+PrivateAPI.swift` - Private API access for subtasks/URLs (108 lines)
- `EKReminder+Encodable.swift` - JSON serialization for API responses (116 lines)
- `WebhookManager.swift` - Event detection and webhook delivery (515 lines)
- `AuthManager.swift` - Authentication and logging (303 lines)
- `CLI.swift` - Command-line parsing and commands
- `NaturalLanguage.swift` - Date parsing utilities
- `Sort.swift` - Sorting utilities

**Configuration:**
- `Package.swift` - Swift Package Manager configuration
- `Makefile` - Build and packaging automation
- `.github/workflows/swift.yml` - CI/CD pipeline

**Documentation:**
- `README.md` - User-facing documentation (962 lines)
- `API_DOCUMENTATION.md` - Comprehensive API reference (1374 lines)
- `TAGS_IMPLEMENTATION_PLAN.md` - Future feature planning

## Technology Stack

### Language & Framework
- **Language:** Swift 5.9+
- **Platform:** macOS 10.15+
- **Build System:** Swift Package Manager
- **Architectures:** Universal binary (ARM64 + x86_64)

### Dependencies

**From Package.swift:**
```swift
.package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "1.3.1"))
.package(url: "https://github.com/hummingbird-project/hummingbird.git", .upToNextMinor(from: "1.8.2"))
```

**Key Libraries:**
- **ArgumentParser** - CLI command parsing and help generation
- **Hummingbird** - Lightweight HTTP server framework
- **HummingbirdFoundation** - Additional Hummingbird utilities
- **EventKit** - macOS framework for calendar/reminder access

### External Integrations
- **n8n** - Workflow automation platform (custom nodes available)
- **Webhooks** - Real-time event notifications via HTTP POST
- **macOS Reminders** - Native integration via EventKit

## Architecture

### Architectural Pattern

**Layered Architecture with Event-Driven Components:**

```
┌─────────────────────────────────────────────┐
│         Entry Points (CLI/API)              │
│  - reminders (CLI commands)                 │
│  - reminders-api (HTTP routes)              │
└────────────────┬────────────────────────────┘
                 │
┌────────────────▼────────────────────────────┐
│        Business Logic Layer                 │
│  - Reminders (core operations)              │
│  - AuthManager (authentication)             │
│  - WebhookManager (event handling)          │
└────────────────┬────────────────────────────┘
                 │
┌────────────────▼────────────────────────────┐
│         Data Access Layer                   │
│  - EventKit (public API)                    │
│  - Private APIs (via Objective-C runtime)   │
└─────────────────────────────────────────────┘
```

### Data Flow

**CLI Flow:**
1. User invokes command (e.g., `reminders show Work`)
2. ArgumentParser parses command and flags
3. Reminders class fetches data from EventKit
4. Results formatted and displayed (JSON or plain text)

**API Flow:**
1. HTTP request arrives at Hummingbird router
2. Authentication middleware validates token (if required)
3. Route handler calls Reminders service
4. EventKit performs async data fetch
5. Results encoded as JSON and returned
6. Webhooks triggered for any data changes

**Webhook Event Flow:**
1. EventKit sends `EKEventStoreChanged` notification
2. WebhookManager compares current vs previous state
3. Detects created/updated/deleted/completed/uncompleted events
4. Filters reminders against webhook configurations
5. Delivers HTTP POST to matching webhook URLs

### State Management

**Stateless Design:**
- CLI: No persistent state between invocations
- API: Stateless HTTP handlers using async/await patterns

**State Storage:**
- Reminders data: Stored in macOS Reminders.app database (accessed via EventKit)
- Webhook configs: JSON file in `~/Library/Application Support/reminders-cli/webhooks.json`
- Auth config: JSON file in `~/Library/Application Support/reminders-cli/auth_config.json`
- Previous reminder state: In-memory cache in WebhookManager for change detection

### Error Handling

**CLI Error Handling:**
- ArgumentParser validates inputs automatically
- Errors printed to stdout with `exit(1)`
- Semaphores used for synchronous EventKit operations

**API Error Handling:**
- HTTP status codes (400, 401, 404, 500)
- JSON error responses: `{"error": "message", "status": 400}`
- Logging at multiple levels (DEBUG, INFO, WARN, ERROR)
- Graceful degradation for optional features

## Constraints

### Technical Constraints

**Platform-Specific:**
- **macOS only** - Relies on EventKit and private Reminders framework
- **TCC Permissions Required** - User must grant Reminders access
- **LaunchAgent Complexity** - Service mode requires careful permission handling

**Private API Risks:**
- **API Stability** - Private APIs may break across macOS versions
- **App Store Restrictions** - Cannot distribute via App Store
- **Maintenance Burden** - Requires testing on each macOS release

**Concurrency:**
- EventKit uses callback-based async API
- Wrapped in Swift async/await using continuations
- Semaphores used for CLI synchronous behavior
- Webhook delivery on background queue

### Business Constraints

**Authentication Model:**
- Optional by default (can be toggled to required)
- Single admin token (no multi-user support)
- Token stored in plaintext config file
- No token rotation or expiration

**Webhook Limitations:**
- No retry logic for failed deliveries
- 5-second timeout per delivery
- No rate limiting on webhook triggers
- No signature verification for security

### Performance Considerations

**EventKit Performance:**
- Fetching all reminders can be slow (async callback pattern)
- No built-in pagination in EventKit API
- Search implemented client-side (filters in memory)
- Change detection requires full state comparison

**Recommended Limits:**
- Limit search results via `limit` parameter
- Use specific list filters to reduce data fetching
- Configure webhook filters narrowly to reduce event volume

### Security Considerations

**Authentication:**
- Bearer token authentication (optional)
- Tokens stored in user application support directory
- No HTTPS enforcement (localhost default)
- CORS enabled for all origins (development-friendly, production risk)

**Private API Usage:**
- Uses Objective-C runtime reflection (`NSSelectorFromString`)
- Accesses private backing objects (`backingObject`, `_reminder`)
- No sandboxing restrictions (macOS service context)

**Data Access:**
- Full access to all user reminders
- No row-level security or user isolation
- Webhook URLs receive sensitive reminder data
- No data encryption at rest

## Current State

### What Works

**Core Functionality:**
- ✅ CLI commands for all CRUD operations
- ✅ REST API with comprehensive endpoints
- ✅ Authentication (optional token-based)
- ✅ Webhook system with event filtering
- ✅ Private API access (subtasks, URLs, mail links)
- ✅ Search with advanced filtering
- ✅ JSON and plain text output formats
- ✅ macOS service installation
- ✅ n8n integration nodes
- ✅ Universal binary builds (ARM64 + x86_64)

**Testing:**
- ✅ Test suite exists in `/Tests/RemindersTests/`
- ✅ GitHub Actions CI/CD workflow
- ✅ Multiple test files covering different components

### Known Issues

**From TAGS_IMPLEMENTATION_PLAN.md:**
- Tags feature is planned but not fully implemented
- Command stubs exist (`ShowTags`, `FilterByTag`, `AddTag`, `RemoveTag`)
- Read-only tag access partially implemented
- Write operations for tags not completed

**TCC Permission Challenges:**
- LaunchAgent service may return empty results without proper permissions
- Binary must be granted Reminders access separately from Terminal
- Documentation includes extensive troubleshooting guide

**Limitations:**
- EventKit's `url` field is typically null (documented Apple limitation)
- URL attachment write operations not implemented
- Subtask creation not implemented (read-only)

### Areas Needing Attention

**Technical Debt:**
1. **Priority Mapping Inconsistency**
   - Recent commits mention fixing priority mapping (0-3 scale)
   - May have legacy code using different scales

2. **Error Handling**
   - Some functions use `exit(1)` instead of throwing errors
   - Inconsistent error messages between CLI and API

3. **Testing Coverage**
   - Several test files are stubs (171 bytes suggests placeholder content)
   - Need more comprehensive integration tests

4. **Documentation**
   - Extensive documentation but may need updates after recent changes
   - n8n nodes mentioned as "new in v1.1.0" but integration details sparse

**Security Improvements:**
- Add HTTPS support for production deployments
- Implement webhook signature verification
- Add token rotation capabilities
- Restrict CORS origins in production mode

**Performance Optimizations:**
- Implement caching layer for frequently accessed lists
- Add pagination support in API endpoints
- Optimize change detection in WebhookManager
- Consider database for webhook event history

### Recent Changes

**From Git History:**
```
3763e63 we already had nodes
8d65cff Add n8n nodes package for reminders-api
b398548 Fix priority mapping to use correct 0-3 scale
86d4a67 Enhance API with unified list/calendar filtering and improved priority mapping
bbbd415 Enhance search API with advanced filtering options
```

**Key Recent Enhancements:**
1. **n8n Integration** - Added comprehensive n8n nodes package
2. **Priority Mapping Fix** - Corrected priority scale to 0-3
3. **Advanced Search** - Enhanced filtering with calendar/list exclusions
4. **Unified Filtering** - Calendar and list parameters now accept names or UUIDs

## Project-Specific Conventions

### Code Organization

**File Naming:**
- Swift files use PascalCase
- Extensions use pattern: `TypeName+Extension.swift`
- Test files mirror source files with `Tests` suffix

**Code Style:**
- 4-space indentation
- Extensive inline comments explaining private API usage
- Descriptive variable names (prefer clarity over brevity)
- Functions returning values vs void based on side effects

### Private API Pattern

**Established Pattern (from `EKReminder+PrivateAPI.swift`):**
```swift
1. Access backing object via `backingObject` selector
2. Call `_reminder` on backing object
3. Use `NSSelectorFromString` for private method calls
4. Handle `Unmanaged` values with `takeUnretainedValue()`
5. Provide computed properties as public interface
6. Document NOTE comments explaining private API usage
```

**Example:**
```swift
var attachedUrl: URL? {
    let attachmentsSelector = NSSelectorFromString("attachments")
    guard let backingObj = reminderBackingObject,
          let unmanagedAttachments = backingObj.perform(attachmentsSelector),
          let attachments = unmanagedAttachments.takeUnretainedValue() as? [AnyObject] else {
        return nil
    }
    // Process attachments...
}
```

### API Design

**Endpoint Patterns:**
- RESTful resource naming (e.g., `/reminders`, `/lists`, `/webhooks`)
- UUID-based operations preferred over index-based
- Legacy endpoints maintained for backward compatibility
- Query parameters for filtering, not path segments

**Response Formats:**
- JSON with pretty printing and sorted keys
- ISO8601 dates with internet format
- UUIDs without `x-apple-reminder://` prefix in API responses
- Consistent error response structure

### Testing Strategy

**Test Organization:**
- Unit tests for individual functions
- Integration tests for API endpoints
- Component-specific test files (Auth, Webhooks, etc.)
- Natural language parsing tests

**Current Test Files:**
- `APIEndpointTests.swift` (131 bytes - likely stub)
- `AuthManagerTests.swift` (3804 bytes - substantive)
- `NaturalLanguageTests.swift` (5012 bytes - comprehensive)
- Several stub files needing implementation

### Build System

**Makefile Targets:**
```makefile
build-release    # Build CLI + API for production
build-api        # Build only API server
run-api          # Build and run API server
test             # Run all tests
test-single      # Run specific test
package          # Create CLI distribution tarball
package-api      # Create API distribution tarball
clean            # Clean build artifacts
```

**Compiler Flags:**
- `--arch arm64 --arch x86_64` - Universal binaries
- `-Xswiftc -enable-upcoming-feature -Xswiftc DisableSwift6Isolation` - Future Swift features

### Deployment

**Service Installation:**
- LaunchAgent plist configuration
- Installation scripts with TCC permission handling
- Automatic startup on login
- Log files in `/tmp/reminders-api-service.{out,err}`

**Production Deployment:**
- `deploy-production.sh` script for remote servers
- Token generation and configuration
- Service installation and verification
- SSH-based deployment

## Questions and Uncertainties

### Private API Stability

**Question:** How stable are the private APIs across macOS versions?

**Context:** The project uses `NSSelectorFromString` to access:
- `backingObject` → `_reminder` → `attachments`
- `parentReminderID` → `uuid`
- `userActivity` → `storage`

**Risk:** These selectors could change or be removed in future macOS releases.

**Mitigation:** Need to test on each new macOS version and potentially version-guard private API access.

### n8n Integration Status

**Question:** What is the current state of the n8n integration?

**Evidence:**
- API_DOCUMENTATION.md mentions "New in v1.1.0"
- Recent commit: "we already had nodes"
- Documentation shows comprehensive node types

**Uncertainty:**
- Are the n8n nodes published to npm?
- Where is the node source code located?
- Is there a separate package or embedded in this repo?

**Need:** Clarification on n8n node distribution and maintenance.

### Test Coverage

**Question:** What is the actual test coverage?

**Observation:** Several test files are extremely small (171 bytes), suggesting stubs.

**Files needing investigation:**
- `EKReminderEncodableTests.swift`
- `RemindersAPITests.swift`
- `RemindersTests.swift`
- `SortTests.swift`
- `TokenAuthMiddlewareTests.swift`

**Action needed:** Expand test coverage or remove placeholder files.

### Priority System

**Question:** Is the priority system fully consistent after recent fixes?

**Evidence:**
- Commit b398548: "Fix priority mapping to use correct 0-3 scale"
- Code uses both raw values and `Priority` enum
- API accepts string values ("none", "low", "medium", "high")

**Potential issues:**
- Legacy code may use old scale
- Documentation may reference incorrect values
- API validation may not be comprehensive

### Authentication Security

**Question:** Is the current authentication model sufficient for production?

**Current state:**
- Optional token authentication
- Single admin token
- No token rotation
- Plaintext storage
- No expiration

**Considerations:**
- Is multi-user support planned?
- Should tokens expire?
- Is HTTPS enforcement needed?
- Should webhook deliveries be signed?

### Webhook Reliability

**Question:** How should webhook delivery failures be handled?

**Current behavior:**
- No retry logic
- 5-second timeout
- Fire-and-forget delivery
- No delivery confirmation

**Unknowns:**
- Should failed deliveries be logged?
- Should there be a retry queue?
- Should webhooks be disabled after repeated failures?
- Should delivery history be persisted?

## Next Steps for Context Continuation

When resuming work on this project, consider investigating:

1. **n8n Node Package** - Locate and document the n8n integration source
2. **Test Coverage** - Run coverage analysis and expand stub tests
3. **Priority System Audit** - Verify consistency across CLI, API, and documentation
4. **Tags Feature** - Review TAGS_IMPLEMENTATION_PLAN.md and decide on implementation
5. **Security Hardening** - Evaluate authentication and webhook security requirements
6. **Performance Profiling** - Test with large reminder datasets
7. **macOS Version Compatibility** - Test private APIs on latest macOS release

---

**Context Documentation Created:** 2025-10-16

**Codebase Branch:** reminders-hassio-todo (clean working tree)

**Last Commit:** 3763e63 "we already had nodes"

**Total Lines Analyzed:** ~8,000+ across 33 files
