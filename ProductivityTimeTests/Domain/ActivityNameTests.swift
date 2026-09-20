import XCTest
@testable import ProductivityTime

final class ActivityNameTests: XCTestCase {
    func testTrimsLeadingAndTrailingWhitespace() throws {
        let name = try ActivityName("  Focused work\n")

        XCTAssertEqual(name.value, "Focused work")
    }

    func testRejectsAnEmptyNameAfterTrimming() {
        XCTAssertThrowsError(try ActivityName(" \n\t "))
    }

    func testRejectsAnEightyOneCharacterName() {
        XCTAssertThrowsError(try ActivityName(String(repeating: "a", count: 81)))
    }

    func testAcceptsAnEightyCharacterName() throws {
        let name = try ActivityName(String(repeating: "a", count: 80))

        XCTAssertEqual(name.value.count, 80)
    }

    func testAcceptsUnicodeName() throws {
        let name = try ActivityName("Öğrenme 日本語")

        XCTAssertEqual(name.value, "Öğrenme 日本語")
    }

    func testAcceptsEmojiName() throws {
        let name = try ActivityName("Deep work 🧠")

        XCTAssertEqual(name.value, "Deep work 🧠")
    }
}
