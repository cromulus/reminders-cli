# Tags Implementation Plan

## Objective

Add support for managing tags in the reminders CLI application, following the same pattern established for subtasks and URL attachments. This would enable users to:

- List all available tags
- Filter reminders by tags
- Add tags to existing reminders
- Remove tags from reminders
- View tags in reminder output (list commands, JSON export, etc.)

## Current State Analysis

### Existing Private API Pattern

The codebase already successfully implements private API access for two features:

1. **Subtasks** - Accessing parent reminder relationships
2. **URL Attachments** - Accessing attached URLs and mail links

Both follow a consistent pattern in `EKReminder+PrivateAPI.swift`:
- Access the backing REM framework object via `reminderBackingObject`
- Use `NSSelectorFromString` to call private methods
- Process and expose data through computed properties

### Evidence of Tag Support Infrastructure

**Command Structure Already Exists:**
- `ShowTags` command (stubbed)
- `FilterByTag` command (stubbed)  
- `AddTag` command (stubbed)
- `RemoveTag` command (stubbed)

**Encoding Framework Ready:**
The `EKReminder+Encodable.swift` extension can easily accommodate tag fields for JSON output.

## Technical Implementation Approach

### Phase 1: Private API Discovery and Read Access

**1. Extend EKReminder+PrivateAPI.swift**

Add tag access functionality:

```swift
/// Returns all tags associated with this reminder
var tags: [String]? {
    let tagsSelector = NSSelectorFromString("tags") // or "tagNames", "tagLabels"
    
    guard let backingObj = reminderBackingObject,
          let unmanagedTags = backingObj.perform(tagsSelector),
          let tags = unmanagedTags.takeUnretainedValue() as? [AnyObject] else {
        return nil
    }
    
    // Process tag objects to extract string names
    return tags.compactMap { tagObj in
        // Extract tag name from tag object
        // May need additional selector calls like "name" or "title"
    }
}

/// Returns true if this reminder has any tags
var hasTags: Bool {
    return tags?.isEmpty == false
}
```

**2. Update EKReminder+Encodable.swift**

Add tags to JSON output:

```swift
private enum EncodingKeys: String, CodingKey {
    // ... existing keys ...
    case tags
    case hasTags
}

public func encode(to encoder: Encoder) throws {
    // ... existing encoding ...
    try container.encodeIfPresent(self.tags, forKey: .tags)
    try container.encode(self.hasTags, forKey: .hasTags)
}
```

**3. Update Display Logic**

Modify `Reminders.swift` to show tags in list output:

```swift
private func format(_ reminder: EKReminder, at index: Int, listName: String) -> String {
    // ... existing formatting ...
    
    if let tags = reminder.tags, !tags.isEmpty {
        additionalInfo.append("tags: \(tags.joined(separator: ", "))")
    }
}
```

### Phase 2: Implement Read Commands

**Replace TODO implementations in PrivateAPICommands.swift:**

```swift
struct ShowTags: ParsableCommand {
    func run() throws {
        let reminders = Reminders()
        let allReminders = reminders.getAllReminders()
        
        // Collect all unique tags
        let allTags = Set(allReminders.compactMap { $0.tags }.flatMap { $0 })
        
        for tag in allTags.sorted() {
            print(tag)
        }
    }
}

struct FilterByTag: ParsableCommand {
    func run() throws {
        let reminders = Reminders()
        let filtered = reminders.getAllReminders().filter { reminder in
            reminder.tags?.contains(tagName) == true
        }
        
        // Display filtered reminders
    }
}
```

### Phase 3: Write Operations (Advanced)

**Implement tag modification commands:**

This would require discovering write methods in the REM framework:
- Methods to add tags to reminders
- Methods to remove tags from reminders
- Proper event store saving procedures

## Potential Challenges

### 1. Selector Discovery

**Challenge:** Finding the correct method names for tag access.

**Approach:** 
- Runtime inspection of backing objects
- Reverse engineering similar to how attachments were discovered
- Testing variations: `tags`, `tagNames`, `tagLabels`, `hashtags`

### 2. Tag Object Structure

**Challenge:** Tags may be complex objects rather than simple strings.

**Considerations:**
- Tags might have UUIDs, colors, creation dates
- May need additional selector calls to extract display names
- Could require handling tag object types (similar to `REMURLAttachment`)

### 3. Write Operations Complexity

**Challenge:** Modifying tags requires understanding:
- Tag creation/deletion in the event store
- Reminder-tag association methods
- Proper saving and commit procedures

### 4. Data Consistency

**Challenge:** Ensuring tag modifications sync properly with:
- Other devices via iCloud
- The official Reminders app
- Undo/redo operations

## Risk Assessment

**Low Risk:**
- Read-only tag access (Phase 1-2)
- Following established private API patterns
- Leveraging existing infrastructure

**Medium Risk:**
- Write operations (Phase 3)
- Potential for data corruption if not properly implemented
- API stability across iOS/macOS versions

**High Risk:**
- Deep integration with tag management systems
- Undoing tag operations
- Complex tag object manipulation

## Success Criteria

### Minimum Viable Implementation
- [x] Tag names visible in reminder listings
- [x] JSON export includes tag information
- [x] Basic tag filtering functionality
- [x] List all available tags

### Full Implementation
- [ ] Add tags to existing reminders
- [ ] Remove tags from reminders
- [ ] Create new tags
- [ ] Tag-based reminder organization
- [ ] Tag management commands

## Next Steps

1. **Selector Discovery Research**
   - Inspect backing objects at runtime
   - Test common tag-related selector names
   - Document successful selectors

2. **Proof of Concept**
   - Implement basic tag reading functionality
   - Test with existing tagged reminders
   - Verify data structure and format

3. **Incremental Implementation**
   - Start with read-only operations
   - Add JSON encoding support
   - Implement display functionality

4. **Testing Strategy**
   - Test with reminders that have tags
   - Verify cross-platform compatibility
   - Ensure no data corruption

## Conclusion

Adding tags functionality appears highly feasible given:
- Established private API patterns
- Existing command infrastructure
- Proven track record with subtasks and URLs
- Strong evidence of underlying framework support

The implementation should follow the same cautious, incremental approach used for previous private API features, starting with read-only access before attempting write operations. 