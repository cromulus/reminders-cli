# Reminders MCP Usage Guide

This document consolidates everything you need to run the MCP transport, understand the five exposed tools, and craft valid JSON requests/responses. It mirrors the metadata that SwiftMCP emits so LLM agents and human operators get the same view of the API surface and aligns with the [Model Context Protocol server-tools spec (rev 2025-03-26)](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2025-03-26/server/tools.mdx).

> **Important:** Every tool takes a proper JSON object in the `request` parameter (not a stringified blob). That allows the MCP bridge to deserialize into the typed payloads described below.

## 1. Running the Transport

### Standalone binary

```bash
$ swift build
$ ./.build/debug/reminders-mcp
# or release
$ ./.build/apple/Products/Release/reminders-mcp --host 0.0.0.0 --port 9090 --token "abc123"
```

By default the server listens on `127.0.0.1:8081` and serves both the JSON-RPC POST endpoint (`/mcp`) and the Server-Sent Events stream (`/mcp` via GET). Flags mirror the REST server (`--host`, `--port`, `--token`, `--verbose`).

### Embedded in reminders-api

`reminders-api` launches the MCP transport automatically and proxies `/mcp`, `/messages`, etc. on the REST port.

```bash
$ reminders-api --no-mcp                   # disable MCP entirely
$ reminders-api --mcp-port 9091            # run transport on a different TCP port
$ reminders-api --mcp-host 0.0.0.0         # bind SSE server to all interfaces
```

Authentication follows the same token rules as the REST endpoints.

## 2. Tool Overview

| Tool | Purpose |
|------|---------|
| `reminders_manage` | Single reminder CRUD / complete / archive / move |
| `reminders_bulk` | Batch mutations for many UUIDs with optional dry-run |
| `reminders_search` | Logic tree search with grouping, sorting, pagination |
| `reminders_lists` | List discovery/creation/deletion/archive helpers |
| `reminders_analyze` | Dashboard statistics (overview, lists, priority, due windows, recurrence) |

Each tool takes a single `request` object. SwiftMCP advertises the full schema, and the examples below are the canonical reference.

## 3. reminders_manage

**Use when:** you need to create/read/update/delete/complete/move/archive a single reminder.

```jsonc
{
  "request": {
    "action": "create",
    "create": {
      "title": "Book flights tomorrow 9am @Travel ^high",
      "list": "Travel",
      "notes": "Remember to use miles",
      "dueDate": "next Friday 17:00",
      "priority": "high",
      "recurrence": {
        "frequency": "weekly",
        "daysOfWeek": ["monday"],
        "end": { "type": "count", "value": "8" }
      },
      "location": {
        "title": "HQ Office",
        "latitude": 37.3317,
        "longitude": -122.0301,
        "radius": 75,
        "proximity": "arrival"
      }
    }
  }
}
```

Supported payload keys match the `ManageRequest` schema:

| Action | Payload |
|--------|---------|
| `create` | `create { title, list?, notes?, dueDate?, priority?, recurrence?, location? }` |
| `read` | `read { uuid }` |
| `update` | `update { uuid, title?, notes?, dueDate?, priority?, isCompleted?, recurrence?, location? }` |
| `delete` / `complete` / `uncomplete` | `{ uuid }` |
| `move` | `move { uuid, targetList }` |
| `archive` | `archive { uuid, archiveList?, createIfMissing?, source? }` |

### Recurrence payloads

`recurrence` can be provided as a structured object or inferred from the title via the `~` shorthand:

| Field | Description |
|-------|-------------|
| `frequency` | `daily`, `weekly`, `monthly`, `yearly` |
| `interval` | Integer ≥ 1 (defaults to 1) |
| `daysOfWeek` | For weekly cadence (use lowercase names) |
| `dayOfMonth` | For monthly cadence (1–31) |
| `end` | `{ "type": "count" \| "date" \| "never", "value": "10" \| "2025-01-01" }` |
| `pattern` | Free-form string like `"every 2 weeks"` |
| `remove` | `true` clears existing recurrence |

Shorthand markers (`~weekly`, `~every 2 weeks`, `~monthly on 15`, `~daily for 10`) in the title are parsed automatically. Recurrence requires a due date or enough structured info to infer cadence (for weekly/monthly we fall back to the due date’s weekday/day).

