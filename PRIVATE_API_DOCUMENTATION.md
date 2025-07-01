# Private Reminders API Integration

This document describes the integration of Apple's private Reminders APIs alongside the public EventKit framework.

## Overview

The application uses a compile-time flag system to conditionally include private API functionality:

- **Public Mode**: Uses EventKit for baseline functionality (safe, App Store-compatible)
- **Private Mode**: Uses RemindersUICore.framework and ReminderKit.framework for enhanced features

## Architecture

### Compile-Time Flags

```swift
#if PRIVATE_REMINDERS_ENABLED
// Private API code here
#endif
```

### Key Components

1. **PrivateRemindersLoader**: Loads private frameworks at runtime
2. **UnifiedReminder**: Bridges public and private reminder data
3. **PrivateRemindersService**: Handles private API operations
4. **PrivateAPICommands**: New CLI commands for private features

## Features Comparison

| Feature | Public (EventKit) | Private (RemindersUICore) |
|---------|-------------------|---------------------------|
| Basic reminder access | ✅ | ✅ |
| Subtask info / parent links | ❌ | ✅ |
| Tags / structured notes | ❌ | ✅ |
| Attachments | ❌ | ✅ |
| Rich metadata / flags | ❌ | ✅ |

## Build Configurations

### Debug Build (Private APIs Enabled)
```bash
swift build --configuration debug -Xswiftc -DPRIVATE_REMINDERS_ENABLED
```

### Release Build (EventKit Only)
```bash
swift build --configuration release -Xswiftc -warnings-as-errors --arch arm64 --arch x86_64
```

## Setup Requirements for Private APIs

1. **Compile-time flag**: `-DPRIVATE_REMINDERS_ENABLED`
2. **Security settings**:
   - Disable App Sandbox
   - Disable Hardened Runtime
   - Disable Library Validation
3. **Framework loading**: Automatic via `PrivateRemindersLoader`

## New CLI Commands

### Tag Management
- `show-tags`: List all available tags
- `filter-by-tag <tag> [--list <list>]`: Filter reminders by tag
- `add-tag <list> <reminder> <tag>`: Add tag to reminder
- `remove-tag <list> <reminder> <tag>`: Remove tag from reminder

### Subtask Operations
- `show-subtasks <list> <reminder>`: Display subtasks for a reminder
- `add-subtask <list> <parent> <title>`: Create a subtask

### System Information
- `private-api-status`: Check private API availability

## Graceful Degradation

The application gracefully handles cases where private APIs are not available:

1. **Compile-time**: Stub implementations when `PRIVATE_REMINDERS_ENABLED` is not defined
2. **Runtime**: Framework loading failures result in EventKit-only mode
3. **User feedback**: Clear messaging about available features

## Error Handling

Private API operations can fail with:
- `PrivateAPIError.notAvailable`: Private APIs not compiled in or loaded
- `PrivateAPIError.accessDenied`: Permission denied for private API access
- `PrivateAPIError.methodNotFound`: Expected private API method not found

## Security Considerations

- Private APIs are disabled by default in release builds
- Require explicit build configuration to enable
- Framework loading is done safely with error handling
- No impact on public API functionality when disabled

## Implementation Status

### ✅ Completed
- Compile-time flag system
- Runtime framework loading
- Unified reminder model
- Command structure for private features
- Graceful fallback mechanisms

### 🚧 Pending Implementation
- Actual private API method calls (requires framework headers)
- Tag management implementation
- Subtask operations implementation
- Enhanced metadata extraction

## Future Development

When private API headers become available:
1. Update `PrivateRemindersService` with actual API calls
2. Implement `UnifiedReminder` private API constructor
3. Add comprehensive error handling
4. Extend test coverage for private features

## Testing

Private API features should be tested with:
- Both enabled and disabled configurations
- Framework loading success/failure scenarios
- Permission grant/denial scenarios
- All command variations with appropriate error handling