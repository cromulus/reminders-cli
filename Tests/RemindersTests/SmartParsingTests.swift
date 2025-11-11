import Foundation
@testable import RemindersLibrary
import XCTest

final class SmartParsingTests: XCTestCase {

    // MARK: - Priority Parsing Tests

    func testPriorityWords() {
        XCTAssertEqual(Priority(fromString: "high"), .high)
        XCTAssertEqual(Priority(fromString: "urgent"), .high)
        XCTAssertEqual(Priority(fromString: "critical"), .high)

        XCTAssertEqual(Priority(fromString: "medium"), .medium)
        XCTAssertEqual(Priority(fromString: "important"), .medium)

        XCTAssertEqual(Priority(fromString: "low"), .low)
        XCTAssertEqual(Priority(fromString: "normal"), .low)

        XCTAssertEqual(Priority(fromString: "none"), Priority.none)
        XCTAssertEqual(Priority(fromString: ""), Priority.none)
    }

    func testPriorityNumbers() {
        XCTAssertEqual(Priority(fromString: "3"), .high)
        XCTAssertEqual(Priority(fromString: "2"), .medium)
        XCTAssertEqual(Priority(fromString: "1"), .low)
        XCTAssertEqual(Priority(fromString: "0"), Priority.none)
    }

    func testPriorityCaseInsensitive() {
        XCTAssertEqual(Priority(fromString: "HIGH"), .high)
        XCTAssertEqual(Priority(fromString: "High"), .high)
        XCTAssertEqual(Priority(fromString: "URGENT"), .high)
    }

    func testPriorityInvalidValues() {
        XCTAssertNil(Priority(fromString: "invalid"))
        XCTAssertNil(Priority(fromString: "xyz"))
        XCTAssertNil(Priority(fromString: "99"))
    }

    // MARK: - Title Parsing Tests

    func testSimpleTitle() {
        let metadata = TitleParser.parse("Buy milk")
        XCTAssertEqual(metadata.cleanedTitle, "Buy milk")
        XCTAssertNil(metadata.priority)
        XCTAssertNil(metadata.listName)
        XCTAssertEqual(metadata.tags, [])
        XCTAssertNil(metadata.dueDate)
    }

    func testTitleWithPriority() {
        // Test word priorities
        let metadata = TitleParser.parse("Buy milk !high")
        XCTAssertEqual(metadata.cleanedTitle, "Buy milk")
        XCTAssertEqual(metadata.priority, .high)

        let metadata2 = TitleParser.parse("Buy milk !medium")
        XCTAssertEqual(metadata2.cleanedTitle, "Buy milk")
        XCTAssertEqual(metadata2.priority, .medium)

        let metadata3 = TitleParser.parse("Buy milk !low")
        XCTAssertEqual(metadata3.cleanedTitle, "Buy milk")
        XCTAssertEqual(metadata3.priority, .low)

        // Test numeric priorities
        let metadata4 = TitleParser.parse("Buy milk !3")
        XCTAssertEqual(metadata4.cleanedTitle, "Buy milk")
        XCTAssertEqual(metadata4.priority, .high)

        let metadata5 = TitleParser.parse("Buy milk !2")
        XCTAssertEqual(metadata5.cleanedTitle, "Buy milk")
        XCTAssertEqual(metadata5.priority, .medium)

        let metadata6 = TitleParser.parse("Buy milk !1")
        XCTAssertEqual(metadata6.cleanedTitle, "Buy milk")
        XCTAssertEqual(metadata6.priority, .low)

        let metadata7 = TitleParser.parse("Buy milk !0")
        XCTAssertEqual(metadata7.cleanedTitle, "Buy milk")
        XCTAssertEqual(metadata7.priority, Priority.none)

        // Test alternative words
        let metadata8 = TitleParser.parse("Buy milk !urgent")
        XCTAssertEqual(metadata8.cleanedTitle, "Buy milk")
        XCTAssertEqual(metadata8.priority, .high)
    }