Clear a rule by sending `{ "recurrence": { "remove": true } }` or by including `~none` / `~remove` in the title.

### Location alarms

Add a geofence trigger by providing a `location` block with `title`, `latitude`, `longitude`, optional `radius` (meters), and `proximity` (`arrival`, `departure`, `any`). Remove it with `{ "location": { "remove": true } }`. EventKit only supports one structured location alarm per reminder.

### Limitations

- The `url`/attachment fields are read-only at the OS level.
- Only a single structured location alarm is supported per reminder.
- Subtasks are discoverable via `isSubtask`/`parentId` but cannot yet be created in a single call.

**Response snippet**

```jsonc
{
  "reminder": {
    "uuid": "F4832762-50C7-47C0-B09F-BDDFF2F9D1B5",
    "title": "Book flights",
    "list": "Travel",
    "priority": "high",
    "dueDate": "2025-01-17T17:00:00-08:00",
    "tags": ["Travel"],
    "_priorityValue": 3,
    "alarms": [
      {
        "kind": "location",
        "location": {
          "title": "HQ Office",
          "latitude": 37.3317,
          "longitude": -122.0301,
          "radius": 75
        },
        "proximity": "arrival"
      }
    ],
    "recurrence": {
      "frequency": "weekly",
      "interval": 1,
      "daysOfWeek": ["monday"],
      "end": { "type": "count", "value": "8" },
      "summary": "Every week on Monday, for 8 occurrences"
    }
  },
  "success": true,
  "message": "Reminder created"
}
```

## 4. reminders_bulk

**Use when:** the same mutation should be applied to several reminders (complete all overdue items, move a batch to another list, archive en masse, etc.).

```jsonc
{
  "request": {
    "action": "move",
    "uuids": [
      "UUID-ONE",
      "UUID-TWO"
    ],
    "fields": {
      "targetList": "Archive",
      "createArchiveIfMissing": true
    },
    "dryRun": true
  }
}
```

`fields` is optional and only the relevant keys are respected by each action:

| `fields` key | Used by |
|--------------|---------|
| `title`, `notes`, `dueDate`, `priority`, `isCompleted` | `update` |
| `targetList` | `move` |
| `archiveList`, `createArchiveIfMissing` | `archive` |

The response contains `processedCount`, `failedCount`, `errors`, and a per-item result array with change logs.

**Limitations:** bulk operations intentionally ignore attachments, subtasks, structured location alarms, and the OS-managed `url` field.

## 5. reminders_search

**Use when:** you need to query reminders with complex logic, grouping, or sorting. The request accepts either the structured `logic` tree or the shorter SQL-like `filter` string documented in [`filter-syntax.md`](filter-syntax.md).

> Parentheses in the SQL-like `filter` string are not supported yet—use the `logic` object when you need nested AND/OR groupings.

```jsonc
{
  "request": {
    "logic": {
      "all": [
        { "clause": { "field": "priority", "op": "in", "value": ["high", "medium"] } },
        { "clause": { "field": "list", "op": "equals", "value": "Work" } },
        { "clause": { "field": "dueDate", "op": "lessOrEqual", "value": "end of week" } }
      ],
      "not": {
        "clause": { "field": "tag", "op": "includes", "value": "delegated" }
      }
    },
    "groupBy": [{ "field": "list" }, { "field": "priority" }],
    "sort": [
      { "field": "dueDate", "direction": "asc" },
      { "field": "priority", "direction": "desc" }
    ],
    "pagination": { "limit": 25, "offset": 0 },
    "includeCompleted": false,
    "lists": ["Work", "Personal"],
    "query": "client"
  }
}
```

**Filters and operators:**

- Fields: `title`, `notes`, `list`, `listId`, `priority`, `tag`, `dueDate`, `createdAt`, `updatedAt`, `completed`, `hasDueDate`, `hasNotes`
- Ops: `equals`, `notEquals`, `contains`, `notContains`, `like`, `notLike`, `matches`, `notMatches`, `in`, `notIn`, `before`, `after`, `greaterThan`, `lessThan`, `greaterOrEqual`, `lessOrEqual`, `exists`, `notExists`
- Dates accept ISO8601 strings or friendly terms like `today`, `tomorrow`, `friday+2`, `start of month`.

