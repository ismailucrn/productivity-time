import Foundation
import XCTest
@testable import ProductivityTime

@MainActor
final class DeliveryCompositionTests: XCTestCase {
    func testSettingsPersistTrimmedNonSecretConfigurationAndClearTokenInputThroughCredentialStore() throws {
        let preferences = MemoryPreferences(notesTargetName: "  Notes  ", notionDataSourceID: "  source  ")
        let credentials = MemoryCredentials()
        let model = AppModel(
            repository: CompositionRepository(),
            clock: TestClock(date: .now),
            refreshScheduler: CompositionRefreshScheduler(),
            deliveryCoordinator: CompositionCoordinator(),
            preferences: preferences,
            credentialStore: credentials
        )

        model.updateNotesTarget("  Focus Sessions  ")
        model.updateNotionDataSourceID("  source-2  ")
        try model.updateNotionToken("  test-token  ")

        XCTAssertEqual(preferences.notesTargetName, "Focus Sessions")
        XCTAssertEqual(preferences.notionDataSourceID, "source-2")
        XCTAssertTrue(model.isNotionTokenConfigured)
        XCTAssertFalse(String(describing: model.isNotionTokenConfigured).contains("test-token"))
        XCTAssertEqual(credentials.writeCount, 1)

        try model.updateNotionToken("")
        XCTAssertFalse(model.isNotionTokenConfigured)
        XCTAssertEqual(credentials.removeCount, 1)
    }

    func testSuccessfulNotesConnectionRetriesOnlyNotesDestination() async throws {
        let repository = CompositionRepository()
        let session = makeSession()
        repository.sessions = [session]
        repository.records = [
            DestinationDelivery(sessionID: session.id, destination: .appleNotes, phase: .failed, errorCategory: "notesUnavailable", retryNotBefore: nil),
            DestinationDelivery(sessionID: session.id, destination: .notion, phase: .failed, errorCategory: "network", retryNotBefore: nil)
        ]
        let coordinator = CompositionCoordinator()
        let notes = SuccessfulNotesSink()
        let model = AppModel(
            repository: repository,
            clock: TestClock(date: .now),
            refreshScheduler: CompositionRefreshScheduler(),
            deliveryCoordinator: coordinator,
            preferences: MemoryPreferences(),
            credentialStore: MemoryCredentials(),
            notesSink: notes
        )
        try model.loadPersistedState()

        model.testNotesConnection()
        await Task.yield()

        let destinations = await coordinator.destinations
        let connectionCalls = await notes.connectionCallCount
        XCTAssertEqual(destinations, [.appleNotes])
        XCTAssertEqual(connectionCalls, 1)
    }

    func testRetryingFailedNotionDoesNotRequestAppleNotes() async throws {
        let repository = CompositionRepository()
        let session = makeSession()
        repository.sessions = [session]
        repository.records = [
            DestinationDelivery(sessionID: session.id, destination: .appleNotes, phase: .delivered, errorCategory: nil, retryNotBefore: nil),
            DestinationDelivery(sessionID: session.id, destination: .notion, phase: .failed, errorCategory: "network", retryNotBefore: nil)
        ]
        let coordinator = CompositionCoordinator()
        let model = AppModel(repository: repository, clock: TestClock(date: .now), refreshScheduler: CompositionRefreshScheduler(), deliveryCoordinator: coordinator)
        try model.loadPersistedState()

        model.retryDelivery(sessionID: session.id, destination: .notion)
        await Task.yield()

        let retries = await coordinator.retries
        XCTAssertEqual(retries.count, 1)
        XCTAssertEqual(retries.first?.0, session.id)
        XCTAssertEqual(retries.first?.1, .notion)
    }

    private func makeSession() -> CompletedSession {
        CompletedSession(id: UUID(), activityID: UUID(), titleSnapshot: "Writing", mode: .timer, duration: .seconds(60), completedAt: .now, deliveryState: .failed(errorCategory: "network"))
    }
}

