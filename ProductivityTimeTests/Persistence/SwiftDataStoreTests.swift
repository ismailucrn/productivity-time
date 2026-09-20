import SwiftData
import XCTest
@testable import ProductivityTime

@MainActor
final class SwiftDataStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var store: SwiftDataStore!

    override func setUpWithError() throws {
        container = try SwiftDataStore.makeInMemoryContainer()
        store = try SwiftDataStore(container: container)
    }

    func testCreatingCaseInsensitiveDuplicateActivityIsRejected() throws {
        _ = try store.createActivity(named: ActivityName("Reading"), createdAt: Date(timeIntervalSince1970: 100))

        XCTAssertThrowsError(
            try store.createActivity(named: ActivityName("reading"), createdAt: Date(timeIntervalSince1970: 101))
        ) { error in
            XCTAssertEqual(error as? SessionRepositoryError, .activityNameConflict)
        }
    }

    func testStableActivityNormalizationKeepsTurkishDotlessISeparateFromLatinI() {
        XCTAssertEqual(ActivityName.stableCaseInsensitiveKey("I"), "i")
        XCTAssertEqual(ActivityName.stableCaseInsensitiveKey("ı"), "ı")
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

    func testCompletedSessionRetainsTitleAfterActivityIsDeleted() throws {
        let activity = try store.createActivity(named: ActivityName("Reading"), createdAt: Date(timeIntervalSince1970: 100))
        try store.saveCompleted(makeSession(activity: activity, title: "Reading"))
        try store.deleteActivity(activity.id)

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

    func testReplacementStoreRequeuesInterruptedDeliveriesAsPending() throws {
        let container = try SwiftDataStore.makeInMemoryContainer()
        let firstStore = try SwiftDataStore(container: container)
        let activity = try firstStore.createActivity(named: ActivityName("Reading"), createdAt: Date(timeIntervalSince1970: 100))
        let interrupted = makeSession(activity: activity)
        try firstStore.saveCompleted(interrupted)
        try firstStore.updateDeliveryState(sessionID: interrupted.id, to: .delivering)

        let restartedStore = try SwiftDataStore(container: container)
        try restartedStore.recoverInterruptedDeliveries()

        XCTAssertEqual(try restartedStore.pendingDeliverySessions().map(\.id), [interrupted.id])
        XCTAssertEqual(try restartedStore.completedSessions().first?.deliveryState, .pending)
    }

    func testConstructingSecondStoreDoesNotRequeueAnInFlightDelivery() throws {
        let container = try SwiftDataStore.makeInMemoryContainer()
        let firstStore = try SwiftDataStore(container: container)
        let activity = try firstStore.createActivity(named: ActivityName("Reading"), createdAt: Date(timeIntervalSince1970: 100))
        let inFlight = makeSession(activity: activity)
        try firstStore.saveCompleted(inFlight)
        try firstStore.updateDeliveryState(sessionID: inFlight.id, to: .delivering)

        let secondStore = try SwiftDataStore(container: container)

        XCTAssertEqual(try secondStore.completedSessions().first?.deliveryState, .delivering)
        XCTAssertTrue(try secondStore.pendingDeliverySessions().isEmpty)
    }

    func testSavingActiveSnapshotReplacesPriorSnapshotAndPreservesPausedDuration() throws {
        let activity = try store.createActivity(named: ActivityName("Reading"), createdAt: Date(timeIntervalSince1970: 100))
        let first = makeSnapshot(activity: activity, duration: .seconds(10))
        let paused = ActiveSessionSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            activityID: activity.id,
            titleSnapshot: "Reading snapshot",
            mode: .timer,
            configuredDuration: .seconds(60),
            duration: .seconds(25),
            state: .paused
        )
        try store.saveActive(first)
        try store.saveActive(paused)
        let replacementStore = try SwiftDataStore(container: container)

        let restored = try XCTUnwrap(replacementStore.loadActive())
        XCTAssertEqual(restored.id, paused.id)
        XCTAssertEqual(restored.activityID, paused.activityID)
        XCTAssertEqual(restored.titleSnapshot, "Reading snapshot")
        XCTAssertEqual(restored.mode, .timer)
        XCTAssertEqual(restored.configuredDuration, .seconds(60))
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
