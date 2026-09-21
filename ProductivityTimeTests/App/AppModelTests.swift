import AppKit
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

    func testStopwatchResetPersistenceFailureClearsRuntimeTasksAndReportsError() throws {
        let repository = InMemorySessionRepository()
        repository.shouldFailSavingCompletedSession = true
        let scheduler = TestRefreshScheduler()
        let clock = TestClock(date: Date(timeIntervalSince1970: 1_000))
        let model = AppModel(repository: repository, clock: clock, refreshScheduler: scheduler)
        let activity = try model.createActivity(named: "Writing")
        try model.startStopwatch(for: activity.id)
        clock.advance(by: .seconds(25))

        XCTAssertThrowsError(try model.reset())

        XCTAssertNil(model.activeSession)
        XCTAssertTrue(scheduler.activeRepeatingIntervals.isEmpty)
        XCTAssertTrue(scheduler.activeDeadlineDurations.isEmpty)
        XCTAssertNotNil(model.lastError)
    }

    func testTimerDeadlineReloadFailureClearsRuntimeTasksAndReportsError() throws {
        let repository = InMemorySessionRepository()
        repository.shouldFailLoadingCompletedSessions = true
        let scheduler = TestRefreshScheduler()
        let clock = TestClock(date: Date(timeIntervalSince1970: 1_000))
        let model = AppModel(repository: repository, clock: clock, refreshScheduler: scheduler)
        let activity = try model.createActivity(named: "Writing")
        try model.startTimer(for: activity.id, duration: .seconds(60))
        clock.advance(by: .seconds(60))

        scheduler.fireActiveDeadlineTasks()

        XCTAssertNil(model.activeSession)
        XCTAssertTrue(scheduler.activeRepeatingIntervals.isEmpty)
        XCTAssertTrue(scheduler.activeDeadlineDurations.isEmpty)
        XCTAssertNotNil(model.lastError)
    }

    func testWindowVisibilityObserverStopsStopwatchRefreshWhenWindowBecomesInactive() throws {
        let repository = InMemorySessionRepository()
        let scheduler = TestRefreshScheduler()
        let model = AppModel(repository: repository, clock: TestClock(date: Date(timeIntervalSince1970: 1_000)), refreshScheduler: scheduler)
        let observer = WindowVisibilityObserver()
        observer.bind(model: model)
        observer.update(state: .visible)
        let activity = try model.createActivity(named: "Writing")
        try model.startStopwatch(for: activity.id)

        observer.update(state: .inactive)

        XCTAssertTrue(scheduler.activeRepeatingIntervals.isEmpty)
        XCTAssertTrue(scheduler.activeDeadlineDurations.isEmpty)
    }

    func testWindowVisibilityObserverKeepsOnlyTimerDeadlineWhenWindowIsOccluded() throws {
        let repository = InMemorySessionRepository()
        let scheduler = TestRefreshScheduler()
        let model = AppModel(repository: repository, clock: TestClock(date: Date(timeIntervalSince1970: 1_000)), refreshScheduler: scheduler)
        let observer = WindowVisibilityObserver()
        observer.bind(model: model)
        observer.update(state: .visible)
        let activity = try model.createActivity(named: "Writing")
        try model.startTimer(for: activity.id, duration: .seconds(60))

        observer.update(state: .occluded)

        XCTAssertTrue(scheduler.activeRepeatingIntervals.isEmpty)
        XCTAssertEqual(scheduler.activeDeadlineDurations, [.seconds(60)])
    }

    func testWindowVisibilityObserverKeepsOnlyTimerDeadlineWhenMinimizedOrSheetObscured() throws {
        let repository = InMemorySessionRepository()
        let scheduler = TestRefreshScheduler()
        let model = AppModel(repository: repository, clock: TestClock(date: Date(timeIntervalSince1970: 1_000)), refreshScheduler: scheduler)
        let observer = WindowVisibilityObserver()
        observer.bind(model: model)
        observer.update(state: .visible)
        let activity = try model.createActivity(named: "Writing")
        try model.startTimer(for: activity.id, duration: .seconds(60))

        observer.update(state: WindowVisibilityState(appIsActive: true, windowIsKey: true, windowIsVisible: true, windowIsMiniaturized: true, windowIsOccluded: false, isObscuredBySheet: false))
        XCTAssertTrue(scheduler.activeRepeatingIntervals.isEmpty)
        XCTAssertEqual(scheduler.activeDeadlineDurations, [.seconds(60)])

        observer.update(state: WindowVisibilityState(appIsActive: true, windowIsKey: false, windowIsVisible: true, windowIsMiniaturized: false, windowIsOccluded: false, isObscuredBySheet: true))
        XCTAssertTrue(scheduler.activeRepeatingIntervals.isEmpty)
        XCTAssertEqual(scheduler.activeDeadlineDurations, [.seconds(60)])
    }

    func testBeginSheetNotificationImmediatelyStopsStopwatchRefreshAndEndSheetRestoresIt() async throws {
        var state = WindowVisibilityState.visible
        let observer = WindowVisibilityObserver { _ in state }
        let repository = InMemorySessionRepository()
        let scheduler = TestRefreshScheduler()
        let model = AppModel(repository: repository, clock: TestClock(date: Date(timeIntervalSince1970: 1_000)), refreshScheduler: scheduler)
        let window = NSWindow()
        observer.bind(model: model)
        observer.attach(to: window)
        defer { observer.stop() }
        let activity = try model.createActivity(named: "Writing")
        try model.startStopwatch(for: activity.id)

        state = WindowVisibilityState(appIsActive: true, windowIsKey: true, windowIsVisible: true, windowIsMiniaturized: false, windowIsOccluded: false, isObscuredBySheet: true)
        NotificationCenter.default.post(name: NSWindow.willBeginSheetNotification, object: window)
        await Task.yield()

        XCTAssertTrue(scheduler.activeRepeatingIntervals.isEmpty)
        XCTAssertTrue(scheduler.activeDeadlineDurations.isEmpty)

        state = .visible
        NotificationCenter.default.post(name: NSWindow.didEndSheetNotification, object: window)
        await Task.yield()

        XCTAssertEqual(scheduler.activeRepeatingIntervals, [.seconds(1)])
    }

    func testEndSheetNotificationKeepsOnlyTimerDeadlineWhenAppRemainsInactive() async throws {
        var state = WindowVisibilityState.visible
        let observer = WindowVisibilityObserver { _ in state }
        let repository = InMemorySessionRepository()
        let scheduler = TestRefreshScheduler()
        let model = AppModel(repository: repository, clock: TestClock(date: Date(timeIntervalSince1970: 1_000)), refreshScheduler: scheduler)
        let window = NSWindow()
        observer.bind(model: model)
        observer.attach(to: window)
        defer { observer.stop() }
        let activity = try model.createActivity(named: "Writing")
        try model.startTimer(for: activity.id, duration: .seconds(60))

        state = WindowVisibilityState(appIsActive: true, windowIsKey: true, windowIsVisible: true, windowIsMiniaturized: false, windowIsOccluded: false, isObscuredBySheet: true)
        NotificationCenter.default.post(name: NSWindow.willBeginSheetNotification, object: window)
        await Task.yield()

        XCTAssertTrue(scheduler.activeRepeatingIntervals.isEmpty)
        XCTAssertEqual(scheduler.activeDeadlineDurations, [.seconds(60)])

        state = .inactive
        NotificationCenter.default.post(name: NSWindow.didEndSheetNotification, object: window)
        await Task.yield()

        XCTAssertTrue(scheduler.activeRepeatingIntervals.isEmpty)
        XCTAssertEqual(scheduler.activeDeadlineDurations, [.seconds(60)])
    }

    func testNaturalTimerCompletionPersistsBothDestinationJobsBeforeStartingDelivery() async throws {
        let repository = InMemorySessionRepository()
        let clock = TestClock(date: Date(timeIntervalSince1970: 1_000))
        let delivery = RecordingDeliveryCoordinator()
        let model = AppModel(
            repository: repository,
            clock: clock,
            refreshScheduler: TestRefreshScheduler(),
            deliveryCoordinator: delivery,
            notificationScheduler: RecordingNotificationScheduler()
        )
        let activity = try model.createActivity(named: "Writing")
        try model.startTimer(for: activity.id, duration: .seconds(60))
        clock.advance(by: .seconds(60))

        try model.completeTimerIfDueForTesting()
        await Task.yield()

        XCTAssertEqual(repository.savedCompletedSessions.count, 1)
        XCTAssertEqual(Set(repository.jobs.map(\.destination)), Set(DeliveryDestination.allCases))
        let deliveryCalls = await delivery.deliverAllCallCount
        XCTAssertEqual(deliveryCalls, 1)
    }

    func testTimerNotificationUsesStableRuntimeIdentifierAndPauseResumeReplacesDeadline() async throws {
        let repository = InMemorySessionRepository()
        let clock = TestClock(date: Date(timeIntervalSince1970: 1_000))
        let notifications = RecordingNotificationScheduler()
        let model = AppModel(
            repository: repository,
            clock: clock,
            refreshScheduler: TestRefreshScheduler(),
            deliveryCoordinator: RecordingDeliveryCoordinator(),
            notificationScheduler: notifications
        )
        let activity = try model.createActivity(named: "Writing")

        try model.startTimer(for: activity.id, duration: .seconds(60))
        await Task.yield()
        let first = await notifications.requests
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].deadline, Date(timeIntervalSince1970: 1_060))
        let identifier = first[0].identifier

        clock.advance(by: .seconds(10))
        try model.pause()
        await Task.yield()
        let removed = await notifications.removed
        XCTAssertEqual(removed, [identifier])

        try model.resume()
        await Task.yield()
        let requests = await notifications.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].identifier, identifier)
        XCTAssertEqual(requests[1].deadline, Date(timeIntervalSince1970: 1_060))
    }

    func testCompletionPersistenceFailureDoesNotStartDeliveryOrTouchNotificationBoundary() async throws {
        let repository = InMemorySessionRepository()
        repository.shouldFailSavingCompletedSession = true
        let clock = TestClock(date: Date(timeIntervalSince1970: 1_000))
        let delivery = RecordingDeliveryCoordinator()
        let notifications = RecordingNotificationScheduler()
        let model = AppModel(
            repository: repository,
            clock: clock,
            refreshScheduler: TestRefreshScheduler(),
            deliveryCoordinator: delivery,
            notificationScheduler: notifications
        )
        let activity = try model.createActivity(named: "Writing")
        try model.startStopwatch(for: activity.id)
        clock.advance(by: .seconds(5))

        XCTAssertThrowsError(try model.reset())
        XCTAssertEqual(delivery.deliverAllCallCountSynchronously, 0)
        let notificationOperations = await notifications.operationCount
        XCTAssertEqual(notificationOperations, 0)
    }

    func testTimerCancelAndNaturalCompletionRemoveItsNotificationButStopwatchNeverSchedulesOne() async throws {
        let repository = InMemorySessionRepository()
        let clock = TestClock(date: Date(timeIntervalSince1970: 1_000))
        let notifications = RecordingNotificationScheduler()
        let model = AppModel(repository: repository, clock: clock, refreshScheduler: TestRefreshScheduler(), deliveryCoordinator: RecordingDeliveryCoordinator(), notificationScheduler: notifications)
        let activity = try model.createActivity(named: "Writing")

        try model.startStopwatch(for: activity.id)
        await Task.yield()
        let stopwatchRequests = await notifications.requests
        XCTAssertTrue(stopwatchRequests.isEmpty)
        try model.cancel()

        try model.startTimer(for: activity.id, duration: .seconds(60))
        await Task.yield()
        let timerRequests = await notifications.requests
        let identifier = try XCTUnwrap(timerRequests.first?.identifier)
        try model.cancel()
        await Task.yield()
        let removedAfterCancel = await notifications.removed
        XCTAssertEqual(removedAfterCancel, [identifier])

        try model.startTimer(for: activity.id, duration: .seconds(60))
        clock.advance(by: .seconds(60))
        try model.completeTimerIfDueForTesting()
        await Task.yield()
        let removed = await notifications.removed
        XCTAssertEqual(removed.count, 2)
    }

    func testDeniedTimerNotificationAuthorizationLeavesTimerRunningAndReportsSanitizedError() async throws {
        let repository = InMemorySessionRepository()
        let notifications = RecordingNotificationScheduler(granted: false)
        let model = AppModel(repository: repository, clock: TestClock(date: Date(timeIntervalSince1970: 1_000)), refreshScheduler: TestRefreshScheduler(), deliveryCoordinator: RecordingDeliveryCoordinator(), notificationScheduler: notifications)
        let activity = try model.createActivity(named: "Writing")

        try model.startTimer(for: activity.id, duration: .seconds(60))
        await Task.yield()

        XCTAssertEqual(model.activeSession?.state, .running)
        let deniedRequests = await notifications.requests
        XCTAssertTrue(deniedRequests.isEmpty)
        XCTAssertEqual(model.lastError, "Timer notification could not be scheduled. Enable notifications in System Settings and try again.")
    }

}

