import Foundation
import XCTest
@testable import ProductivityTime

final class NotesLineFormatterTests: XCTestCase {
    func testFormatterMakesStableReadableLineAndFullLowercaseMarkerForHostileValues() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3 * 60 * 60)!
        let formatter = NotesLineFormatter(
            locale: Locale(identifier: "en_US_POSIX"),
            calendar: calendar,
            timeZone: calendar.timeZone
        )
        let identifier = UUID(uuidString: "A0B1C2D3-E4F5-4678-9ABC-DEF012345678")!
        let session = CompletedSession(
            id: identifier,
            activityID: UUID(),
            titleSnapshot: "Read \\\"Swift\\\" <>&\\n\\u{1F4DA}",
            mode: .stopwatch,
            duration: .seconds(3_661),
            completedAt: Date(timeIntervalSince1970: 1_704_067_200),
            deliveryState: .pending
        )

        let line = formatter.format(session)

        XCTAssertEqual(line.marker, "PT:a0b1c2d3-e4f5-4678-9abc-def012345678")
        XCTAssertTrue(line.plainText.contains("Read \\\"Swift\\\" <>&"))
        XCTAssertTrue(line.plainText.contains("01:01:01"))
        XCTAssertTrue(line.plainText.contains("stopwatch"))
        XCTAssertTrue(line.plainText.contains("2024-01-01 03:00:00"))
        XCTAssertTrue(line.html.contains("&lt;&gt;&amp;"))
        XCTAssertFalse(line.html.contains("<>&"))
        XCTAssertTrue(line.html.contains("PT:a0b1c2d3-e4f5-4678-9abc-def012345678"))
    }
}
