# Reminders MCP Consolidation – Implementation Plan

Follow these steps alongside the context (`consolidation-context.md`) and specification (`consolidation-spec.md`) to deliver the new tool surface.

## 1. Project Setup

1. Confirm you are on the `swiftmcp-migration` branch (or desired feature branch).  
2. Run `swift build --product reminders-mcp` to ensure baseline compiles.  
3. Create new Swift source files placeholders (they will be populated in later steps):  
   - `Sources/reminders-mcp/ManageModels.swift`  
   - `Sources/reminders-mcp/BulkModels.swift`  
   - `Sources/reminders-mcp/SearchModels.swift`  
   - `Sources/reminders-mcp/AnalyzeModels.swift` (optional; can live in server file)

## 2. Define Request/Response Models

1. In `ManageModels.swift`, declare:
   - `enum ManageAction: String, Decodable` (`create`, `read`, `update`, `delete`, `complete`, `uncomplete`, `move`, `archive`).  
   - `struct ManageRequest: Decodable` with `action` plus optional payloads (`CreatePayload`, `ReadPayload`, etc.).  
   - `struct ManageResponse: Encodable` returning reminder data or success flags.
2. In `BulkModels.swift`, declare:
   - `enum BulkAction: String, Decodable` (`update`, `complete`, `uncomplete`, `move`, `archive`, `delete`).  
   - `struct BulkRequest` with `uuids`, `action`, optional `fields`, `dryRun`.  
   - `struct BulkItemResult`, `struct BulkResponse`.
3. In `SearchModels.swift`, declare the DSL types:
   - `enum Field`, `enum SearchOperator`, `enum LogicNode`.  
   - `struct FilterClause`, `struct SearchGrouping`, `struct SortDescriptor`, `struct SearchRequest`, `struct SearchResponse`, `struct SearchGroup`.
4. Update `Package.swift` target (`reminders-mcp`) if necessary (usually automatic when files are in `Sources/reminders-mcp`).

## 3. Refactor `RemindersMCPServer`

1. Remove existing `@MCPTool` methods (`lists_*`, `reminders_*`, `search`, `reminders_get_overview`, `reminders_bulk_*`).  
2. Add the five new methods with signatures:
   ```swift
   @MCPTool public func reminders_manage(_ request: ManageRequest) async throws -> ManageResponse
   @MCPTool public func reminders_bulk(_ request: BulkRequest) async throws -> BulkResponse
   @MCPTool public func reminders_search(_ request: SearchRequest) async throws -> SearchResponse
   @MCPTool public func reminders_lists(_ request: ListsRequest) async throws -> ListsResponse
   @MCPTool public func reminders_analyze(_ request: AnalyzeRequest) async throws -> AnalyzeResponse
   ```
3. For lists/analyze, create corresponding request/response types (can live near Manage/Bulk models or inside `RemindersMCPServer.swift`).
4. Implement action dispatch:
   - `reminders_manage` → switch on `request.action`, call private helpers (create/read/update/delete/complete/uncomplete/move/archive).
   - `reminders_bulk` → loop `uuids`, call manage helpers, collect `BulkItemResult`s, honour `dryRun`.
   - `reminders_lists` → switch on `request.action` (`list`, `create`, `delete`, `ensureArchive`).
   - `reminders_analyze` → compute overview metrics; additional modes optional.
5. Extract or update helper functions:
   - `parseDueDate(from:)` (natural language + ISO8601).  
   - `applyPriority(reminder:priority:)`.  
   - `move(reminder:to calendar:)` using `Reminders` API.  
   - `ensureArchiveCalendar(named:createIfMissing:)`.  
   - `multiSort(reminders:using descriptors:)`, `group(reminders:by:)`.  
   - `evaluateLogicNode(_:reminder:)` for search DSL.

## 4. Implement Manage & Bulk Helpers

1. Reuse logic from removed methods:
   - Create: smart parsing via `TitleParser`.  
   - Update: apply metadata, explicit fields, completion toggle, due date parsing.  
   - Delete: call `deleteReminder`.  
   - Complete/Uncomplete: `setReminderComplete(reminder, complete: Bool)`.  
   - Move: resolve target calendar; persist via `store.save(reminder, commit: true)`.  
   - Archive: call `ensureArchiveCalendar` then move reminder.
2. Bulk:
   - Validate `uuids` non-empty.  
   - For each item: resolve reminder, apply action, catch errors, push `BulkItemResult`.  
   - Dry run: do not mutate; instead, compute `BulkItemResult` with `wouldChange` flags.  
   - Aggregate totals for response.

## 5. Build Search Engine

1. In `SearchModels.swift`, implement `Decodable` for logic tree and operators.  
2. Add helper methods (possibly extension on `RemindersMCPServer`) to transform `LogicNode` → predicate.  
3. Extend field extraction to cover:
   - Title, notes (strings)  
   - List identifiers/names  
   - Priority bucket (`none`, `low`, `medium`, `high`)  
   - Due dates, completion status, creation/modification dates  
   - Tags (ensure `EKReminder` exposes them or stub with empty array)
4. Grouping: implement functions to group by list/priority/tag and due date granularity (day/week/month).  
5. Sorting: build comparator supporting multiple descriptors; reuse existing `sortReminders` logic but adapt to multi-key.

## 6. Update Documentation

1. Edit/replace `API_DOCUMENTATION.md` section about MCP with the new tools and JSON examples.  
2. Create a new doc (e.g., `docs/mcp/search-dsl.md`) describing filter language, grouping, sorting, pagination.  
3. Add prompt cookbook (e.g., `docs/mcp/prompt-recipes.md`) with example natural-language tasks and matching payloads.  
4. Ensure README or other top-level docs link to new references.

## 7. Testing

1. Add unit tests under `Tests/RemindersTests` (create new test files if needed):  
   - Manage create/update/delete/complete/uncomplete/move/archive success and validation failures.  
   - Bulk actions verifying counts, dry-run behaviour, error reporting.  
   - Search logic: AND/OR/XOR combinations, before/after date filters, grouping + sorting order, pagination edges.  
2. Consider integration test using a lightweight fake EventKit layer or fixtures if available.  
3. Run `swift test` (or `swift build` if tests not in scope) to confirm.

## 8. Cleanup & Verification

1. Remove any obsolete helper methods/files left from previous MCP tools.  
2. Confirm `swift build --product reminders-mcp` succeeds.  
3. If available, generate MCP schema output to verify only five tools are exposed.  
4. Review documentation for accuracy; ensure spec requirements/acceptance criteria are met.  
5. Prepare commit with clear message summarizing consolidation.

