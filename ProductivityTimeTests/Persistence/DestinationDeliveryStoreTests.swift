import SwiftData
import XCTest
@testable import ProductivityTime

@MainActor
final class DestinationDeliveryStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var store: SwiftDataStore!

    override func setUpWithError() throws {
        container = try SwiftDataStore.makeInMemoryContainer()
        store = try SwiftDataStore(container: container)
    }

    // Would fail if saving a completed session omitted either destination job or
    // used a new identifier instead of the completed session's stable UUID.
    func testSavingCompletedSessionCreatesTwoPendingDestinationJobsWithTheSessionIdentifier() throws {
        let activity = try store.createActivity(named: ActivityName("Reading"), createdAt: Date(timeIntervalSince1970: 100))
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let session = CompletedSession(
            id: sessionID,
            activityID: activity.id,
            titleSnapshot: "Reading",
            mode: .stopwatch,
            duration: .seconds(25),
            completedAt: Date(timeIntervalSince1970: 200),
            deliveryState: .pending
        )

        try store.saveCompleted(session)

        XCTAssertEqual(
            try store.deliveryRecords(for: sessionID),
            [
                DestinationDelivery(sessionID: sessionID, destination: .appleNotes, phase: .pending, errorCategory: nil, retryNotBefore: nil),
                DestinationDelivery(sessionID: sessionID, destination: .notion, phase: .pending, errorCategory: nil, retryNotBefore: nil),
            ]
        )
    }

    // Would fail if a state transition were stored on the session aggregate,
    // allowing one destination's retry to overwrite a different destination.
    func testRetryingFailedNotionLeavesDeliveredAppleNotesUntouched() throws {
        let session = try saveSession()
        let retryDate = Date(timeIntervalSince1970: 900)

        XCTAssertNotNil(try store.claimDelivery(sessionID: session.id, destination: .appleNotes, at: Date(timeIntervalSince1970: 500)))
        try store.markDeliverySucceeded(sessionID: session.id, destination: .appleNotes)
        XCTAssertNotNil(try store.claimDelivery(sessionID: session.id, destination: .notion, at: Date(timeIntervalSince1970: 500)))
        try store.markDeliveryFailed(sessionID: session.id, destination: .notion, errorCategory: "network", retryNotBefore: retryDate)

        try store.retryDelivery(sessionID: session.id, destination: .notion)

        XCTAssertEqual(
            try store.deliveryRecords(for: session.id),
            [
                DestinationDelivery(sessionID: session.id, destination: .appleNotes, phase: .delivered, errorCategory: nil, retryNotBefore: nil),
                DestinationDelivery(sessionID: session.id, destination: .notion, phase: .pending, errorCategory: nil, retryNotBefore: nil),
            ]
        )
        XCTAssertNil(try store.claimDelivery(sessionID: session.id, destination: .appleNotes, at: retryDate))
    }

    // Would fail if a claim ignored an existing delivery or a backoff deadline,
    // permitting concurrent or premature external writes for one destination.
    func testClaimRejectsInFlightAndBackedOffDestinationWork() throws {
        let session = try saveSession()
        let start = Date(timeIntervalSince1970: 500)
        let retryDate = Date(timeIntervalSince1970: 900)

        XCTAssertNotNil(try store.claimDelivery(sessionID: session.id, destination: .appleNotes, at: start))
        XCTAssertNil(try store.claimDelivery(sessionID: session.id, destination: .appleNotes, at: start))
        try store.markDeliveryFailed(sessionID: session.id, destination: .appleNotes, errorCategory: "network", retryNotBefore: retryDate)

        XCTAssertNil(try store.claimDelivery(sessionID: session.id, destination: .appleNotes, at: Date(timeIntervalSince1970: 899)))
        XCTAssertNotNil(try store.claimDelivery(sessionID: session.id, destination: .appleNotes, at: retryDate))
    }

    // Would fail if delivery recovery requeued a completed destination alongside
    // an interrupted one, causing a duplicate external write after restart.
    func testColdLaunchRecoveryOnlyRequeuesInterruptedDestinationWork() throws {
        let session = try saveSession()
        let now = Date(timeIntervalSince1970: 500)
        XCTAssertNotNil(try store.claimDelivery(sessionID: session.id, destination: .appleNotes, at: now))
        try store.markDeliverySucceeded(sessionID: session.id, destination: .appleNotes)
        XCTAssertNotNil(try store.claimDelivery(sessionID: session.id, destination: .notion, at: now))

        try store.recoverInterruptedDeliveries()

        XCTAssertEqual(
            try store.deliveryRecords(for: session.id),
            [
                DestinationDelivery(sessionID: session.id, destination: .appleNotes, phase: .delivered, errorCategory: nil, retryNotBefore: nil),
                DestinationDelivery(sessionID: session.id, destination: .notion, phase: .pending, errorCategory: nil, retryNotBefore: nil),
            ]
        )
    }

    // Would fail if a legacy aggregate success were copied to Notion, falsely
    // suppressing required Notion delivery after the per-destination migration.
    func testLegacyAggregateDeliveryMigratesToAppleNotesAndLeavesNotionPending() throws {
        let context = ModelContext(container)
        let activityID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        let legacy = SessionRecord(session: CompletedSession(
            id: sessionID,
            activityID: activityID,
            titleSnapshot: "Legacy reading",
            mode: .stopwatch,
            duration: .seconds(25),
            completedAt: Date(timeIntervalSince1970: 200),
            deliveryState: .pending
        ))
        legacy.setDeliveryState(.delivered)
        context.insert(legacy)
        try context.save()

        XCTAssertEqual(
            try store.deliveryRecords(for: sessionID),
            [
                DestinationDelivery(sessionID: sessionID, destination: .appleNotes, phase: .delivered, errorCategory: nil, retryNotBefore: nil),
                DestinationDelivery(sessionID: sessionID, destination: .notion, phase: .pending, errorCategory: nil, retryNotBefore: nil),
            ]
        )
        XCTAssertEqual(try store.completedSessions().first?.deliveryState, .pending)
    }

    // Would fail if the persistent compound job identity allowed two records for
    // the same session/destination, making duplicate external delivery possible.
    func testPersistentJobKeyPreventsDuplicateDestinationRecords() throws {
        let session = try saveSession()
        let context = ModelContext(container)
        context.insert(DestinationDeliveryRecord(sessionID: session.id, destination: .appleNotes))
        try context.save()

        XCTAssertEqual(
            try store.deliveryRecords(for: session.id).map(\.destination),
            [.appleNotes, .notion]
        )
    }

    // Would fail if arbitrary failure text reached persistent state, where it
    // could later leak credentials or private remote-service details to the UI.
    func testFailurePersistsOnlyASanitizedErrorCategory() throws {
        let session = try saveSession()
        XCTAssertNotNil(try store.claimDelivery(sessionID: session.id, destination: .notion, at: Date(timeIntervalSince1970: 500)))

        try store.markDeliveryFailed(
            sessionID: session.id,
            destination: .notion,
            errorCategory: "untrusted diagnostic content",
            retryNotBefore: nil
        )

        XCTAssertEqual(
            try store.deliveryRecords(for: session.id).last,
            DestinationDelivery(sessionID: session.id, destination: .notion, phase: .failed, errorCategory: "unknown", retryNotBefore: nil)
        )
    }

    // Would fail if constructing a second store silently performed launch
    // recovery and requeued an in-flight operation from the live first store.
    func testConstructingASecondStoreDoesNotRecoverLiveDestinationWork() throws {
        let session = try saveSession()
        XCTAssertNotNil(try store.claimDelivery(sessionID: session.id, destination: .notion, at: Date(timeIntervalSince1970: 500)))
        let secondStore = try SwiftDataStore(container: container)

        XCTAssertEqual(
            try secondStore.deliveryRecords(for: session.id).last,
            DestinationDelivery(sessionID: session.id, destination: .notion, phase: .delivering, errorCategory: nil, retryNotBefore: nil)
        )
    }

    // Would fail if a terminal success could be changed back to failed or
    // pending, allowing a later retry to duplicate an already delivered record.
    func testDeliveredDestinationCannotTransitionBackToFailureOrRetry() throws {
        let session = try saveSession()
        XCTAssertNotNil(try store.claimDelivery(sessionID: session.id, destination: .appleNotes, at: Date(timeIntervalSince1970: 500)))
        try store.markDeliverySucceeded(sessionID: session.id, destination: .appleNotes)

        XCTAssertThrowsError(try store.markDeliveryFailed(sessionID: session.id, destination: .appleNotes, errorCategory: "network", retryNotBefore: nil)) { error in
            XCTAssertEqual(error as? SessionRepositoryError, .invalidDeliveryStateTransition)
        }
        XCTAssertThrowsError(try store.retryDelivery(sessionID: session.id, destination: .appleNotes)) { error in
            XCTAssertEqual(error as? SessionRepositoryError, .invalidDeliveryStateTransition)
        }
        XCTAssertEqual(try store.deliveryRecords(for: session.id).first?.phase, .delivered)
    }

    private func saveSession() throws -> CompletedSession {
        let activity = try store.createActivity(named: ActivityName("Writing"), createdAt: Date(timeIntervalSince1970: 100))
        let session = CompletedSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            activityID: activity.id,
            titleSnapshot: "Writing",
            mode: .timer,
            duration: .seconds(60),
            completedAt: Date(timeIntervalSince1970: 200),
            deliveryState: .pending
        )
        try store.saveCompleted(session)
        return session
    }
}