@MainActor private final class CompositionRepository: SessionRepository {
    var activitiesValue = [Activity]()
    var sessions = [CompletedSession]()
    var records = [DestinationDelivery]()
    func createActivity(named name: ActivityName, createdAt: Date) throws -> Activity { let activity = Activity(id: UUID(), name: name, createdAt: createdAt); activitiesValue.append(activity); return activity }
    func renameActivity(_ id: UUID, to name: ActivityName) throws -> Activity { throw SessionRepositoryError.activityNotFound }
    func deleteActivity(_ id: UUID) throws {}
    func activities() throws -> [Activity] { activitiesValue }
    func saveCompleted(_ session: CompletedSession) throws { sessions.append(session); records += DeliveryDestination.allCases.map { DestinationDelivery(sessionID: session.id, destination: $0, phase: .pending, errorCategory: nil, retryNotBefore: nil) } }
    func completedSessions() throws -> [CompletedSession] { sessions }
    func pendingDeliverySessions() throws -> [CompletedSession] { sessions }
    func deliveryRecords(for sessionID: UUID) throws -> [DestinationDelivery] { records.filter { $0.sessionID == sessionID } }
    func pendingDeliveryRecords(for destination: DeliveryDestination, at date: Date) throws -> [DestinationDelivery] { records.filter { $0.destination == destination && $0.phase == .pending } }
    func claimDelivery(sessionID: UUID, destination: DeliveryDestination, at date: Date) throws -> DestinationDelivery? { nil }
    func markDeliverySucceeded(sessionID: UUID, destination: DeliveryDestination) throws {}
    func markDeliveryFailed(sessionID: UUID, destination: DeliveryDestination, errorCategory: String, retryNotBefore: Date?) throws {}
    func retryDelivery(sessionID: UUID, destination: DeliveryDestination) throws {}
    func recoverInterruptedDeliveries() throws {}
    func updateDeliveryState(sessionID: UUID, to state: DeliveryState) throws {}
    func saveActive(_ snapshot: ActiveSessionSnapshot?) throws {}
    func loadActive() throws -> ActiveSessionSnapshot? { nil }
}

@MainActor private final class CompositionCoordinator: DeliveryCoordinating {
    private(set) var destinations = [DeliveryDestination]()
    private(set) var retries = [(UUID, DeliveryDestination)]()
    func deliverAllPending() async -> [DeliveryAttemptResult] { [] }
    func deliverPending(destination: DeliveryDestination) async -> [DeliveryAttemptResult] { destinations.append(destination); return [] }
    func retry(sessionID: UUID, destination: DeliveryDestination) async -> DeliveryAttemptResult { retries.append((sessionID, destination)); return DeliveryAttemptResult(sessionID: sessionID, destination: destination, outcome: .skipped) }
}

@MainActor private final class MemoryPreferences: AppPreferences {
    var notesTargetName: String
    var notionDataSourceID: String
    init(notesTargetName: String = UserDefaultsAppPreferences.defaultNotesTargetName, notionDataSourceID: String = "") { self.notesTargetName = notesTargetName; self.notionDataSourceID = notionDataSourceID }
}

private final class MemoryCredentials: NotionCredentialStore, @unchecked Sendable {
    private(set) var writeCount = 0
    private(set) var removeCount = 0
    private var token: Data?
    func readToken() throws -> Data? { token }
    func writeToken(_ token: Data) throws { self.token = token; writeCount += 1 }
    func removeToken() throws { token = nil; removeCount += 1 }
}

private actor SuccessfulNotesSink: NotesSessionSink {
    private(set) var connectionCallCount = 0
    func deliver(_ session: CompletedSession, to target: NotesTarget) async throws -> DeliveryResult { .created }
    func testConnection(to target: NotesTarget) async throws { connectionCallCount += 1 }
}

@MainActor private final class CompositionRefreshScheduler: RefreshScheduling {
    func scheduleRepeating(every interval: Duration, action: @escaping @MainActor () -> Void) -> any RefreshTask { CompositionRefreshTask() }
    func scheduleDeadline(after duration: Duration, action: @escaping @MainActor () -> Void) -> any RefreshTask { CompositionRefreshTask() }
}
@MainActor private final class CompositionRefreshTask: RefreshTask { func cancel() {} }
