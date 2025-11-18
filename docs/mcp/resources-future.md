# MCP Resource Expansion – Future Sprint Notes

Goal: expose live reminders/lists as MCP resources so clients can fetch structured context (not just static docs).

## Proposed Capabilities
- resources capability advertises `subscribe: true`, `listChanged: true`.
- subscriptions allow clients to receive notifications when individual reminders update (title, due date, completion, etc.).
- listChanged notifications fire whenever any reminder mutation occurs so clients can refresh their caches.

## URI Scheme
- `reminder://{uuid}` – single reminder payload (JSON).
- `list://{identifier}` – metadata for a reminder list (name, source, counts).
- `reminder-list://{identifier}/reminders` (optional) – paginated reminder collection per list.
- `tasks://recent?limit=N` (optional) – curated view such as “recently updated reminders”.

Example resource entry:
```json
{
  "uri": "reminder://F4832762-50C7-47C0-B09F-BDDFF2F9D1B5",
  "name": "Team sync tomorrow 9am",
  "title": "Reminder – Team sync tomorrow 9am",
  "description": "Due tomorrow 09:00, list Work, priority high",
  "mimeType": "application/json",
  "annotations": {
    "audience": ["assistant"],
    "priority": 0.8,
    "lastModified": "2025-03-24T17:15:00Z"
  }
}
```

## Resource Templates
- `reminder://{uuid}` template exposes the schema for fetching arbitrary reminders.
- `list://{identifier}` template for list metadata.
- Potential template for filtered search results, e.g., `search://{query}?limit={n}` referencing saved searches or static filters.

## Resource Contents
- JSON body mirrors the `reminders_manage` read response, including tags, recurrence, alarms, parsed metadata.
- For lists, include writable flag, source, total counts, last modified.
- Include `_sourceVersion` or `lastModified` to help clients deduplicate updates.

## Notifications
- `notifications/resources/list_changed` when any reminder/list is created, updated, or deleted.
- `notifications/resources/updated` with specific URIs when clients subscribe to reminder resources and the reminder changes.

## Security
- Respect the same bearer token as the HTTP/MCP endpoints.
- Only expose reminders accessible to the current macOS user (no multi-user cross-contamination).

## Implementation Sketch
1. Add resource templates and list implementations in `RemindersMCPServer` with `@MCPResource`.
2. Maintain an in-memory index of reminder/list URIs to track lastModified timestamps.
3. Hook into mutation paths (manage/bulk) to send `Session.current?.sendResourceListChanged()` or `sendResourceUpdated(uri:)` notifications.
4. Consider pagination for lists (`resources/list` should not stream thousands of entries at once; implement cursor-based paging).
5. Document usage in `docs/mcp/USAGE.md` so clients know how to request `reminder://{uuid}` or subscribe.

## Open Questions
- Should reminders be fetched lazily (resource templates only) or eagerly listed? (Leaning: list only the most relevant/reminder-limited subset; rely on templates for arbitrary UUIDs.)
- Do we auto-create “saved searches” as resources (e.g., overdue, due today) or keep those as tool queries?
- Subscription granularity: only per reminder/list, or aggregated notifications?

## Next Steps
- Decide on pagination strategy and memory limits.
- Prototype the resource template path for `reminder://{uuid}` and ensure `resources/read` reuses the existing read logic.
- Add prompts/metadata to encourage clients to fetch relevant resources (e.g., “use reminder resources when summarizing context”).
