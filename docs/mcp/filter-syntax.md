# MCP Search Filter Syntax

## Overview
The search tool now supports a powerful SQL-like filter syntax with logical operators, shortcuts, wildcards, regex, and ordering capabilities.

## Basic Operators

### Comparison Operators
- `=` - Equals (case-insensitive for strings)
- `!=` - Not equals
- `>` - Greater than (dates, numbers)
- `<` - Less than (dates, numbers)
- `>=` - Greater than or equal
- `<=` - Less than or equal

### String Operators
- `CONTAINS` - String contains substring (case-insensitive)
- `NOT CONTAINS` - String does not contain substring
- `LIKE` - Pattern matching with wildcards (* for any chars, ? for single char)
- `NOT LIKE` - Negated pattern matching
- `MATCHES` - Regex pattern matching
- `NOT MATCHES` - Negated regex matching

### Logical Operators
- `AND` - Both conditions must be true
- `OR` - Either condition must be true
- `()` - Grouping for complex expressions

## Fields

### Available Fields
- `title` - Reminder title (string)
- `notes` - Reminder notes (string)
- `list` - List name (string)
- `priority` - Priority level (high, medium, low, none)
- `completed` - Completion status (true, false)
- `dueDate` - Due date (ISO date or keywords)
- `hasNotes` - Has notes (true, false)
- `hasDueDate` - Has due date (true, false)

### Special Date Keywords
- `now` - Current date/time
- `today` - Start of today
- `tomorrow` - Start of tomorrow
- `yesterday` - Start of yesterday

## Query Shortcuts

Use these shortcuts instead of complex filter expressions:

- `overdue` → `(dueDate < now AND completed = false)`
- `due_today` → `(dueDate >= today AND dueDate < tomorrow)`
- `this_week` → `(dueDate >= today AND dueDate < today+7)`
- `high_priority` → `priority = 'high'`
- `no_due_date` → `hasDueDate = false`
- `has_notes` → `hasNotes = true`

## Wildcard Patterns

Use wildcards in LIKE expressions:
- `*` - Matches any sequence of characters
- `?` - Matches exactly one character

Examples:
```
title LIKE 'Buy *'          # Starts with "Buy "
title LIKE '* milk *'       # Contains "milk"
title LIKE 'Call ???'       # "Call" followed by 3 chars
```

## Regex Patterns

Use MATCHES for powerful regex patterns:
```
title MATCHES '^Buy.*groceries$'    # Starts with "Buy" ends with "groceries"
title MATCHES '\d{3}-\d{4}'         # Phone number pattern
notes MATCHES '(?i)urgent'          # Case-insensitive match
```

## ORDER BY Clause

Sort results by one or more fields:
```
ORDER BY priority ASC
ORDER BY dueDate DESC
ORDER BY priority DESC, dueDate ASC
```

Supported fields:
- `title`, `priority`, `dueDate`, `completionDate`, `creationDate`, `lastModified`

Sort orders:
- `ASC` - Ascending (default)
- `DESC` - Descending

## Example Queries

### Simple Queries
```
list = 'work'
priority = 'high'
completed = false
title CONTAINS 'meeting'
```

### Using Shortcuts
```
overdue
due_today AND priority = 'high'
this_week OR high_priority
```

### Complex Queries
```
(list = 'work' OR list = 'personal') AND priority = 'high'
title CONTAINS 'meeting' AND dueDate < tomorrow
completed = false AND (priority = 'high' OR dueDate < now)
```

### Wildcard Queries
```
title LIKE 'Buy *' AND list = 'groceries'
notes LIKE '*urgent*'
title LIKE '??? project *'
```

### Regex Queries
```
title MATCHES '^(Buy|Purchase)'
notes MATCHES '\b(TODO|FIXME)\b'
title MATCHES '\d{4}-\d{2}-\d{2}'
```

### Queries with Ordering
```
overdue ORDER BY priority DESC, dueDate ASC
list = 'work' AND completed = false ORDER BY dueDate ASC
high_priority ORDER BY dueDate DESC
```

## Validation

The filter parser validates impossible combinations:
```
list = 'work' AND list = 'home'              # ERROR: Impossible
priority = 'high' AND priority = 'low'       # ERROR: Impossible
completed = true AND completed = false       # ERROR: Impossible
```

Use OR instead:
```
list = 'work' OR list = 'home'               # OK
priority = 'high' OR priority = 'low'        # OK
```

## Tips

1. **Case Insensitivity**: All string comparisons are case-insensitive
2. **Parentheses**: Use parentheses to group complex conditions
3. **Shortcuts First**: Try shortcuts before writing complex filters
4. **Wildcards vs Regex**: Use wildcards for simple patterns, regex for complex ones
5. **Date Keywords**: Use `now`, `today`, `tomorrow` instead of specific dates
6. **Multiple Sorts**: Separate sort fields with commas

## Common Use Cases

### Today's Urgent Tasks
```
due_today AND priority = 'high' ORDER BY dueDate ASC
```

### All Overdue Items Sorted by Priority
```
overdue ORDER BY priority DESC, dueDate ASC
```

### Find Specific Project Items
```
title LIKE '*project X*' AND completed = false ORDER BY dueDate ASC
```

### Items Needing Attention
```
(overdue OR due_today) AND has_notes ORDER BY priority DESC
```

### Search by Phone Numbers
```
notes MATCHES '\d{3}-\d{3}-\d{4}' ORDER BY creationDate DESC
```
