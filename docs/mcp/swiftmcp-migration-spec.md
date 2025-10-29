# SwiftMCP Migration Specification

## Overview

Complete migration of the reminders-cli MCP server from custom `modelcontextprotocol/swift-sdk` + Hummingbird implementation to SwiftMCP framework.

## Goals

1. **Eliminate Custom Code**: Remove ~660 lines of custom transport/protocol handling
2. **Maintain Functionality**: All existing tools and resources continue working
3. **Improve Maintainability**: Use community-maintained transport layer
4. **Add Features**: Gain OAuth, bearer token auth, OpenAPI support
5. **Preserve REST API**: Keep `reminders-api` on Hummingbird unchanged

## Non-Goals

- Backward compatibility (breaking changes acceptable)
- WebSocket transport
- Real-time push notifications (still use polling)
- Modifying REST API functionality

## Success Criteria

### 1. Functional Requirements

#### 1.1 Tools Work Identically

**Lists Tool:**
- ✅ GET all lists returns same data structure
- ✅ CREATE list creates and returns new list
- ✅ DELETE list removes list (or returns appropriate error)

**Reminders Tool:**
- ✅ CREATE reminder with all fields (title, notes, dueDate, priority)
- ✅ GET reminder by UUID (both formats: with/without prefix)
- ✅ UPDATE reminder fields selectively
- ✅ DELETE reminder
- ✅ COMPLETE/UNCOMPLETE reminder
- ✅ LIST reminders in a list

**Search Tool:**
- ✅ Text query search in title/notes
- ✅ Filter by lists, completion status, priority
- ✅ Filter by date ranges (dueBefore, dueAfter)
- ✅ Filter by hasNotes, hasDueDate
- ✅ Sort by title, dueDate, priority
- ✅ Limit results

#### 1.2 Resources Work Identically

- ✅ `reminders://lists` returns all lists
- ✅ `reminders://list/{name}` returns reminders in list
- ✅ `reminders://list/{uuid}` returns reminders by list UUID
- ✅ `reminders://uuid/{id}` returns single reminder
- ✅ UUID format handling (both with/without prefix)

#### 1.3 Transports Function

**Stdio Transport:**
- ✅ Accepts JSON-RPC from stdin
- ✅ Writes responses to stdout
- ✅ Logs to stderr (when verbose)
- ✅ Works with Claude Desktop

**HTTP Transport:**
- ✅ Listens on configured host:port
- ✅ Serves MCP over SSE
- ✅ Handles sessions properly
- ✅ CORS configured correctly
- ✅ Works with HTTP clients

#### 1.4 Error Handling

- ✅ Permission denied (Reminders access)
- ✅ List not found
- ✅ Reminder not found
- ✅ Invalid parameters
- ✅ Parse errors
- ✅ Clear, LLM-friendly error messages

### 2. Code Quality Requirements

#### 2.1 Code Reduction
- ✅ Delete 4 files (~660 lines)
- ✅ Create 1 new file (~300 lines)
- ✅ Net reduction: ~360 lines
- ✅ Zero custom transport code

#### 2.2 Architecture
- ✅ Use `@MCPServer` macro for server
- ✅ Use `@MCPTool` macro for each tool
- ✅ Leverage SwiftMCP transports
- ✅ Reuse existing business logic where possible
- ✅ Clean separation of concerns

#### 2.3 Documentation
- ✅ Update `CLAUDE.md` with new commands
- ✅ Document OAuth/bearer token usage
- ✅ Update build instructions
- ✅ Document transport configuration

### 3. Performance Requirements

| Operation | Requirement |
|-----------|-------------|
| Lists GET | < 300ms |
| Reminder CREATE | < 500ms |
| Reminder GET | < 300ms |
| Search (simple) | < 1s |
| Search (complex) | < 2s |

**Note:** Performance should be similar or better than current implementation.

### 4. Compatibility Requirements

- ✅ macOS 15.0+
- ✅ Swift 6.0+
- ✅ Xcode 16+
- ✅ Claude Desktop compatibility (stdio)
- ✅ HTTP client compatibility (curl, Postman, etc.)
- ✅ Home Assistant integration unaffected (uses REST API)

## Acceptance Criteria

### AC1: Stdio Transport Works

**Given** reminders-mcp is started with `--transport stdio`
**When** a JSON-RPC request is sent to stdin
**Then** a valid JSON-RPC response is written to stdout
**And** no errors appear on stderr (except verbose logging)

### AC2: HTTP Transport Works

**Given** reminders-mcp is started with `--transport http --port 8090`
**When** a client connects to `http://localhost:8090`
**Then** an SSE connection is established
**And** MCP messages can be sent/received
**And** sessions are maintained correctly

### AC3: Lists Tool Functions

**When** calling getLists()
**Then** all reminder lists are returned with names and UUIDs

**When** calling createList(name: "Shopping")
**Then** a new list "Shopping" is created
**And** it appears in subsequent getLists() calls

**When** calling deleteList(name: "Shopping")
**Then** the list is removed
**And** an error is returned if list doesn't exist

### AC4: Reminders Tool Functions

**When** calling createReminder(list: "Work", title: "Review PR", dueDate: "2025-10-20T14:00:00Z", priority: "high")
**Then** a new reminder is created with all fields
**And** a UUID is returned

**When** calling getReminder(uuid: "ABC123")
**Then** the complete reminder is returned
**And** both UUID formats work (with/without prefix)

**When** calling updateReminder(uuid: "ABC123", title: "Updated Title")
**Then** only the title changes
**And** other fields remain unchanged

