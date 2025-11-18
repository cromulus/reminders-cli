# Reminders MCP Prompt Recipes

Quick-start prompts and response patterns for each tool. These examples assume the MCP client already knows the token/endpoints; adapt list names and UUIDs to your own data.

## reminders_manage
- “Create a reminder ‘Send status update tomorrow 9am @Work ^high’ and keep the parsed metadata in the response.”
- “Read reminder UUID `UUID-HERE` and show its list, tags, and due date.”
- “Update reminder `UUID-HERE` to mark it complete and move it to the Archive list.”
- “Archive reminder `UUID-HERE` into ‘Archive’ (create the list if missing) and tell me which list it came from.”

## reminders_bulk
- “Complete every reminder in this UUID list [...] but run a dry run first; if there are no errors, run it for real.”
- “Move these UUIDs to ‘Personal’ using a dry run; then apply.”
- “Delete these UUIDs permanently and show me how many failed.”

## reminders_search
- “Search for due-today reminders in Work or Personal lists, exclude completed, sort by dueDate asc and priority desc, and group counts by list.”
- “Find every reminder tagged finance or accounting due before end of month, include completed items, and page 25 per response.”
- “Show reminders updated in the last 48 hours, grouped by list, and include raw filters that were applied.”

## reminders_lists
- “List every writable reminder list; include read-only ones too so I know what is unavailable.”
- “Create a list named ‘Projects’ inside iCloud and confirm the identifier.”
- “Delete the reminder list named ‘Chores’.”
- “Ensure there is an Archive list in the same source as ‘Personal’; create it if missing.”

## reminders_analyze
- “Give me an overview (default mode) with summary counts plus per-list breakdown; use upcomingWindowDays=5.”
- “Show the priority histogram so I can see highs vs lows, and tell me overdue counts per priority.”
- “Produce due-windows buckets for overdue, today, next 7 days, later, and unscheduled.”
- “Provide recurrence stats so I know how many reminders repeat weekly vs monthly.”

## General Tips
- Always send a JSON object inside `request`; do not wrap the object in a string.
- Use natural-date literals like `today`, `end of week`, `next friday 5pm`, or `overdue`.
- For bulk actions, set `"dryRun": true` to preview results before mutating reminders.
- Combine search logic with follow-up manage/bulk calls by referencing the returned UUIDs.