The response contains `reminders`, `totalCount`, `limit`, `offset`, and optional `groups` (each group entry includes `field`, `value`, `count`, `reminderUUIDs`, `children`).

## 6. reminders_lists

**Use when:** you need to inspect or manage reminder lists.

```jsonc
{
  "request": {
    "action": "ensureArchive",
    "ensureArchive": {
      "name": "Archive",
      "createIfMissing": true,
      "source": "iCloud"
    }
  }
}
```

Actions:

| Action | Payload |
|--------|---------|
| `list` | `list { includeReadOnly? }` |
| `create` | `create { name, source? }` |
| `delete` | `delete { identifier }` (identifier may be name or UUID) |
| `ensureArchive` | `ensureArchive { name?, createIfMissing?, source? }` |

## 7. reminders_analyze

**Use when:** you need aggregate statistics without enumerating reminders. Modes:

| Mode | What you get |
|------|--------------|
| `overview` (default) | Summary + list and priority breakdowns |
| `lists` | Per-list totals, completion, overdue, recurring counts |
| `priority` | Priority histogram with completion/overdue counts |
| `dueWindows` | Buckets: overdue, today, next _N_ days, later, unscheduled |
| `recurrence` | Recurring vs one-off distribution (grouped by frequency) |

Optional `upcomingWindowDays` (1–30, default 7) controls how “due soon” is calculated for the summary and due-window buckets.

```jsonc
{
  "request": {
    "mode": "dueWindows",
    "upcomingWindowDays": 10
  }
}
```

Sample response (`mode: dueWindows`):

```jsonc
{
  "mode": "dueWindows",
  "summary": {
    "total": 246,
    "completed": 120,
    "incomplete": 126,
    "overdue": 14,
    "dueToday": 6,
    "dueWithinWindow": 22,
    "upcomingWindowDays": 10
  },
  "dueWindows": [
    { "label": "Overdue", "count": 14 },
    { "label": "Today", "count": 6 },
    { "label": "Next 10 days", "count": 22 },
    { "label": "Later", "count": 41 },
    { "label": "Unscheduled", "count": 43 }
  ]
}
```

## 8. Filter Language Cheat Sheet

The parsed filter DSL is documented in detail in [`filter-syntax.md`](filter-syntax.md). Highlights:

- Logical operators: `AND`, `OR`, `NOT` (use the structured `logic` tree for grouping—parentheses in the SQL-like string are not supported yet).
- Operators: `=`, `!=`, `<`, `>`, `<=`, `>=`, `CONTAINS`, `LIKE`, `MATCHES`, `IN`, `BETWEEN`.
- Natural dates: `today`, `tomorrow`, `now`, `friday+2`, `start of week`, `end of month`.
- Shortcuts: `overdue`, `due_today`, `incomplete`, `high_priority`, etc.
- Ordering: `ORDER BY priority DESC, dueDate ASC`.

## 9. Troubleshooting

- **Type mismatch (“expected ManageRequest but received String”)** – Restart the MCP transport to pick up the updated schema or ensure your client reloaded the metadata. Every tool expects a JSON object; raw strings are still accepted for backwards compatibility but now parsed internally.
- **Capabilities not obvious** – Inspect the tool descriptions returned by the MCP metadata (`mcpToolMetadata`) or refer to this document’s examples.
- **Authentication failures** – Ensure the `Authorization: Bearer <token>` header is present when the transport is configured with a token or when the embedded API requires auth.

## 10. Docs as Resources

The MCP server also exposes Markdown documentation as resources so agents can fetch it without leaving the protocol:

| URI | Description |
|-----|-------------|
| `docs://reminders/overview` | Tool overview + sample payloads and prompts |
| `docs://reminders/filter-cheatsheet` | SQL-like filter grammar, operators, shortcuts, examples |

Both resources declare `mimeType: text/markdown` and mirror the reference material in this folder.

If you keep receiving errors, run the transport with `--verbose` to mirror every incoming request/response. That output is extremely useful when filing issues.
