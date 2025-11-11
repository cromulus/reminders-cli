import XCTest
import EventKit
@testable import RemindersLibrary

// NOTE: These tests require access to EventKit and will create temporary reminders
// They clean up after themselves but need Reminders permission to run

final class FilterExpressionTests: XCTestCase {

    var store: EKEventStore!
    var testCalendar: EKCalendar!
    var createdReminders: [EKReminder] = []

    override func setUp() async throws {
        store = EKEventStore()

        // Request access to reminders
        let granted = try await store.requestFullAccessToReminders()
        guard granted else {
            throw XCTestError(.failureWhileWaiting, userInfo: [
                "reason": "Reminders access denied - tests require permission"
            ])
        }

        // Create a test calendar for our reminders
        testCalendar = EKCalendar(for: .reminder, eventStore: store)
        testCalendar.title = "FilterTests_\(UUID().uuidString)"
        testCalendar.source = store.defaultCalendarForNewReminders()?.source

        try store.saveCalendar(testCalendar, commit: true)
    }

    override func tearDown() async throws {
        // Delete all test reminders
        for reminder in createdReminders {
            try? store.remove(reminder, commit: false)
        }
        try? store.commit()

        // Delete test calendar
        if let testCalendar = testCalendar {
            try? store.removeCalendar(testCalendar, commit: true)
        }

        createdReminders.removeAll()
        store = nil
        testCalendar = nil
    }

    // MARK: - Helper Methods

    private func createReminder(
        title: String,
        priority: Int = 0,
        isCompleted: Bool = false,
        notes: String? = nil,
        dueDate: Date? = nil
    ) -> EKReminder {
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = testCalendar
        reminder.title = title
        reminder.priority = priority
        reminder.isCompleted = isCompleted
        reminder.notes = notes

        if let dueDate = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        }

