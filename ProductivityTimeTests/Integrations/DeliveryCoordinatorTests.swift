import Foundation
import XCTest
@testable import ProductivityTime

@MainActor
final class DeliveryCoordinatorTests: XCTestCase {
    // Would fail if a repository failure while enumerating a destination batch
    // invented a session UUID or exposed an undifferentiated/raw error.
    func testPendingFetchFailureHasNoFabricatedSessionIdentifierAndIsSanitized() async {
        let repository = CoordinatorRepository(failure: .pendingFetch)
        let coordinator = makeCoordinator(repository: repository)

        let results = await coordinator.deliverPending(destination: .appleNotes)

        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results[0].sessionID)
        XCTAssertEqual(results[0].destination, .appleNotes)
        XCTAssertEqual(results[0].outcome, .failed("pendingFetch"))
    }

    // Would fail if one destination's transport failure stopped the next
    // destination or coupled the two durable delivery records.
    func testDeliverAllPendingPersistsNotesFailureAndNotionSuccessIndependently() async {
        let session = makeSession()
        let repository = repository(jobs: jobs(for: session))
        let notes = RecordingNotesSink(result: .failure(.notesUnavailable))
        let notion = RecordingNotionSink(result: .success(.created))
        let coordinator = makeCoordinator(repository: repository, notes: notes, notion: notion)

        let results = await coordinator.deliverAllPending()

        XCTAssertEqual(results, [
            DeliveryAttemptResult(sessionID: session.id, destination: .appleNotes, outcome: .failed("notesUnavailable")),
            DeliveryAttemptResult(sessionID: session.id, destination: .notion, outcome: .delivered),
        ])
        let notesCalls = await notes.callCount
        let notionCalls = await notion.callCount
        let notesPhase = repository.phase(for: session.id, destination: .appleNotes)
        let notionPhase = repository.phase(for: session.id, destination: .notion)
        XCTAssertEqual(notesCalls, 1)
        XCTAssertEqual(notionCalls, 1)
        XCTAssertEqual(notesPhase, .failed)
        XCTAssertEqual(notionPhase, .delivered)
    }

    // Would fail if a successful first destination made the coordinator skip a
    // later destination that independently failed.
    func testDeliverAllPendingPersistsNotesSuccessAndNotionFailureIndependently() async {
        let session = makeSession()
        let repository = repository(jobs: jobs(for: session))
        let notes = RecordingNotesSink(result: .success(.created))
        let notion = RecordingNotionSink(result: .failure(.network))
        let coordinator = makeCoordinator(repository: repository, notes: notes, notion: notion)

        let results = await coordinator.deliverAllPending()

        XCTAssertEqual(results, [
            DeliveryAttemptResult(sessionID: session.id, destination: .appleNotes, outcome: .delivered),
            DeliveryAttemptResult(sessionID: session.id, destination: .notion, outcome: .failed("network")),
        ])
        let notesCalls = await notes.callCount
        let notionCalls = await notion.callCount
        let notesPhase = repository.phase(for: session.id, destination: .appleNotes)
        let notionPhase = repository.phase(for: session.id, destination: .notion)
        XCTAssertEqual(notesCalls, 1)
        XCTAssertEqual(notionCalls, 1)
        XCTAssertEqual(notesPhase, .delivered)
        XCTAssertEqual(notionPhase, .failed)
    }

    // Would fail if awaiting an external sink released the main actor without a
    // per-job in-flight guard, allowing duplicate external writes.
    func testConcurrentDeliveryOfTheSameJobUsesOneExternalWriteAndOneTerminalMark() async {
        let session = makeSession()
        let repository = repository(jobs: [job(session, .appleNotes)])
        let notes = BlockingNotesSink()
        let coordinator = makeCoordinator(repository: repository, notes: notes)

        let first = Task { @MainActor in await coordinator.deliverPending(destination: .appleNotes) }
        await notes.waitUntilCalled()
        let second = await coordinator.deliverPending(destination: .appleNotes)
        await notes.release()
        let firstResult = await first.value
        let notesCalls = await notes.callCount
        let markSuccessCalls = repository.markSuccessCalls

        XCTAssertEqual(firstResult, [DeliveryAttemptResult(sessionID: session.id, destination: .appleNotes, outcome: .delivered)])
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(notesCalls, 1)
        XCTAssertEqual(markSuccessCalls, 1)
    }

    // Would fail if an idempotent sink response was treated as a failure and
    // retried despite the session already existing at the destination.
    func testAlreadyExistsIsPersistedAsTerminalSuccess() async {
        let session = makeSession()
        let repository = repository(jobs: [job(session, .appleNotes)])
        let notes = RecordingNotesSink(result: .success(.alreadyExists))
        let coordinator = makeCoordinator(repository: repository, notes: notes)

        let results = await coordinator.deliverPending(destination: .appleNotes)
        let phase = repository.phase(for: session.id, destination: .appleNotes)

        XCTAssertEqual(results, [DeliveryAttemptResult(sessionID: session.id, destination: .appleNotes, outcome: .delivered)])
        XCTAssertEqual(phase, .delivered)
    }

    // Would fail if a retry deadline was ignored while listing eligible work,
    // allowing an external request before its persisted backoff expires.
    func testDeliverPendingExcludesJobsUntilTheirRetryDeadline() async {
        let session = makeSession()
        let retryDate = Date(timeIntervalSince1970: 1_704_067_260)
        let repository = repository(jobs: [job(session, .appleNotes, phase: .failed, retryNotBefore: retryDate)])
        let notes = RecordingNotesSink()
        let coordinator = makeCoordinator(repository: repository, notes: notes)

        let results = await coordinator.deliverPending(destination: .appleNotes)
        let notesCalls = await notes.callCount
        let phase = repository.phase(for: session.id, destination: .appleNotes)

        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(notesCalls, 0)
        XCTAssertEqual(phase, .failed)
    }

    // Would fail if retrying Notion mutated Apple Notes state or retried an
    // already-delivered destination.
    func testExplicitRetryOnlyChangesTheRequestedDestination() async {
        let session = makeSession()
        let repository = repository(jobs: [
            job(session, .appleNotes, phase: .failed),
            job(session, .notion, phase: .failed),
        ])
        let notion = RecordingNotionSink()
        let coordinator = makeCoordinator(repository: repository, notion: notion)

        let result = await coordinator.retry(sessionID: session.id, destination: .notion)
        let retryCalls = repository.retryCalls
        let notesPhase = repository.phase(for: session.id, destination: .appleNotes)
        let notionPhase = repository.phase(for: session.id, destination: .notion)
        let notionCalls = await notion.callCount

        XCTAssertEqual(result, DeliveryAttemptResult(sessionID: session.id, destination: .notion, outcome: .delivered))
        XCTAssertEqual(retryCalls, [.notion])
        XCTAssertEqual(notesPhase, .failed)
        XCTAssertEqual(notionPhase, .delivered)
        XCTAssertEqual(notionCalls, 1)
    }

    // Would fail if an error before the claim boundary reached a destination
    // sink, or if a repository diagnostic leaked into the UI-facing outcome.
    func testClaimFailureIsSanitizedAndPerformsNoExternalWrite() async {
        let session = makeSession()
        let repository = repository(jobs: [job(session, .appleNotes)], failure: .claim)
        let notes = RecordingNotesSink()
        let coordinator = makeCoordinator(repository: repository, notes: notes)

        let results = await coordinator.deliverPending(destination: .appleNotes)
        let notesCalls = await notes.callCount
        let markFailureCalls = repository.markFailureCalls

        XCTAssertEqual(results, [DeliveryAttemptResult(sessionID: session.id, destination: .appleNotes, outcome: .failed("claim"))])
        XCTAssertEqual(notesCalls, 0)
        XCTAssertEqual(markFailureCalls, 0)
    }

    // Would fail if a session lookup error were reported as delivered after a
    // claim, or if the failure could not be categorized without raw details.
    func testSessionLoadFailureIsSanitizedAndMarksTheClaimFailed() async {
        let session = makeSession()
        let repository = repository(jobs: [job(session, .appleNotes)], failure: .sessionLoad)
        let notes = RecordingNotesSink()
        let coordinator = makeCoordinator(repository: repository, notes: notes)

        let results = await coordinator.deliverPending(destination: .appleNotes)
        let notesCalls = await notes.callCount
        let markFailureCalls = repository.markFailureCalls

        XCTAssertEqual(results, [DeliveryAttemptResult(sessionID: session.id, destination: .appleNotes, outcome: .failed("sessionLoad"))])
        XCTAssertEqual(notesCalls, 0)
        XCTAssertEqual(markFailureCalls, 1)
    }

    // Would fail if a completed external write was reported as delivered even
    // though its durable success transition failed.
    func testMarkSuccessFailureIsSanitizedAndNeverReportedAsDelivered() async {
        let session = makeSession()
        let repository = repository(jobs: [job(session, .appleNotes)], failure: .markSuccess)
        let notes = RecordingNotesSink()
        let coordinator = makeCoordinator(repository: repository, notes: notes)

        let results = await coordinator.deliverPending(destination: .appleNotes)
        let notesCalls = await notes.callCount
        let markFailureCalls = repository.markFailureCalls

        XCTAssertEqual(results, [DeliveryAttemptResult(sessionID: session.id, destination: .appleNotes, outcome: .failed("markSuccess"))])
        XCTAssertEqual(notesCalls, 1)
        XCTAssertEqual(markFailureCalls, 1)
    }

    // Would fail if failure-to-mark-failed was falsely surfaced as delivery, or
    // if a private error string escaped the coordinator result.
    func testMarkFailureErrorIsSanitizedAndNeverReportedAsDelivered() async {
        let session = makeSession()
        let repository = repository(jobs: [job(session, .appleNotes)], failure: .markFailure)
        let notes = RecordingNotesSink(result: .failure(.network))
        let coordinator = makeCoordinator(repository: repository, notes: notes)

        let results = await coordinator.deliverPending(destination: .appleNotes)
        let notesCalls = await notes.callCount
        let markFailureCalls = repository.markFailureCalls

        XCTAssertEqual(results, [DeliveryAttemptResult(sessionID: session.id, destination: .appleNotes, outcome: .failed("markFailure"))])
        XCTAssertEqual(notesCalls, 1)
        XCTAssertEqual(markFailureCalls, 1)
    }

    @MainActor
    private func makeCoordinator(
        repository: CoordinatorRepository,
        notes: any NotesSessionSink = RecordingNotesSink(),
        notion: any NotionSessionSink = RecordingNotionSink()
    ) -> DeliveryCoordinator {
        DeliveryCoordinator(
            repository: repository,
            notes: notes,
            notion: notion,
            notesTarget: { NotesTarget(noteName: "Productivity Time") },
            notionConfiguration: { NotionConfiguration(dataSourceID: "unused") },
            now: { Date(timeIntervalSince1970: 1_704_067_200) }
        )
    }

    private func repository(
        jobs: [DestinationDelivery],
        failure: CoordinatorRepository.Failure? = nil
    ) -> CoordinatorRepository {
        CoordinatorRepository(sessions: [makeSession()], jobs: jobs, failure: failure)
    }

    private func makeSession() -> CompletedSession {
        CompletedSession(
            id: UUID(uuidString: "A0B1C2D3-E4F5-4678-9ABC-DEF012345678")!,
            activityID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            titleSnapshot: "Writing",
            mode: .timer,
            duration: .seconds(60),
            completedAt: Date(timeIntervalSince1970: 1_704_067_200),
            deliveryState: .pending
        )
    }

    private func jobs(for session: CompletedSession) -> [DestinationDelivery] {
        [job(session, .appleNotes), job(session, .notion)]
    }

    private func job(
        _ session: CompletedSession,
        _ destination: DeliveryDestination,
        phase: DeliveryPhase = .pending,
        retryNotBefore: Date? = nil
    ) -> DestinationDelivery {
        DestinationDelivery(sessionID: session.id, destination: destination, phase: phase, errorCategory: nil, retryNotBefore: retryNotBefore)
    }
}

