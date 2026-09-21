import Foundation
import XCTest
@testable import ProductivityTime

@MainActor
final class AppModelTests: XCTestCase {
    func testStartingSecondActivityWhileOneIsActiveIsRejected() throws {
        let repository = InMemorySessionRepository()
        let clock = TestClock(date: Date(timeIntervalSince1970: 1_000))
        let model = AppModel(repository: repository, clock: clock, refreshScheduler: TestRefreshScheduler())
        let first = try model.createActivity(named: "Writing")
        let second = try model.createActivity(named: "Reading")

        try model.startStopwatch(for: first.id)

        XCTAssertThrowsError(try model.startStopwatch(for: second.id)) { error in
            XCTAssertEqual(error as? AppModelError, .activeSessionAlreadyExists)
        }
        XCTAssertEqual(model.activeSession?.activityID, first.id)
    }

    func testPausingStopwatchDoesNotSaveCompletedSession() throws {
        let repository = InMemorySessionRepository()
        let clock = TestClock(date: Date(timeIntervalSince1970: 1_000))
        let model = AppModel(repository: repository, clock: clock, refreshScheduler: TestRefreshScheduler())
        let activity = try model.createActivity(named: "Writing")
        try model.startStopwatch(for: activity.id)
        clock.advance(by: .seconds(25))

        try model.pause()

        XCTAssertTrue(repository.savedCompletedSessions.isEmpty)
        XCTAssertEqual(model.activeSession?.state, .paused)
    }

    func testResettingStopwatchSavesCompletedSession() throws {
        let repository = InMemorySessionRepository()
        let clock = TestClock(date: Date(timeIntervalSince1970: 1_000))
        let model = AppModel(repository: repository, clock: clock, refreshScheduler: TestRefreshScheduler())
        let activity = try model.createActivity(named: "Writing")
        try model.startStopwatch(for: activity.id)
        clock.advance(by: .seconds(25))

        try model.reset()

        XCTAssertEqual(repository.savedCompletedSessions.map(\.duration), [.seconds(25)])
        XCTAssertEqual(repository.savedCompletedSessions.map(\.mode), [.stopwatch])
        XCTAssertNil(model.activeSession)
    }

    func testResettingTimerBeforeZeroDoesNotSaveCompletedSession() throws {
        let repository = InMemorySessionRepository()
        let clock = TestClock(date: Date(timeIntervalSince1970: 1_000))
        let model = AppModel(repository: repository, clock: clock, refreshScheduler: TestRefreshScheduler())
        let activity = try model.createActivity(named: "Writing")
        try model.startTimer(for: activity.id, duration: .seconds(60))
        clock.advance(by: .seconds(25))

        try model.reset()

        XCTAssertTrue(repository.savedCompletedSessions.isEmpty)
        XCTAssertNil(model.activeSession)
    }

    func testVisibleCounterSchedulesOneSecondRefresh() throws {
        let repository = InMemorySessionRepository()
        let scheduler = TestRefreshScheduler()
        let model = AppModel(repository: repository, clock: TestClock(date: Date(timeIntervalSince1970: 1_000)), refreshScheduler: scheduler)
        let activity = try model.createActivity(named: "Writing")

        try model.startStopwatch(for: activity.id)

        XCTAssertEqual(scheduler.activeRepeatingIntervals, [.seconds(1)])
        XCTAssertTrue(scheduler.activeDeadlineDurations.isEmpty)
    }

    func testHiddenStopwatchDoesNotScheduleARefresh() throws {
        let repository = InMemorySessionRepository()
        let scheduler = TestRefreshScheduler()
        let model = AppModel(repository: repository, clock: TestClock(date: Date(timeIntervalSince1970: 1_000)), refreshScheduler: scheduler)
        let activity = try model.createActivity(named: "Writing")
        model.setCounterVisible(false)

        try model.startStopwatch(for: activity.id)

        XCTAssertTrue(scheduler.activeRepeatingIntervals.isEmpty)
        XCTAssertTrue(scheduler.activeDeadlineDurations.isEmpty)
    }

