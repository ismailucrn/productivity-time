import XCTest
@testable import ProductivityTime

final class SessionPresentationTests: XCTestCase {
    func testSettingsStatusPresentationCoversEveryConnectionAndNotificationState() {
        XCTAssertEqual(SettingsStatusPresentation.connectionLabel(for: .idle), "Not tested")
        XCTAssertEqual(SettingsStatusPresentation.connectionLabel(for: .testing), "Testing connection")
        XCTAssertEqual(SettingsStatusPresentation.connectionLabel(for: .succeeded), "Connected")
        XCTAssertEqual(SettingsStatusPresentation.connectionLabel(for: .failed), "Connection failed")

        XCTAssertEqual(SettingsStatusPresentation.notificationLabel(for: .notDetermined), "Not requested")
        XCTAssertEqual(SettingsStatusPresentation.notificationLabel(for: .authorized), "Allowed")
        XCTAssertEqual(SettingsStatusPresentation.notificationLabel(for: .denied), "Denied")
    }

    func testClockTextUsesStableTwoDigitFieldsAndClampsNegativeValues() {
        XCTAssertEqual(SessionPresentation.clockText(for: .zero), "00:00:00")
        XCTAssertEqual(SessionPresentation.clockText(for: .seconds(3_661)), "01:01:01")
        XCTAssertEqual(SessionPresentation.clockText(for: .seconds(-4)), "00:00:00")
    }

    func testCompactDurationAvoidsRawFloatingPointOutput() {
        XCTAssertEqual(SessionPresentation.compactDurationText(for: .seconds(45)), "45 sec")
        XCTAssertEqual(SessionPresentation.compactDurationText(for: .seconds(3_900)), "1 hr 5 min")
    }

    func testTimerPresentationRestoresCustomDurationAndContextualActions() {
        XCTAssertEqual(TimerPanelPresentation.configuredMinutes(from: .seconds(3_000), fallback: 25), 50)
        XCTAssertEqual(TimerPanelPresentation.configuredMinutes(from: nil, fallback: 25), 25)
        XCTAssertEqual(TimerPanelPresentation.secondaryActions(for: .stopwatch), [.completeSession, .discard])
        XCTAssertEqual(TimerPanelPresentation.secondaryActions(for: .timer), [.cancelTimer])
        XCTAssertEqual(TimerPanelPresentation.secondaryActions(for: nil), [])
    }

    func testDeliveryPresentationKeepsDestinationsIndependentlyReadable() {
        let failed = DestinationDelivery(
            sessionID: UUID(),
            destination: .notion,
            phase: .failed,
            errorCategory: "network",
            retryNotBefore: nil
        )

        XCTAssertEqual(
            DeliveryStatusPresentation.make(from: failed),
            DeliveryStatusPresentation(
                text: "Failed",
                systemImage: "exclamationmark.triangle.fill",
                role: .failure,
                canRetry: true
            )
        )
        XCTAssertEqual(DeliveryStatusPresentation.make(from: nil).text, "Pending")
        XCTAssertFalse(DeliveryStatusPresentation.make(from: nil).canRetry)
    }

    func testEveryDeliveryPhaseHasAReadableLabelAndRetryOnlyOnFailure() {
        let id = UUID()
        let values: [(DeliveryPhase, String, Bool)] = [
            (.pending, "Pending", false),
            (.delivering, "Delivering", false),
            (.delivered, "Delivered", false),
            (.failed, "Failed", true)
        ]

        for (phase, text, canRetry) in values {
            let record = DestinationDelivery(sessionID: id, destination: .appleNotes, phase: phase, errorCategory: nil, retryNotBefore: nil)
            let presentation = DeliveryStatusPresentation.make(from: record)
            XCTAssertEqual(presentation.text, text)
            XCTAssertEqual(presentation.canRetry, canRetry)
        }
    }
}
