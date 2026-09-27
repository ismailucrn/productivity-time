import Foundation
import XCTest

final class ProductivityTimeUITests: XCTestCase {
    private func discardRestorableSessionIfNeeded(in app: XCUIApplication) {
        let discard = app.buttons["restore.discard"]
        if discard.waitForExistence(timeout: 1) { discard.click() }
    }

    private func addActivity(named name: String, in app: XCUIApplication) {
        let field = app.textFields["activity.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText(name)
        app.buttons["activity.add"].click()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
    }

    func testWorkflowControlsExposeAccessibilityIdentifiers() {
        let app = XCUIApplication()
        app.launch()
        discardRestorableSessionIfNeeded(in: app)

        XCTAssertTrue(app.buttons["activity.add"].exists)
        XCTAssertTrue(app.buttons["timer.primary"].exists)
        XCTAssertTrue(app.buttons["history.show"].exists)
        addActivity(named: "Controls \(UUID().uuidString)", in: app)
        XCTAssertTrue(app.segmentedControls["timer.mode"].exists)
        app.buttons["timer.primary"].click()
        XCTAssertTrue(app.buttons["timer.complete"].exists)
        app.buttons["timer.discard"].click()
        app.buttons["history.show"].click()
    }

    func testMainToolbarKeepsHistoryAndLeavesSettingsToTheAppMenu() {
        let app = XCUIApplication()
        app.launch()
        discardRestorableSessionIfNeeded(in: app)

        XCTAssertTrue(app.buttons["history.show"].exists)
        XCTAssertFalse(app.buttons["settings.show"].exists)
    }

    func testSettingsExposeNonSecretConnectionAndNotificationStatusIdentifiers() {
        let app = XCUIApplication()
        app.launch()
        discardRestorableSessionIfNeeded(in: app)

        app.menuBars.menuBarItems["Productivity Time"].click()
        app.menuItems["Settings…"].click()

        let notesStatus = app.descendants(matching: .any)["settings.notes.status"]
        let notionStatus = app.descendants(matching: .any)["settings.notion.status"]
        let notificationStatus = app.descendants(matching: .any)["settings.notifications.status"]
        XCTAssertTrue(notesStatus.waitForExistence(timeout: 5))
        XCTAssertTrue(notionStatus.exists)
        XCTAssertTrue(notificationStatus.exists)
        XCTAssertEqual(notesStatus.label, "Not tested")
        XCTAssertEqual(notionStatus.label, "Not tested")
        XCTAssertTrue(["Not requested", "Allowed", "Denied"].contains(notificationStatus.label))

        let token = "ui-test-token-must-not-appear-in-status"
        let dataSourceResponseBody = #"{"object":"data_source","id":"ui-test"}"#
        app.descendants(matching: .any)["settings.notion.token"].click()
        app.typeText(token)
        app.descendants(matching: .any)["settings.notion.dataSource"].click()
        app.typeText(dataSourceResponseBody)

        let statusLabels = [notesStatus.label, notionStatus.label, notificationStatus.label].joined(separator: " ")
        XCTAssertFalse(statusLabels.contains(token))
        XCTAssertFalse(statusLabels.contains(dataSourceResponseBody))
    }

    func testActivityContextMenuOffersRenameAndDelete() {
        let app = XCUIApplication()
        app.launch()
        discardRestorableSessionIfNeeded(in: app)
        let name = "Manage \(UUID().uuidString)"
        addActivity(named: name, in: app)

        let activity = app.outlines["Sidebar"].staticTexts[name]
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        activity.rightClick()

        XCTAssertTrue(app.menuItems["Rename"].exists)
        XCTAssertTrue(app.menuItems["Delete"].exists)
    }

    func testTimerPanelExplainsEmptyStateAndContextualActions() {
        let app = XCUIApplication()
        app.launch()
        discardRestorableSessionIfNeeded(in: app)

        XCTAssertTrue(app.otherElements["timer.empty"].exists)
        XCTAssertFalse(app.buttons["timer.primary"].isEnabled)

        addActivity(named: "Writing \(UUID().uuidString)", in: app)
        XCTAssertTrue(app.segmentedControls["timer.mode"].exists)
        XCTAssertTrue(app.buttons["timer.primary"].isEnabled)
        app.buttons["timer.primary"].click()
        XCTAssertTrue(app.buttons["timer.complete"].exists)
        XCTAssertTrue(app.buttons["timer.discard"].exists)
    }

    func testActivityCreationAndKeyboardFocus() {
        let app = XCUIApplication()
        app.launch()
        discardRestorableSessionIfNeeded(in: app)
        addActivity(named: "Writing \(UUID().uuidString)", in: app)
    }

    func testStopwatchPauseAndResetAddsOneHistoryEntry() {
        let app = XCUIApplication()
        app.launch()
        discardRestorableSessionIfNeeded(in: app)
        let title = "Pause Reset \(UUID().uuidString)"
        addActivity(named: title, in: app)
        app.buttons["timer.primary"].click()
        XCTAssertTrue(app.buttons["timer.primary"].label == "Pause")
        app.buttons["timer.primary"].click()
        XCTAssertTrue(app.buttons["timer.primary"].label == "Resume")
        app.buttons["timer.complete"].click()
        app.buttons["history.show"].click()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
    }

    func testTimerCancelDoesNotAddHistoryEntry() {
        let app = XCUIApplication()
        app.launch()
        discardRestorableSessionIfNeeded(in: app)
        let title = "Timer Cancel \(UUID().uuidString)"
        addActivity(named: title, in: app)
        app.segmentedControls["timer.mode"].buttons["Timer"].click()
        XCTAssertTrue(app.steppers["timer.duration"].exists)
        app.buttons["timer.primary"].click()
        app.buttons["timer.cancel"].click()
        app.buttons["history.show"].click()
        XCTAssertFalse(app.staticTexts[title].waitForExistence(timeout: 1))
    }

    func testMixedHistoryShowsIndependentStatusAndOnlyFailedRetry() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-fixture", "mixed-history"]
        app.launch()
        app.buttons["history.show"].click()
        let id = "11111111-2222-3333-4444-555555555555"

        XCTAssertEqual(app.descendants(matching: .any)["history.status.appleNotes.\(id)"].label, "Apple Notes delivery status: Delivered")
        XCTAssertEqual(app.descendants(matching: .any)["history.status.notion.\(id)"].label, "Notion delivery status: Failed")
        XCTAssertFalse(app.buttons["history.retry.appleNotes.\(id)"].exists)
        XCTAssertTrue(app.buttons["history.retry.notion.\(id)"].exists)
    }

    func testPausedSessionOffersRestoreThenDiscardAfterRelaunch() {
        let app = XCUIApplication()
        app.launch()
        discardRestorableSessionIfNeeded(in: app)
        addActivity(named: "Restore \(UUID().uuidString)", in: app)
        app.buttons["timer.primary"].click()
        app.buttons["timer.primary"].click()
        app.terminate()
        app.launch()

        XCTAssertTrue(app.buttons["restore.resume"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["restore.discard"].exists)
        app.buttons["restore.discard"].click()
        XCTAssertFalse(app.buttons["restore.resume"].exists)
    }
}