@MainActor
private final class CoordinatorRepository: SessionRepository {
    enum Failure: Error, Equatable { case pendingFetch, claim, sessionLoad, markSuccess, markFailure }

    private let sessions: [CompletedSession]
    private var jobs: [DestinationDelivery]
    private let failure: Failure?
    private(set) var markSuccessCalls = 0
    private(set) var markFailureCalls = 0
    private(set) var retryCalls = [DeliveryDestination]()

    init(sessions: [CompletedSession] = [], jobs: [DestinationDelivery] = [], failure: Failure? = nil) {
        self.sessions = sessions
        self.jobs = jobs
        self.failure = failure
    }

    func createActivity(named name: ActivityName, createdAt: Date) throws -> Activity { throw SessionRepositoryError.activityNotFound }
    func renameActivity(_ id: UUID, to name: ActivityName) throws -> Activity { throw SessionRepositoryError.activityNotFound }
    func deleteActivity(_ id: UUID) throws {}
    func activities() throws -> [Activity] { [] }
    func saveCompleted(_ session: CompletedSession) throws {}
    func completedSessions() throws -> [CompletedSession] {
        if failure == .sessionLoad { throw Failure.sessionLoad }
        return sessions
    }
    func pendingDeliverySessions() throws -> [CompletedSession] { [] }
    func deliveryRecords(for sessionID: UUID) throws -> [DestinationDelivery] { [] }
    func pendingDeliveryRecords(for destination: DeliveryDestination, at date: Date) throws -> [DestinationDelivery] {
        if failure == .pendingFetch { throw Failure.pendingFetch }
        return jobs.filter { job in
            guard job.destination == destination else { return false }
            switch job.phase {
            case .pending: return true
            case .failed: return job.retryNotBefore == nil || job.retryNotBefore! <= date
            case .delivering, .delivered: return false
            }
        }
    }
    func claimDelivery(sessionID: UUID, destination: DeliveryDestination, at date: Date) throws -> DestinationDelivery? {
        if failure == .claim { throw Failure.claim }
        guard let index = jobs.firstIndex(where: { $0.sessionID == sessionID && $0.destination == destination }) else { return nil }
        let current = jobs[index]
        guard current.phase == .pending || (current.phase == .failed && (current.retryNotBefore == nil || current.retryNotBefore! <= date)) else { return nil }
        let claimed = DestinationDelivery(sessionID: sessionID, destination: destination, phase: .delivering, errorCategory: nil, retryNotBefore: nil)
        jobs[index] = claimed
        return claimed
    }
    func markDeliverySucceeded(sessionID: UUID, destination: DeliveryDestination) throws {
        markSuccessCalls += 1
        if failure == .markSuccess { throw Failure.markSuccess }
        set(sessionID: sessionID, destination: destination, phase: .delivered, errorCategory: nil, retryNotBefore: nil)
    }
    func markDeliveryFailed(sessionID: UUID, destination: DeliveryDestination, errorCategory: String, retryNotBefore: Date?) throws {
        markFailureCalls += 1
        if failure == .markFailure { throw Failure.markFailure }
        set(sessionID: sessionID, destination: destination, phase: .failed, errorCategory: errorCategory, retryNotBefore: retryNotBefore)
    }
    func retryDelivery(sessionID: UUID, destination: DeliveryDestination) throws {
        retryCalls.append(destination)
        set(sessionID: sessionID, destination: destination, phase: .pending, errorCategory: nil, retryNotBefore: nil)
    }
    func recoverInterruptedDeliveries() throws {}
    func updateDeliveryState(sessionID: UUID, to state: DeliveryState) throws {}
    func saveActive(_ snapshot: ActiveSessionSnapshot?) throws {}
    func loadActive() throws -> ActiveSessionSnapshot? { nil }