    func testTitleWithList() {
        let metadata = TitleParser.parse("Buy milk @Groceries")
        XCTAssertEqual(metadata.cleanedTitle, "Buy milk")
        XCTAssertEqual(metadata.listName, "Groceries")
    }

    func testTitleWithTags() {
        let metadata = TitleParser.parse("Buy milk #shopping #food")
        XCTAssertEqual(metadata.cleanedTitle, "Buy milk")
        XCTAssertEqual(metadata.tags.sorted(), ["food", "shopping"])
    }

    func testTitleWithEverything() {
        let metadata = TitleParser.parse("Buy milk tomorrow @Groceries !high #shopping #food")

        XCTAssertEqual(metadata.cleanedTitle, "Buy milk")
        XCTAssertEqual(metadata.priority, .high)
        XCTAssertEqual(metadata.listName, "Groceries")
        XCTAssertEqual(metadata.tags.sorted(), ["food", "shopping"])
        XCTAssertNotNil(metadata.dueDate) // Should have parsed "tomorrow"
    }

    func testTitleWithDateAtBeginning() {
        let metadata = TitleParser.parse("tomorrow Buy milk @Groceries")

        XCTAssertEqual(metadata.cleanedTitle, "Buy milk")
        XCTAssertEqual(metadata.listName, "Groceries")
        XCTAssertNotNil(metadata.dueDate)
    }

    func testTitleWithDateInMiddle() {
        let metadata = TitleParser.parse("Buy milk tomorrow @Groceries")

        XCTAssertEqual(metadata.cleanedTitle, "Buy milk")
        XCTAssertEqual(metadata.listName, "Groceries")
        XCTAssertNotNil(metadata.dueDate)
    }

    func testComplexRealWorldExamples() {
        // Example 1: Work task
        let work = TitleParser.parse("Review PR #123 next monday @Work !urgent #review")
        XCTAssertEqual(work.cleanedTitle, "Review PR #123")
        XCTAssertEqual(work.priority, .high)
        XCTAssertEqual(work.listName, "Work")
        XCTAssertTrue(work.tags.contains("review"))
        XCTAssertNotNil(work.dueDate)

        // Example 2: Shopping with time
        let shop = TitleParser.parse("Pick up groceries tomorrow 6pm @Errands !low #shopping")
        XCTAssertTrue(shop.cleanedTitle.contains("Pick up groceries"))
        XCTAssertEqual(shop.priority, .low)
        XCTAssertEqual(shop.listName, "Errands")
        XCTAssertTrue(shop.tags.contains("shopping"))

        // Example 3: Simple with numeric priority
        let simple = TitleParser.parse("Call mom !3 @Personal")
        XCTAssertEqual(simple.cleanedTitle, "Call mom")
        XCTAssertEqual(simple.priority, .high)
        XCTAssertEqual(simple.listName, "Personal")
    }

    func testMarkersCanAppearInAnyOrder() {
        let m1 = TitleParser.parse("Buy milk @Groceries !high #shopping")
        let m2 = TitleParser.parse("Buy milk !high @Groceries #shopping")
        let m3 = TitleParser.parse("Buy milk #shopping @Groceries !high")

        XCTAssertEqual(m1.cleanedTitle, "Buy milk")
        XCTAssertEqual(m2.cleanedTitle, "Buy milk")
        XCTAssertEqual(m3.cleanedTitle, "Buy milk")

        XCTAssertEqual(m1.priority, .high)
        XCTAssertEqual(m2.priority, .high)
        XCTAssertEqual(m3.priority, .high)

        XCTAssertEqual(m1.listName, "Groceries")
        XCTAssertEqual(m2.listName, "Groceries")
        XCTAssertEqual(m3.listName, "Groceries")
    }

    func testWhitespaceIsCleanedUp() {
        let metadata = TitleParser.parse("  Buy   milk   @Groceries   ")
        XCTAssertEqual(metadata.cleanedTitle, "Buy milk")
        XCTAssertEqual(metadata.listName, "Groceries")
    }
}