**When** calling completeReminder(uuid: "ABC123")
**Then** the reminder is marked completed
**And** completionDate is set

### AC5: Search Tool Functions

**When** calling search(query: "meeting", lists: ["Work"], completed: false, priority: ["high"], sortBy: "dueDate", limit: 20)
**Then** matching reminders are returned
**And** results are sorted by due date
**And** at most 20 results returned
**And** all filters apply correctly

### AC6: Resources Function

**When** accessing `reminders://lists`
**Then** all lists with metadata are returned

**When** accessing `reminders://list/Work`
**Then** all reminders in "Work" list are returned

**When** accessing `reminders://uuid/ABC123`
**Then** the specific reminder is returned

### AC7: Error Handling Works

**Given** Reminders access not granted
**When** any tool is called
**Then** an error with code -32001 is returned
**And** the message explains how to grant access

**When** requesting non-existent reminder UUID
**Then** an error with code -32002 is returned
**And** the message indicates "Reminder not found"

**When** calling a tool with invalid parameters
**Then** an error with code -32602 is returned
**And** the message explains what's invalid

### AC8: REST API Unaffected

**Given** reminders-api is running
**When** making REST API calls (GET /lists, POST /reminders, etc.)
**Then** all REST endpoints work as before
**And** Home Assistant integration is unaffected

### AC9: Build Works

**When** running `swift build`
**Then** build succeeds without warnings
**And** all targets compile successfully

**When** running `swift test`
**Then** all tests pass (when tests are written)

### AC10: Claude Desktop Integration

**Given** Claude Desktop configured with stdio transport
**When** asking Claude to list reminders
**Then** Claude can call the MCP server
**And** responses are properly formatted
**And** Claude can parse and display results

## Testing Requirements

### Unit Tests
- [ ] Test each @MCPTool method with valid inputs
- [ ] Test each @MCPTool method with invalid inputs
- [ ] Test UUID format handling
- [ ] Test error cases
- [ ] Mock Reminders service for isolation

### Integration Tests
- [ ] Stdio transport full cycle
- [ ] HTTP transport full cycle
- [ ] Multi-tool sequences (create → update → delete)
- [ ] Resource access patterns
- [ ] Permission handling

### Manual Tests
1. **Claude Desktop Integration**
   - Configure MCP server
   - Ask Claude to create reminder
   - Ask Claude to search reminders
   - Verify natural language responses

2. **HTTP Client Testing**
   - Connect via curl/Postman
   - Send tool requests
   - Verify SSE events
   - Test session persistence

3. **Home Assistant Integration**
   - Verify REST API endpoints work
   - Verify Todo integration unaffected
   - No breaking changes

4. **Error Scenarios**
   - Revoke Reminders permission, verify error
   - Request non-existent items, verify not-found
   - Send malformed JSON, verify parse error

## Migration Validation Checklist

### Pre-Migration
- [x] Create feature branch (`swiftmcp-migration`)
- [x] Merge `reminders-hassio-todo` branch
- [x] Verify current build works
- [x] Document current implementation

### During Migration
- [ ] Add SwiftMCP dependency
- [ ] Create new @MCPServer class
- [ ] Implement all tools with @MCPTool
- [ ] Implement resource handling
- [ ] Update main.swift entry points
- [ ] Delete old transport files
- [ ] Remove MCP from reminders-api

### Post-Migration
- [ ] Build succeeds
- [ ] Stdio transport tested
- [ ] HTTP transport tested
- [ ] All tools function correctly
- [ ] All resources accessible
- [ ] Error handling works
- [ ] Documentation updated
- [ ] Tests pass (if any)
- [ ] Claude Desktop integration verified

## Rollback Plan

If migration fails or has critical issues:

1. **Immediate Rollback**
   ```bash
   git checkout rest_api_list_uuids
   # or
   git reset --hard origin/rest_api_list_uuids
   ```

2. **Partial Rollback (keep hassio-todo changes)**
   ```bash
   git revert <migration-commits>
   ```

3. **Cherry-pick Strategy**
   - Identify working commits
   - Create new branch from rest_api_list_uuids
   - Cherry-pick successful changes only

## Success Metrics

### Quantitative
- Lines of code: Reduce by ~360 lines
- Build time: Remain under 15 seconds
- Test coverage: If tests exist, maintain or improve
- Performance: Match or beat current benchmarks

### Qualitative
- Code is more maintainable (less custom transport code)
- Error messages are clear for LLMs
- Documentation is complete and accurate
- Community support for SwiftMCP available

## Sign-Off Criteria

Migration is complete and successful when:

- [x] Branch created and hassio-todo merged
- [ ] All acceptance criteria pass
- [ ] No regressions in REST API
- [ ] Home Assistant integration unaffected
- [ ] Documentation updated
- [ ] Manual testing complete (Claude Desktop + HTTP client)
- [ ] Performance acceptable
- [ ] No critical bugs
- [ ] Code review approved (if applicable)
- [ ] Merged to main branch

## Future Enhancements (Out of Scope)

Once migration is complete, consider:
- Bearer token authentication for HTTP transport
- OAuth provider integration
- OpenAPI spec generation
- Discovery endpoints (/.well-known/)
- Resource change notifications (if SwiftMCP supports)
- Custom middleware for logging/metrics

## References

- Migration Context: `docs/mcp/swiftmcp-migration-context.md`
- Implementation Plan: `docs/mcp/swiftmcp-migration-plan.md`
- Original Spec: `docs/mcp/specification.md`
- SwiftMCP Docs: https://github.com/Cocoanetics/SwiftMCP
