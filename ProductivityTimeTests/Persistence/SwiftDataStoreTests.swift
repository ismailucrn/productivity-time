import SwiftData
import XCTest
@testable import ProductivityTime

@MainActor
final class SwiftDataStoreTests: XCTestCase {
    private var store: SwiftDataStore!

    override func setUpWithError() throws {
        store = try SwiftDataStore(container: SwiftDataStore.makeInMemoryContainer())
    }

    func testCreatingCaseInsensitiveDuplicateActivityIsRejected() throws {
        _ = try store.createActivity(named: ActivityName("Reading"), createdAt: Date(timeIntervalSince1970: 100))

        XCTAssertThrowsError(
            try store.createActivity(named: ActivityName("reading"), createdAt: Date(timeIntervalSince1970: 101))
        ) { error in
            XCTAssertEqual(error as? SessionRepositoryError, .activityNameConflict)
        }
    }

    func testRenamingToCaseInsensitiveDuplicateIsRejected() throws {
        let first = try store.createActivity(named: ActivityName("Reading"), createdAt: Date(timeIntervalSince1970: 100))
        _ = try store.createActivity(named: ActivityName("Writing"), createdAt: Date(timeIntervalSince1970: 101))

        XCTAssertThrowsError(try store.renameActivity(first.id, to: ActivityName("writing"))) { error in
            XCTAssertEqual(error as? SessionRepositoryError, .activityNameConflict)
        }
    }

    func testDeletingActivityWithActiveSnapshotIsRejected() throws {
        let activity = try store.createActivity(named: ActivityName("Reading"), createdAt: Date(timeIntervalSince1970: 100))
        try store.saveActive(makeSnapshot(activity: activity))

        XCTAssertThrowsError(try store.deleteActivity(activity.id)) { error in
            XCTAssertEqual(error as? SessionRepositoryError, .activityHasActiveSession)
        }
    }

    func testCompletedSessionRetainsTitleAfterActivityIsRenamed() throws {
        let activity = try store.createActivity(named: ActivityName("Reading"), createdAt: Date(timeIntervalSince1970: 100))
        let session = makeSession(activity: activity, title: "Reading")
        try store.saveCompleted(session)
        _ = try store.renameActivity(activity.id, to: ActivityName("Research"))

        XCTAssertEqual(try store.completedSessions().first?.titleSnapshot, "Reading")
    }

    func testSavingDuplicateStableSessionIdentifierIsRejected() throws {
        let activity = try store.createActivity(named: ActivityName("Reading"), createdAt: Date(timeIntervalSince1970: 100))
        let session = makeSession(activity: activity, id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        try store.saveCompleted(session)

        XCTAssertThrowsError(try store.saveCompleted(session)) { error in
            XCTAssertEqual(error as? SessionRepositoryError, .sessionIDConflict)
        }
    }

    func testSavedCompletedSessionDefaultsToPendingDelivery() throws {
        let activity = try store.createActivity(named: ActivityName("Reading"), createdAt: Date(timeIntervalSince1970: 100))
        try store.saveCompleted(makeSession(activity: activity, deliveryState: .delivered))

        XCTAssertEqual(try store.completedSessions().first?.deliveryState, .pending)
    }

    func testDeliveryStateOnlyAllowsOutboxTransitions() throws {
        let activity = try store.createActivity(named: ActivityName("Reading"), createdAt: Date(timeIntervalSince1970: 100))
        let session = makeSession(activity: activity)
        try store.saveCompleted(session)
        try store.updateDeliveryState(sessionID: session.id, to: .delivering)
        try store.updateDeliveryState(sessionID: session.id, to: .failed(errorCategory: "permissionDenied"))
        try store.updateDeliveryState(sessionID: session.id, to: .delivering)
        try store.updateDeliveryState(sessionID: session.id, to: .delivered)

        XCTAssertThrowsError(try store.updateDeliveryState(sessionID: session.id, to: .pending)) { error in
            XCTAssertEqual(error as? SessionRepositoryError, .invalidDeliveryStateTransition)
        }
    }

    func testRestartFetchesPendingAndFailedSessionsButNotDeliveredSessions() throws {
        let container = try SwiftDataStore.makeInMemoryContainer()
        let firstStore = try SwiftDataStore(container: container)
        let activity = try firstStore.createActivity(named: ActivityName("Reading"), createdAt: Date(timeIntervalSince1970: 100))
        let pending = makeSession(activity: activity, id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let failed = makeSession(activity: activity, id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let delivered = makeSession(activity: activity, id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)
        try firstStore.saveCompleted(pending)
        try firstStore.saveCompleted(failed)
        try firstStore.saveCompleted(delivered)
        try firstStore.updateDeliveryState(sessionID: failed.id, to: .delivering)
        try firstStore.updateDeliveryState(sessionID: failed.id, to: .failed(errorCategory: "notesUnavailable"))
        try firstStore.updateDeliveryState(sessionID: delivered.id, to: .delivering)
        try firstStore.updateDeliveryState(sessionID: delivered.id, to: .delivered)
        let restartedStore = try SwiftDataStore(container: container)

        XCTAssertEqual(Set(try restartedStore.pendingDeliverySessions().map(\.id)), [pending.id, failed.id])
    }

    func testSavingActiveSnapshotReplacesPriorSnapshotAndPreservesPausedDuration() throws {
        let activity = try store.createActivity(named: ActivityName("Reading"), createdAt: Date(timeIntervalSince1970: 100))
        let first = makeSnapshot(activity: activity, duration: .seconds(10))
        let paused = makeSnapshot(activity: activity, duration: .seconds(25))
        try store.saveActive(first)
        try store.saveActive(paused)

        let restored = try XCTUnwrap(store.loadActive())
        XCTAssertEqual(restored.id, paused.id)
        XCTAssertEqual(restored.duration, .seconds(25))
        XCTAssertEqual(restored.state, .paused)
    }

    func testLoadingPausedSnapshotDoesNotCountClosedProcessTime() throws {
        let activity = try store.createActivity(named: ActivityName("Reading"), createdAt: Date(timeIntervalSince1970: 100))
        try store.saveActive(makeSnapshot(activity: activity, duration: .seconds(25)))

        XCTAssertEqual(try store.loadActive()?.duration, .seconds(25))
    }

    func testDiscardingActiveSnapshotCreatesNoCompletedSession() throws {
        let activity = try store.createActivity(named: ActivityName("Reading"), createdAt: Date(timeIntervalSince1970: 100))
        try store.saveActive(makeSnapshot(activity: activity))
        try store.saveActive(nil)

        XCTAssertNil(try store.loadActive())
        XCTAssertTrue(try store.completedSessions().isEmpty)
    }

    private func makeSession(
        activity: Activity,
        id: UUID = UUID(),
        title: String? = nil,
        deliveryState: DeliveryState = .pending
    ) -> CompletedSession {
        CompletedSession(
            id: id,
            activityID: activity.id,
            titleSnapshot: title ?? activity.name.value,
            mode: .stopwatch,
            duration: .seconds(25),
            completedAt: Date(timeIntervalSince1970: 200),
            deliveryState: deliveryState
        )
    }

    private func makeSnapshot(activity: Activity, duration: Duration = .seconds(25)) -> ActiveSessionSnapshot {
        ActiveSessionSnapshot(
            id: UUID(),
            activityID: activity.id,
            titleSnapshot: activity.name.value,
            mode: .stopwatch,
            configuredDuration: nil,
            duration: duration,
            state: .paused
        )
    }
}