@MainActor
private final class InMemorySessionRepository: SessionRepository {
    private(set) var savedCompletedSessions: [CompletedSession] = []
    private var storedActivities: [Activity] = []
    private var activeSnapshot: ActiveSessionSnapshot?
    var savedActiveSnapshot: ActiveSessionSnapshot? { activeSnapshot }
    private(set) var recoveryCallCount = 0
    private(set) var jobs: [DestinationDelivery] = []
    var shouldFailSavingCompletedSession = false
    var shouldFailLoadingCompletedSessions = false

    func createActivity(named name: ActivityName, createdAt: Date) throws -> Activity {
        let activity = Activity(id: UUID(), name: name, createdAt: createdAt)
        storedActivities.append(activity)
        return activity
    }

    func renameActivity(_ id: UUID, to name: ActivityName) throws -> Activity { fatalError("unused") }
    func deleteActivity(_ id: UUID) throws { fatalError("unused") }
    func activities() throws -> [Activity] { storedActivities }
    func saveCompleted(_ session: CompletedSession) throws {
        guard !shouldFailSavingCompletedSession else { throw TestRepositoryError.persistenceFailed }
        savedCompletedSessions.append(session)
        jobs += DeliveryDestination.allCases.map {
            DestinationDelivery(sessionID: session.id, destination: $0, phase: .pending, errorCategory: nil, retryNotBefore: nil)
        }
    }
    func completedSessions() throws -> [CompletedSession] {
        guard !shouldFailLoadingCompletedSessions else { throw TestRepositoryError.persistenceFailed }
        return savedCompletedSessions
    }
    func pendingDeliverySessions() throws -> [CompletedSession] { [] }
    func deliveryRecords(for sessionID: UUID) throws -> [DestinationDelivery] { jobs.filter { $0.sessionID == sessionID } }
    func pendingDeliveryRecords(for destination: DeliveryDestination, at date: Date) throws -> [DestinationDelivery] { jobs.filter { $0.destination == destination && $0.phase == .pending } }
    func claimDelivery(sessionID: UUID, destination: DeliveryDestination, at date: Date) throws -> DestinationDelivery? { nil }
    func markDeliverySucceeded(sessionID: UUID, destination: DeliveryDestination) throws {}
    func markDeliveryFailed(sessionID: UUID, destination: DeliveryDestination, errorCategory: String, retryNotBefore: Date?) throws {}
    func retryDelivery(sessionID: UUID, destination: DeliveryDestination) throws {}
    func recoverInterruptedDeliveries() throws { recoveryCallCount += 1 }
    func updateDeliveryState(sessionID: UUID, to state: DeliveryState) throws { fatalError("unused") }
    func saveActive(_ snapshot: ActiveSessionSnapshot?) throws { activeSnapshot = snapshot }
    func loadActive() throws -> ActiveSessionSnapshot? { activeSnapshot }
}