    func testHiddenTimerKeepsOnlyItsDeadlineTask() throws {
        let repository = InMemorySessionRepository()
        let scheduler = TestRefreshScheduler()
        let model = AppModel(repository: repository, clock: TestClock(date: Date(timeIntervalSince1970: 1_000)), refreshScheduler: scheduler)
        let activity = try model.createActivity(named: "Writing")
        model.setCounterVisible(false)

        try model.startTimer(for: activity.id, duration: .seconds(60))

        XCTAssertTrue(scheduler.activeRepeatingIntervals.isEmpty)
        XCTAssertEqual(scheduler.activeDeadlineDurations, [.seconds(60)])
    }

    func testCounterRefreshDoesNotWritePersistence() throws {
        let repository = InMemorySessionRepository()
        let scheduler = TestRefreshScheduler()
        let model = AppModel(repository: repository, clock: TestClock(date: Date(timeIntervalSince1970: 1_000)), refreshScheduler: scheduler)
        let activity = try model.createActivity(named: "Writing")
        try model.startStopwatch(for: activity.id)

        scheduler.fireActiveRepeatingTasks()

        XCTAssertTrue(repository.savedCompletedSessions.isEmpty)
        XCTAssertNil(repository.savedActiveSnapshot)
    }

    func testLifecycleRecoversInterruptedDeliveriesOnlyOnceAtLaunch() throws {
        let repository = InMemorySessionRepository()
        let model = AppModel(repository: repository, clock: TestClock(date: Date(timeIntervalSince1970: 1_000)), refreshScheduler: TestRefreshScheduler())
        let lifecycle = AppLifecycleController()

        try lifecycle.start(model: model)
        try lifecycle.start(model: model)

        XCTAssertEqual(repository.recoveryCallCount, 1)
    }

    func testConstructingAppModelDoesNotRecoverInterruptedDeliveries() {
        let repository = InMemorySessionRepository()
        _ = AppModel(repository: repository, clock: TestClock(date: Date(timeIntervalSince1970: 1_000)), refreshScheduler: TestRefreshScheduler())

        XCTAssertEqual(repository.recoveryCallCount, 0)
    }

    func testLifecycleTerminationSnapshotsPausedMonotonicDuration() throws {
        let repository = InMemorySessionRepository()
        let clock = TestClock(date: Date(timeIntervalSince1970: 1_000))
        let model = AppModel(repository: repository, clock: clock, refreshScheduler: TestRefreshScheduler())
        let activity = try model.createActivity(named: "Writing")
        try model.startStopwatch(for: activity.id)
        clock.advance(by: .seconds(25))

        try AppLifecycleController().snapshotForTermination(model: model)

        XCTAssertEqual(repository.savedActiveSnapshot?.duration, .seconds(25))
        XCTAssertEqual(repository.savedActiveSnapshot?.state, .paused)
        XCTAssertTrue(repository.savedCompletedSessions.isEmpty)
    }

    func testRestoredSessionResumesFromStoredPausedDuration() throws {
        let repository = InMemorySessionRepository()
        let activityID = UUID()
        let snapshot = ActiveSessionSnapshot(id: UUID(), activityID: activityID, titleSnapshot: "Writing", mode: .stopwatch, configuredDuration: nil, duration: .seconds(25), state: .paused)
        try repository.saveActive(snapshot)
        let model = AppModel(repository: repository, clock: TestClock(date: Date(timeIntervalSince1970: 1_000)), refreshScheduler: TestRefreshScheduler())
        try model.loadPersistedState()

        try model.resumeRestoredSession()

        XCTAssertEqual(model.activeSession?.state, .running)
        XCTAssertEqual(model.displayedDuration, .seconds(25))
        XCTAssertNil(repository.savedActiveSnapshot)
    }

    func testDiscardingRestoredSessionCreatesNoCompletedSession() throws {
        let repository = InMemorySessionRepository()
        let snapshot = ActiveSessionSnapshot(id: UUID(), activityID: UUID(), titleSnapshot: "Writing", mode: .stopwatch, configuredDuration: nil, duration: .seconds(25), state: .paused)
        try repository.saveActive(snapshot)
        let model = AppModel(repository: repository, clock: TestClock(date: Date(timeIntervalSince1970: 1_000)), refreshScheduler: TestRefreshScheduler())
        try model.loadPersistedState()

        try model.discardRestoredSession()

        XCTAssertNil(model.restorableSession)
        XCTAssertNil(repository.savedActiveSnapshot)
        XCTAssertTrue(repository.savedCompletedSessions.isEmpty)
    }

