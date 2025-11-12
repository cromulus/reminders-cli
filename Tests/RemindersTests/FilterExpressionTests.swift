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
        let condition = try FilterExpression.parseConditionPublic("priority = 'high'")
        XCTAssertEqual(condition.value, "high")

        let doubleQuote = try FilterExpression.parseConditionPublic("priority = \"high\"")
        XCTAssertEqual(doubleQuote.value, "high")

        let noQuote = try FilterExpression.parseConditionPublic("priority = high")
        XCTAssertEqual(noQuote.value, "high")
    }

    func testParenthesisStrippingInINOperator() throws {
        let condition = try FilterExpression.parseConditionPublic("list IN ('Work', 'Home')")
        XCTAssertEqual(condition.value, "Work, Home")

        let brackets = try FilterExpression.parseConditionPublic("list IN [Work, Home]")
        XCTAssertEqual(brackets.value, "Work, Home")

        let bare = try FilterExpression.parseConditionPublic("list IN Work, Home")
        XCTAssertEqual(bare.value, "Work, Home")
    }

    // MARK: - Operator Parsing Tests

    func testParseEqualsOperator() throws {
        let condition = try FilterExpression.parseConditionPublic("priority = 'high'")
        XCTAssertEqual(condition.field, "priority")
        XCTAssertEqual(condition.op, .equals)
        XCTAssertEqual(condition.value, "high")
    }

    func testParseNotEqualsOperator() throws {
        let condition = try FilterExpression.parseConditionPublic("priority != 'low'")
        XCTAssertEqual(condition.op, .notEquals)
    }

    func testParseContainsOperator() throws {
        let condition = try FilterExpression.parseConditionPublic("title CONTAINS 'meeting'")
        XCTAssertEqual(condition.op, .contains)
        XCTAssertEqual(condition.value, "meeting")
    }

    func testParseNotContainsOperator() throws {
        let condition = try FilterExpression.parseConditionPublic("notes NOT CONTAINS 'urgent'")
        XCTAssertEqual(condition.op, .notContains)
    }

    func testParseLikeOperator() throws {
        let condition = try FilterExpression.parseConditionPublic("title LIKE 'Buy *'")
        XCTAssertEqual(condition.op, .like)
    }

    func testParseMatchesOperator() throws {
        let condition = try FilterExpression.parseConditionPublic("title MATCHES '^Buy.*'")
        XCTAssertEqual(condition.op, .matches)
    }

    func testParseINOperator() throws {
        let condition = try FilterExpression.parseConditionPublic("list IN ('Work', 'Home')")
        XCTAssertEqual(condition.op, .in)
    }

    func testParseNotINOperator() throws {
        let condition = try FilterExpression.parseConditionPublic("priority NOT IN ('low', 'none')")
        XCTAssertEqual(condition.op, .notIn)
    }

    func testParseComplexLogicalExpression() throws {
        let workHigh = createReminder(title: "Work item", priority: 1, isCompleted: false)
        let completedOther = createReminder(title: "Done", priority: 5, isCompleted: true)
        let filter = try FilterExpression.parse("priority = 'high' AND list = '\(testCalendar.title)' OR completed = true")

        XCTAssertTrue(filter.evaluate(workHigh, calendar: Calendar.current))
        XCTAssertTrue(filter.evaluate(completedOther, calendar: Calendar.current))
    }

    // MARK: - Shortcut Expansion Tests

    func testOverdueShortcut() throws {
        let filter = try FilterExpression.parse("overdue")
        XCTAssertFalse(filter.isEmpty)
    }

    func testDueTodayShortcut() throws {
        let filter = try FilterExpression.parse("due_today")
        XCTAssertFalse(filter.isEmpty)
    }

    func testHighPriorityShortcut() throws {
        let filter = try FilterExpression.parse("high_priority")
        XCTAssertFalse(filter.isEmpty)
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
        let filter = FilterExpression.empty

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
        let condition = try! FilterExpression.parseConditionPublic("priority   =    'high'")
        XCTAssertEqual(condition.value, "high")
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