private enum TestRepositoryError: Error { case persistenceFailed }

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

@MainActor
private final class RecordingDeliveryCoordinator: DeliveryCoordinating {
    private(set) var deliverAllCallCountSynchronously = 0
    var deliverAllCallCount: Int { deliverAllCallCountSynchronously }

    func deliverAllPending() async -> [DeliveryAttemptResult] {
        deliverAllCallCountSynchronously += 1
        return []
    }

    func deliverPending(destination: DeliveryDestination) async -> [DeliveryAttemptResult] { [] }
    func retry(sessionID: UUID, destination: DeliveryDestination) async -> DeliveryAttemptResult {
        DeliveryAttemptResult(sessionID: sessionID, destination: destination, outcome: .skipped)
    }
}

private actor RecordingNotificationScheduler: NotificationScheduling {
    private(set) var requests = [TimerNotificationRequest]()
    private(set) var removed = [String]()
    var operationCount: Int { requests.count + removed.count }

    private let granted: Bool
    init(granted: Bool = true) { self.granted = granted }

    func requestAuthorization() async throws -> Bool { granted }
    func schedule(identifier: String, at deadline: Date, title: String) async throws {
        requests.append(TimerNotificationRequest(identifier: identifier, deadline: deadline, title: title))
    }
    func remove(identifier: String) async { removed.append(identifier) }
}
