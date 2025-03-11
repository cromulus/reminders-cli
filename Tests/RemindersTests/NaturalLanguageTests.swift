import Foundation
@testable import RemindersLibrary
import XCTest

final class NaturalLanguageTests: XCTestCase {
    func testYesterday() throws {
        let components = try XCTUnwrap(DateComponents(argument: "yesterday"))
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        let expectedComponents = Calendar.current.dateComponents(
            calendarComponents(except: timeComponents), from: tomorrow)

        XCTAssertEqual(components, expectedComponents)
    }

    func testTodayString() throws {
        let components = try XCTUnwrap(DateComponents(argument: "today"))
        let expectedComponents = Calendar.current.dateComponents(
            calendarComponents(except: timeComponents), from: Date())

        XCTAssertEqual(components, expectedComponents)
    }

    func testTodayNoon() throws {
        let components = try XCTUnwrap(DateComponents(argument: "12:00"))
        
        // Create dates from components for comparison
        let componentsDate = try XCTUnwrap(Calendar.current.date(from: components))
        
        // Compare hour and minute only
        XCTAssertEqual(Calendar.current.component(.hour, from: componentsDate), 12)
        XCTAssertEqual(Calendar.current.component(.minute, from: componentsDate), 0)
        
        // Make sure it's today
        XCTAssertEqual(
            Calendar.current.dateComponents([.year, .month, .day], from: componentsDate),
            Calendar.current.dateComponents([.year, .month, .day], from: Date())
        )
    }

    func testTonight() throws {
        let components = try XCTUnwrap(DateComponents(argument: "tonight"))
        
        // Create date from components for comparison
        let componentsDate = try XCTUnwrap(Calendar.current.date(from: components))
        
        // Tonight should be 7pm today
        XCTAssertEqual(Calendar.current.component(.hour, from: componentsDate), 19)
        XCTAssertEqual(Calendar.current.component(.minute, from: componentsDate), 0)
        
        // Make sure it's today
        XCTAssertEqual(
            Calendar.current.dateComponents([.year, .month, .day], from: componentsDate),
            Calendar.current.dateComponents([.year, .month, .day], from: Date())
        )
    }

    func testTomorrow() throws {
        let components = try XCTUnwrap(DateComponents(argument: "tomorrow"))
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: Date()))
        let expectedComponents = Calendar.current.dateComponents(
            calendarComponents(except: timeComponents), from: tomorrow)

        XCTAssertEqual(components, expectedComponents)
    }

    func testTomorrowAtTime() throws {
        let components = try XCTUnwrap(DateComponents(argument: "tomorrow 9pm"))
        
        // Create date from components for comparison
        let componentsDate = try XCTUnwrap(Calendar.current.date(from: components))
        
        // Should be 9pm
        XCTAssertEqual(Calendar.current.component(.hour, from: componentsDate), 21)
        XCTAssertEqual(Calendar.current.component(.minute, from: componentsDate), 0)
        
        // Get tomorrow's date for comparison
        let today = Date()
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: today))
        
        // Make sure it's tomorrow
        XCTAssertEqual(
            Calendar.current.dateComponents([.year, .month, .day], from: componentsDate),
            Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
        )
    }

    func testRelativeDayCount() throws {
        let components = try XCTUnwrap(DateComponents(argument: "in 2 days"))
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 2, to: Date()))
        let expectedComponents = Calendar.current.dateComponents(
            calendarComponents(except: timeComponents), from: tomorrow)

        XCTAssertEqual(components, expectedComponents)
    }

    func testNextSaturday() throws {
        let components = try XCTUnwrap(DateComponents(argument: "next saturday"))
        let date = try XCTUnwrap(Calendar.current.date(from: components))

        XCTAssertTrue(Calendar.current.isDateInWeekend(date))
    }

    // FB8921206
    func testNextWeekend() throws {
        // TODO: This should be inverted but DataDetector doesn't support it right now
        XCTAssertNil(DateComponents(argument: "next weekend"))
        // let components = try XCTUnwrap(DateComponents(argument: "next weekend"))
        // let date = try XCTUnwrap(Calendar.current.date(from: components))

        // XCTAssertTrue(Calendar.current.isDateInWeekend(date))
    }

    func testSpecificDays() throws {
        XCTAssertNotNil(DateComponents(argument: "next monday"))
        XCTAssertNotNil(DateComponents(argument: "on monday at 9pm"))
    }

    func testIgnoreRandomString() {
        XCTAssertNil(DateComponents(argument: "blah tomorrow 9pm"))
    }
}
