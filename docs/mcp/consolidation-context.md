# Reminders MCP Consolidation – Context

This document captures the key files and existing behaviours that will be touched while consolidating the Reminders MCP server into the new five-tool surface.

## Swift Targets

- `Sources/reminders-mcp/RemindersMCPServer.swift`  
  Contains all current `@MCPTool` endpoints (`lists_*`, `reminders_*`, `search`, `reminders_get_overview`, `reminders_bulk_*`). Provides helper methods such as `resolveCalendar`, `resolveReminder`, `fetchReminders`, `sortReminders`. This file will be refactored to expose the new consolidated tools and shared helpers.

- `Sources/reminders-mcp/RemindersMCP.swift`  
  CLI entry point that instantiates `RemindersMCPServer`. No functional changes required, but ensure the new server API compiles with SwiftMCP.

- `Sources/RemindersLibrary/Reminders.swift`  
  Wrapper around `EKEventStore` with calendar/reminder operations (`createReminder`, `updateReminder`, `deleteReminder`, `setReminderComplete`, `getReminderByUUID`, etc.). Bulk and manage actions rely on these methods.

- `Sources/RemindersLibrary/SmartParsing.swift`  
  Provides `Priority(fromString:)`, `TitleParser.parse`, and metadata extraction supporting natural-language dates, list hints, and tags. Reused in create/update flows.

- `Sources/RemindersLibrary/EKReminder+Encodable.swift`  
  Adds `Encodable` conformance to `EKReminder`/`EKCalendar`. Confirm new fields (e.g., tags, grouping metadata) remain covered or extend encoder.

- `Sources/RemindersLibrary/NaturalLanguage.swift`  
  Natural-language date parsing helper used by SmartParsing and due-date handling.

## Documentation & Resources

- `docs/mcp/implementation-plan.md`, `docs/mcp/swiftmcp-migration-plan.md`  
  Previous MCP documentation. Must be updated or superseded with new tool schemas and DSL references.

- `API_DOCUMENTATION.md`  
  Public-facing description of current CLI/MCP endpoints. Needs revision to describe the consolidated tools.

- Potential new docs/resources  
  - Search DSL reference  
  - Prompt examples (cookbook)  
  - Priority/field mapping tables for MCP clients

## Testing

- `Tests/RemindersTests`  
  Existing unit tests (e.g., `SmartParsingTests`) and any new tests added for MCP functionality. Additional tests needed for consolidated tool behaviour, search DSL evaluation, and bulk actions.

## Build & Toolchain

- `Package.swift`  
  Depends on SwiftMCP. Ensure new files are added to appropriate targets.

- CLI helpers/scripts (`Makefile`, `start-reminders-api-service.sh`) remain unaffected but may be used to validate builds.

## Key Considerations

- **Archive Behaviour**: We will introduce archive-aware actions. Ensure `Reminders` helper can move reminders between calendars and detect/create archive lists.
- **Search DSL**: Requires new data models and parsing logic (likely new Swift files under `Sources/reminders-mcp/`).
- **Backward Compatibility**: Not required; existing tool names can be removed.
- **Schema Validation**: SwiftMCP derives JSON schemas from method signatures. The new request structs must express validation clearly to avoid ambiguous optional fields.
- **Error Handling**: Consolidated tools must return actionable errors (e.g., missing archive list) for LLM clients to recover.