    func testOverdueTimerDeadlinePersistsNaturalCompletion() throws {
        let repository = InMemorySessionRepository()
        let clock = TestClock(date: Date(timeIntervalSince1970: 1_000))
        let scheduler = TestRefreshScheduler()
        let model = AppModel(repository: repository, clock: clock, refreshScheduler: scheduler)
        let activity = try model.createActivity(named: "Writing")
        try model.startTimer(for: activity.id, duration: .seconds(60))
        clock.advance(by: .seconds(60))

        scheduler.fireActiveDeadlineTasks()

        XCTAssertEqual(repository.savedCompletedSessions.map(\.duration), [.seconds(60)])
        XCTAssertNil(model.activeSession)
    }
}

@MainActor
private final class InMemorySessionRepository: SessionRepository {
    private(set) var savedCompletedSessions: [CompletedSession] = []
    private var storedActivities: [Activity] = []
    private var activeSnapshot: ActiveSessionSnapshot?
    var savedActiveSnapshot: ActiveSessionSnapshot? { activeSnapshot }
    private(set) var recoveryCallCount = 0

    func createActivity(named name: ActivityName, createdAt: Date) throws -> Activity {
        let activity = Activity(id: UUID(), name: name, createdAt: createdAt)
        storedActivities.append(activity)
        return activity
    }

    func renameActivity(_ id: UUID, to name: ActivityName) throws -> Activity { fatalError("unused") }
    func deleteActivity(_ id: UUID) throws { fatalError("unused") }
    func activities() throws -> [Activity] { storedActivities }
    func saveCompleted(_ session: CompletedSession) throws { savedCompletedSessions.append(session) }
    func completedSessions() throws -> [CompletedSession] { savedCompletedSessions }
    func pendingDeliverySessions() throws -> [CompletedSession] { [] }
    func recoverInterruptedDeliveries() throws { recoveryCallCount += 1 }
    func updateDeliveryState(sessionID: UUID, to state: DeliveryState) throws { fatalError("unused") }
    func saveActive(_ snapshot: ActiveSessionSnapshot?) throws { activeSnapshot = snapshot }
    func loadActive() throws -> ActiveSessionSnapshot? { activeSnapshot }
}

@MainActor
private final class TestRefreshScheduler: RefreshScheduling {
    private var repeatingTasks: [(Duration, TestRefreshTask)] = []
    private var deadlineTasks: [(Duration, TestRefreshTask)] = []

    var activeRepeatingIntervals: [Duration] { repeatingTasks.filter { !$0.1.isCancelled }.map(\.0) }
    var activeDeadlineDurations: [Duration] { deadlineTasks.filter { !$0.1.isCancelled }.map(\.0) }

    func scheduleRepeating(every interval: Duration, action: @escaping @MainActor () -> Void) -> any RefreshTask {
        let task = TestRefreshTask(action: action)
        repeatingTasks.append((interval, task))
        return task
    }

    func scheduleDeadline(after duration: Duration, action: @escaping @MainActor () -> Void) -> any RefreshTask {
        let task = TestRefreshTask(action: action)
        deadlineTasks.append((duration, task))
        return task
    }

    func fireActiveRepeatingTasks() {
        repeatingTasks.filter { !$0.1.isCancelled }.forEach { $0.1.fire() }
    }

    func fireActiveDeadlineTasks() {
        deadlineTasks.filter { !$0.1.isCancelled }.forEach { $0.1.fire() }
    }
}

@MainActor
private final class TestRefreshTask: RefreshTask {
    private let action: @MainActor () -> Void
    private(set) var isCancelled = false

    init(action: @escaping @MainActor () -> Void = {}) { self.action = action }
    func cancel() { isCancelled = true }
    func fire() { action() }
}
