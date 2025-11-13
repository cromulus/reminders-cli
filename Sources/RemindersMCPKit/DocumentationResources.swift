import Foundation

public struct DocumentationResource: Encodable {
    public let title: String
    public let summary: String
    public let details: String
    public let samplePrompts: [String]
    public let sampleRequests: [String]
}

enum MCPDocs {
    static let filterDetails = """
# Search Filter Quick Reference

- Logical operators: AND, OR, NOT (use the structured `logic` tree for grouping—parentheses in the SQL-like string are not supported yet)
- Operators: =, !=, <, >, <=, >=, CONTAINS, LIKE, MATCHES, IN, BETWEEN
- Fields: title, notes, list, priority, tag, dueDate, createdAt, updatedAt, completed, hasDueDate, hasNotes
- Natural dates: today, tomorrow, now, friday+2, start of week, end of month
- Shortcuts: overdue, due_today, due_tomorrow, this_week, next_week, high_priority, incomplete
- Ordering: ORDER BY priority DESC, dueDate ASC

Wildcards (`LIKE`):
- `*` any characters, `?` single character

Regex (`MATCHES`):
- Standard ICU regular expressions with `(?i)` for case-insensitive matches

Examples:
1. `priority IN ('high','medium') AND list = 'Work'`
2. `dueDate BETWEEN 'today' AND 'end of week' AND completed = false`
3. `title CONTAINS 'client' AND NOT notes LIKE '*draft*'`
4. `overdue ORDER BY priority DESC, dueDate ASC`
"""

    static let toolOverview = """
# Reminders MCP Tool Overview

Per the [Model Context Protocol server tools spec (rev 2025-03-26)](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2025-03-26/server/tools.mdx), every tool must be self-documenting. This overview mirrors the JSON schema that SwiftMCP advertises so LLM clients can rely solely on protocol metadata.

**Invocation pattern:** each tool accepts a single `request` object. Pass JSON—not plain strings—in that parameter so the server can deserialize into the typed payloads shown below.

## reminders_manage — single reminder CRUD + smart parsing
- **Use when:** creating, reading, updating, deleting, completing, uncompleting, moving, or archiving one reminder.
- **Natural language helpers:** titles can embed `@list`, `!priority`, `#tags`, date phrases, and recurrence shorthands (`~weekly`, `~every 2 weeks`, `~monthly on 15`).
- **Recurrence:** set a `recurrence` object (`frequency`, `interval`, `daysOfWeek`, `dayOfMonth`, `end`, `remove`) *or* rely on the `~` shorthand.
- **Location alarms:** add `location { title, latitude, longitude, radius?, proximity? }` to attach a geofence trigger.
- **Limitations:** EventKit will not let us set attachments or the `url` field, and only one structured location alarm is supported per reminder.

**Sample prompt:** “Create ‘Team sync tomorrow 9am @Work ^high ~weekly on Monday’ with an arrival alarm at HQ and archive reminder `UUID-123`.”

**Sample JSON**
```jsonc
{
  "request": {
    "action": "create",
    "create": {
      "title": "Team sync tomorrow 9am @Work ^high ~weekly",
      "list": "Work",
      "notes": "Share wins + risks",
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

## reminders_bulk — batch mutations with dry-run support
- **Use when:** the same mutation must be applied to many UUIDs (complete, move, update, delete, archive).
- **Dry-runs:** set `dryRun: true` to view the change log without saving.

**Sample prompt:** “Move every UUID from my last search into Archive (create if missing) and show a dry-run summary first.”

**Sample JSON**
```jsonc
{
  "request": {
    "action": "move",
    "uuids": ["UUID-1", "UUID-2"],
    "fields": { "targetList": "Archive", "createArchiveIfMissing": true },
    "dryRun": true
  }
}
```

**Limitations:** bulk updates can only touch `title`, `notes`, `dueDate`, `priority`, `isCompleted`, `targetList`, and archive options—attachments, subtasks, and alarms stay untouched for safety.

## reminders_search — advanced logic tree queries
- **Use when:** you need grouping, pagination, ordering, or SQL-like filter strings (`priority = 'high' AND dueDate < 'next week'`).
- **Helpers:** natural-language dates, shortcuts (`overdue`, `due_today`, `high_priority`), and nested `logic` trees.
- **Limitations:** parentheses in the SQL-like `filter` string are not supported yet; use the structured `logic` object for grouping.

**Sample prompt:** “Find high or medium Work reminders due this week, grouped by list then priority.”

**Sample JSON**
```jsonc
{
  "request": {
    "logic": {
      "all": [
        { "clause": { "field": "priority", "op": "in", "value": ["high","medium"] } },
        { "clause": { "field": "dueDate", "op": "lessOrEqual", "value": "end of week" } },
        { "clause": { "field": "list", "op": "equals", "value": "Work" } }
      ]
    },
    "groupBy": [{ "field": "list" }, { "field": "priority" }],
    "sort": [{ "field": "dueDate", "direction": "asc" }],
    "pagination": { "limit": 25, "offset": 0 }
  }
}
```

## reminders_lists — list discovery and archive helpers
- **Use when:** you must look up writable lists, create/delete lists, or ensure an Archive list exists before moving reminders.

```jsonc
{
  "request": {
    "action": "ensureArchive",
    "ensureArchive": { "name": "Archive", "createIfMissing": true, "source": "iCloud" }
  }
}
```

## reminders_analyze — overview statistics
- **Use when:** you want a dashboard snapshot (overview), list leaderboard, priority histogram, due-window buckets, or recurrence stats.
- **Modes:** `overview` (default), `lists`, `priority`, `dueWindows`, `recurrence`.
- **Tuning:** set `upcomingWindowDays` (1–30, default 7) to control how “due soon” is computed.
- **Limitations:** analytics operate on the reminders currently available on this device (no historical trend data) and do not include raw reminder payloads.

```jsonc
{
  "request": {
    "mode": "dueWindows",
    "upcomingWindowDays": 10
  }
}
```

All responses embed recurrence info, natural-language parsing echoes, and rich reminder metadata so agents can validate their own work.
"""
}
