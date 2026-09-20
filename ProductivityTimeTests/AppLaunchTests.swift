import XCTest
@testable import ProductivityTime

@MainActor
final class AppLaunchTests: XCTestCase {
    func testAppModelStartsWithoutAnActiveSession() {
        let model = AppModel()

        XCTAssertNil(model.activeSession)
    }
}
