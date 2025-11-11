# Reminders MCP – Consolidated Tool Reference

This reference outlines the new five-tool surface exposed by `RemindersMCPServer`. Each section includes a short description, JSON schema outline, and example prompt snippets an LLM can use.

## 1. reminders_manage

**Purpose:** Single-reminder operations (create/read/update/delete/complete/uncomplete/move/archive) with smart parsing for titles, priorities, and natural-language dates.

```json
{
  "action": "create|read|update|delete|complete|uncomplete|move|archive",
  "create": { "list": "Work", "title": "Send report tomorrow @Finance ^high", "notes": "Quarterly numbers" },
  "update": { "uuid": "...", "priority": "medium", "dueDate": "next Friday 9am" },
  "move": { "uuid": "...", "targetList": "Personal" },
  "archive": { "uuid": "...", "archiveList": "Archive", "createIfMissing": true }
}
```

**Prompt recipe:** “Create a high-priority reminder called ‘Send report tomorrow @Finance’ and archive any reminder titled ‘Weekly Sync’.”

## 2. reminders_bulk

**Purpose:** Batch operations over multiple reminder UUIDs (update completion state, change priority, move lists, archive, delete). Supports dry runs.

```json
{
  "action": "update|complete|uncomplete|move|archive|delete",
  "uuids": ["id-1", "id-2", "..."],
  "fields": {
    "priority": "high",
    "isCompleted": false,
    "targetList": "Planning",
    "archiveList": "Archive",
    "createArchiveIfMissing": true
  },
  "dryRun": true
}
```

**Prompt recipe:** “Mark all overdue tasks as complete, but show me a dry-run summary first.”

## 3. reminders_search

**Purpose:** Advanced querying with composable logic, grouping, and multi-key sorting. DSL supports AND/OR/XOR/NOT, string matching, date comparisons, tag filters, grouping on priority/list/tag/due date, and pagination.

```json
{
  "logic": {
    "all": [
      { "clause": { "field": "priority", "op": "equals", "value": "high" } },
      { "clause": { "field": "dueDate", "op": "before", "value": "next Monday" } },
      { "not": { "clause": { "field": "tag", "op": "includes", "value": "delegated" } } }
    ]
  },
  "groupBy": [
    { "field": "list" },
    { "field": "priority" }
  ],
  "sort": [
    { "field": "list", "direction": "asc" },
    { "field": "dueDate", "direction": "asc" },
    { "field": "createdAt", "direction": "asc" }
  ],
  "pagination": { "limit": 25, "offset": 0 },
  "includeCompleted": false
}
```

**Prompt recipe:** “Find high-priority reminders due this week, exclude anything tagged #delegated, group by list, and sort each group by priority desc then due date asc.”

## 4. reminders_lists

**Purpose:** List management and archive setup.

```json
{
  "action": "list|create|delete|ensureArchive",
  "list": { "includeReadOnly": false },
  "create": { "name": "Backlog", "source": "iCloud" },
  "delete": { "identifier": "Work" },
  "ensureArchive": { "name": "Archive", "createIfMissing": true }
}
```

**Prompt recipe:** “Make sure there is an Archive list (create if missing) and show me all writeable lists.”

## 5. reminders_analyze

**Purpose:** Aggregate statistics and insights (currently “overview” mode matching the previous dashboard output).

```json
{
  "mode": "overview"
}
```

**Prompt recipe:** “Give me an overview of total reminders, overdue items, and list-by-list counts.”

---

### Priority Buckets
- `none`: EventKit priority 0  
- `low`: priorities 6–9  
- `medium`: priority 5  
- `high`: priorities 1–4 (1 is highest)

### Search Fields & Operators (Quick Reference)
- Fields: `title`, `notes`, `list`, `listId`, `priority`, `tag`, `dueDate`, `createdAt`, `updatedAt`, `completed`, `hasDueDate`, `hasNotes`
- Operators: `equals`, `notEquals`, `contains`, `notContains`, `includes`, `excludes`, `before`, `after`, `exists`, `notExists`

### Grouping Options
- `priority`, `list`, `tag`, `dueDate` (`day`, `week`, `month` granularity)

### Sorting
- Multi-key sort descriptors accepted. Fields: `priority`, `list`, `tag`, `title`, `dueDate`, `createdAt`, `updatedAt`.

Use this reference with the specification and implementation plan to build prompts, tests, or client integrations around the consolidated Reminders MCP tools.