    func phase(for sessionID: UUID, destination: DeliveryDestination) -> DeliveryPhase? {
        jobs.first(where: { $0.sessionID == sessionID && $0.destination == destination })?.phase
    }

    private func set(sessionID: UUID, destination: DeliveryDestination, phase: DeliveryPhase, errorCategory: String?, retryNotBefore: Date?) {
        guard let index = jobs.firstIndex(where: { $0.sessionID == sessionID && $0.destination == destination }) else { return }
        jobs[index] = DestinationDelivery(sessionID: sessionID, destination: destination, phase: phase, errorCategory: errorCategory, retryNotBefore: retryNotBefore)
    }
}

private actor RecordingNotesSink: NotesSessionSink {
    private var result: Result<DeliveryResult, DeliveryError>
    private(set) var callCount = 0
    init(result: Result<DeliveryResult, DeliveryError> = .success(.created)) { self.result = result }
    func deliver(_ session: CompletedSession, to target: NotesTarget) async throws -> DeliveryResult {
        callCount += 1
        return try result.get()
    }
    func testConnection(to target: NotesTarget) async throws {}
}

private actor RecordingNotionSink: NotionSessionSink {
    private let result: Result<DeliveryResult, DeliveryError>
    private(set) var callCount = 0
    init(result: Result<DeliveryResult, DeliveryError> = .success(.created)) { self.result = result }
    func deliver(_ session: CompletedSession, configuration: NotionConfiguration) async throws -> DeliveryResult {
        callCount += 1
        return try result.get()
    }
    func testConnection(configuration: NotionConfiguration) async throws {}
}

private actor BlockingNotesSink: NotesSessionSink {
    private var firstCallWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private(set) var callCount = 0

    func deliver(_ session: CompletedSession, to target: NotesTarget) async throws -> DeliveryResult {
        callCount += 1
        firstCallWaiter?.resume()
        firstCallWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
        return .created
    }

    func testConnection(to target: NotesTarget) async throws {}

    func waitUntilCalled() async {
        if callCount > 0 { return }
        await withCheckedContinuation { firstCallWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