        createdReminders.append(reminder)
        return reminder
    }

    // MARK: - Quote Stripping Tests

    func testQuoteStrippingInEquality() throws {
        // Test that single quotes are stripped
        let parts = try FilterExpression.parseConditionPublic("priority = 'high'")
        XCTAssertEqual(parts.value, "high")

        // Test that double quotes are stripped
        let parts2 = try FilterExpression.parseConditionPublic("priority = \"high\"")
        XCTAssertEqual(parts2.value, "high")

        // Test without quotes
        let parts3 = try FilterExpression.parseConditionPublic("priority = high")
        XCTAssertEqual(parts3.value, "high")
    }

    func testParenthesisStrippingInINOperator() throws {
        // Test parentheses syntax
        let parts = try FilterExpression.parseConditionPublic("list IN ('Work', 'Home')")
        XCTAssertEqual(parts.value, "Work, Home")

        // Test bracket syntax
        let parts2 = try FilterExpression.parseConditionPublic("list IN [Work, Home]")
        XCTAssertEqual(parts2.value, "Work, Home")

        // Test without delimiters
        let parts3 = try FilterExpression.parseConditionPublic("list IN Work, Home")
        XCTAssertEqual(parts3.value, "Work, Home")
    }

    // MARK: - Operator Parsing Tests

    func testParseEqualsOperator() throws {
        let filter = try FilterExpression.parse("priority = 'high'")
        XCTAssertEqual(filter.conditions.count, 1)
        XCTAssertEqual(filter.conditions[0].field, "priority")
        XCTAssertEqual(filter.conditions[0].op, .equals)
        XCTAssertEqual(filter.conditions[0].value, "high")
    }

    func testParseNotEqualsOperator() throws {
        let filter = try FilterExpression.parse("priority != 'low'")
        XCTAssertEqual(filter.conditions.count, 1)
        XCTAssertEqual(filter.conditions[0].op, .notEquals)
    }

    func testParseContainsOperator() throws {
        let filter = try FilterExpression.parse("title CONTAINS 'meeting'")
        XCTAssertEqual(filter.conditions.count, 1)
        XCTAssertEqual(filter.conditions[0].op, .contains)
        XCTAssertEqual(filter.conditions[0].value, "meeting")
    }

    func testParseNotContainsOperator() throws {
        let filter = try FilterExpression.parse("notes NOT CONTAINS 'urgent'")
        XCTAssertEqual(filter.conditions.count, 1)
        XCTAssertEqual(filter.conditions[0].op, .notContains)
    }

    func testParseLikeOperator() throws {
        let filter = try FilterExpression.parse("title LIKE 'Buy *'")
        XCTAssertEqual(filter.conditions.count, 1)
        XCTAssertEqual(filter.conditions[0].op, .like)
    }

    func testParseMatchesOperator() throws {
        let filter = try FilterExpression.parse("title MATCHES '^Buy.*'")
        XCTAssertEqual(filter.conditions.count, 1)
        XCTAssertEqual(filter.conditions[0].op, .matches)
    }

    func testParseINOperator() throws {
        let filter = try FilterExpression.parse("list IN ('Work', 'Home')")
        XCTAssertEqual(filter.conditions.count, 1)
        XCTAssertEqual(filter.conditions[0].op, .in)
    }

    func testParseNotINOperator() throws {
        let filter = try FilterExpression.parse("priority NOT IN ('low', 'none')")
        XCTAssertEqual(filter.conditions.count, 1)
        XCTAssertEqual(filter.conditions[0].op, .notIn)
    }

    // MARK: - Logical Operator Tests

    func testParseANDOperator() throws {
        let filter = try FilterExpression.parse("priority = 'high' AND completed = false")
        XCTAssertEqual(filter.conditions.count, 2)
        XCTAssertEqual(filter.logicalOps.count, 1)
        XCTAssertEqual(filter.logicalOps[0], .and)
    }

    func testParseOROperator() throws {
        let filter = try FilterExpression.parse("list = 'Work' OR list = 'Personal'")
        XCTAssertEqual(filter.conditions.count, 2)
        XCTAssertEqual(filter.logicalOps.count, 1)
        XCTAssertEqual(filter.logicalOps[0], .or)
    }

    func testParseComplexLogicalExpression() throws {
        let filter = try FilterExpression.parse("priority = 'high' AND list = 'Work' OR completed = true")
        XCTAssertEqual(filter.conditions.count, 3)
        XCTAssertEqual(filter.logicalOps.count, 2)
        XCTAssertEqual(filter.logicalOps[0], .and)
        XCTAssertEqual(filter.logicalOps[1], .or)
    }

    // MARK: - Shortcut Expansion Tests

    func testOverdueShortcut() throws {
        let filter = try FilterExpression.parse("overdue")
        // Should expand to multiple conditions
        XCTAssertGreaterThan(filter.conditions.count, 0)
    }

    func testDueTodayShortcut() throws {
        let filter = try FilterExpression.parse("due_today")
        XCTAssertGreaterThan(filter.conditions.count, 0)
    }

    func testHighPriorityShortcut() throws {
        let filter = try FilterExpression.parse("high_priority")
        XCTAssertGreaterThan(filter.conditions.count, 0)
    }

    // MARK: - Evaluation Tests

    func testEvaluateSimpleEquality() {
        let reminder = createReminder(title: "Test", priority: 1) // 1 = high
        let filter = try! FilterExpression.parse("priority = 'high'")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testEvaluatePriorityMismatch() {
        let reminder = createReminder(title: "Test", priority: 5) // 5 = medium
        let filter = try! FilterExpression.parse("priority = 'high'")

        XCTAssertFalse(filter.evaluate(reminder, calendar: .current))
    }

    func testEvaluateContainsOperator() {
        let reminder = createReminder(title: "Buy milk at store")
        let filter = try! FilterExpression.parse("title CONTAINS 'milk'")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testEvaluateContainsOperatorCaseInsensitive() {
        let reminder = createReminder(title: "Buy MILK at store")
        let filter = try! FilterExpression.parse("title CONTAINS 'milk'")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testEvaluateNotContains() {
        let reminder = createReminder(title: "Buy eggs")
        let filter = try! FilterExpression.parse("title NOT CONTAINS 'milk'")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testEvaluateINOperator() {
        let reminder = createReminder(title: "Test", priority: 1) // high
        let filter = try! FilterExpression.parse("priority IN ('high', 'medium')")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testEvaluateINOperatorMismatch() {
        let reminder = createReminder(title: "Test", priority: 0) // none
        let filter = try! FilterExpression.parse("priority IN ('high', 'medium')")

        XCTAssertFalse(filter.evaluate(reminder, calendar: .current))
    }

    func testEvaluateNotINOperator() {
        let reminder = createReminder(title: "Test", priority: 1) // high
        let filter = try! FilterExpression.parse("priority NOT IN ('low', 'none')")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testEvaluateANDOperator() {
        let reminder = createReminder(title: "Test", priority: 1, isCompleted: false)
        let filter = try! FilterExpression.parse("priority = 'high' AND completed = false")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testEvaluateANDOperatorOneFails() {
        let reminder = createReminder(title: "Test", priority: 1, isCompleted: true)
        let filter = try! FilterExpression.parse("priority = 'high' AND completed = false")

        XCTAssertFalse(filter.evaluate(reminder, calendar: .current))
    }

    func testEvaluateOROperator() {
        let reminder = createReminder(title: "Test", priority: 5) // medium
        let filter = try! FilterExpression.parse("priority = 'high' OR priority = 'medium'")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testEvaluateOROperatorBothFail() {
        let reminder = createReminder(title: "Test", priority: 0) // none
        let filter = try! FilterExpression.parse("priority = 'high' OR priority = 'medium'")

        XCTAssertFalse(filter.evaluate(reminder, calendar: .current))
    }

    func testEvaluateCompletedStatus() {
        let reminder = createReminder(title: "Test", isCompleted: true)
        let filter = try! FilterExpression.parse("completed = true")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testEvaluateHasNotes() {
        let reminder = createReminder(title: "Test", notes: "Some notes")
        let filter = try! FilterExpression.parse("hasNotes = true")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testEvaluateNoNotes() {
        let reminder = createReminder(title: "Test", notes: nil)
        let filter = try! FilterExpression.parse("hasNotes = false")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testEvaluateHasDueDate() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let reminder = createReminder(title: "Test", dueDate: tomorrow)
        let filter = try! FilterExpression.parse("hasDueDate = true")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testEvaluateNoDueDate() {
        let reminder = createReminder(title: "Test", dueDate: nil)
        let filter = try! FilterExpression.parse("hasDueDate = false")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    // MARK: - Wildcard Tests

    func testWildcardStartsWith() {
        let reminder = createReminder(title: "Buy milk")
        let filter = try! FilterExpression.parse("title LIKE 'Buy *'")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testWildcardEndsWith() {
        let reminder = createReminder(title: "Buy milk")
        let filter = try! FilterExpression.parse("title LIKE '* milk'")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testWildcardContains() {
        let reminder = createReminder(title: "Buy milk at store")
        let filter = try! FilterExpression.parse("title LIKE '* milk *'")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testSingleCharacterWildcard() {
        let reminder = createReminder(title: "Call Mom")
        let filter = try! FilterExpression.parse("title LIKE 'Call ???'")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    // MARK: - Regex Tests

    func testRegexStartsWith() {
        let reminder = createReminder(title: "Buy milk")
        let filter = try! FilterExpression.parse("title MATCHES '^Buy'")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testRegexEndsWith() {
        let reminder = createReminder(title: "Buy milk")
        let filter = try! FilterExpression.parse("title MATCHES 'milk$'")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testRegexPattern() {
        let reminder = createReminder(title: "Call 555-1234")
        let filter = try! FilterExpression.parse("title MATCHES '\\\\d{3}-\\\\d{4}'")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testRegexNotMatches() {
        let reminder = createReminder(title: "Buy milk")
        let filter = try! FilterExpression.parse("title NOT MATCHES '^Sell'")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    // MARK: - Date Comparison Tests

    func testDueDateInFuture() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let reminder = createReminder(title: "Test", dueDate: tomorrow)
        let filter = try! FilterExpression.parse("dueDate > now")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testDueDateInPast() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let reminder = createReminder(title: "Test", dueDate: yesterday)
        let filter = try! FilterExpression.parse("dueDate < now")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testDueDateIsToday() {
        let today = Date()
        let reminder = createReminder(title: "Test", dueDate: today)
        let filter = try! FilterExpression.parse("dueDate >= today")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    // MARK: - Edge Cases

    func testEmptyFilterReturnsTrue() {
        let reminder = createReminder(title: "Test")
        let filter = FilterExpression(conditions: [], logicalOps: [])

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testCaseInsensitiveFieldNames() {
        let reminder = createReminder(title: "Test", priority: 1)
        let filter = try! FilterExpression.parse("PRIORITY = 'high'")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testCaseInsensitiveOperators() {
        let reminder = createReminder(title: "Test")
        let filter = try! FilterExpression.parse("title contains 'test'")

        XCTAssertTrue(filter.evaluate(reminder, calendar: .current))
    }

    func testMultipleSpacesBetweenTokens() {
        let filter = try! FilterExpression.parse("priority   =    'high'")
        XCTAssertEqual(filter.conditions.count, 1)
    }

    // MARK: - Error Cases

    func testInvalidOperatorThrows() {
        XCTAssertThrowsError(try FilterExpression.parse("priority @ high")) { error in
            XCTAssertTrue(error is RemindersMCPError)
        }
    }

    func testMalformedConditionThrows() {
        XCTAssertThrowsError(try FilterExpression.parse("priority")) { error in
            XCTAssertTrue(error is RemindersMCPError)
        }
    }
}

// Extension to expose private methods for testing
extension FilterExpression {
    static func parseConditionPublic(_ conditionStr: String) throws -> (field: String, op: FilterOperator, value: String, negate: Bool) {
        let condition = try parseCondition(conditionStr)
        return (condition.field, condition.op, condition.value, condition.negate)
    }
}
