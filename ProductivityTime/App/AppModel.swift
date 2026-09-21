import Combine
import Foundation

@MainActor
protocol RefreshTask: AnyObject { func cancel() }

@MainActor
protocol RefreshScheduling {
    func scheduleRepeating(every interval: Duration, action: @escaping @MainActor () -> Void) -> any RefreshTask
    func scheduleDeadline(after duration: Duration, action: @escaping @MainActor () -> Void) -> any RefreshTask
}

@MainActor
final class TaskRefreshScheduler: RefreshScheduling {
    func scheduleRepeating(every interval: Duration, action: @escaping @MainActor () -> Void) -> any RefreshTask {
        ScheduledTask {
            while !Task.isCancelled {
                guard (try? await Task.sleep(for: interval)) != nil else { return }
                guard !Task.isCancelled else { return }
                await action()
            }
        }
    }

    func scheduleDeadline(after duration: Duration, action: @escaping @MainActor () -> Void) -> any RefreshTask {
        ScheduledTask {
            guard (try? await Task.sleep(for: duration)) != nil else { return }
            guard !Task.isCancelled else { return }
            await action()
        }
    }
}

private final class ScheduledTask: RefreshTask {
    private let task: Task<Void, Never>

    init(operation: @escaping @Sendable () async -> Void) { task = Task(operation: operation) }
    func cancel() { task.cancel() }
}

enum AppModelError: Error, Equatable {
    case activeSessionAlreadyExists
    case activityNotFound
    case noActiveSession
}

struct ActiveSessionPresentation: Equatable, Identifiable {
    let id: UUID
    let activityID: UUID
    let title: String
    let mode: SessionMode
    let state: TimerState
    let configuredDuration: Duration?
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var activeSession: ActiveSessionPresentation?
    @Published private(set) var displayedDuration: Duration = .zero
    @Published private(set) var activities: [Activity] = []
    @Published private(set) var completedSessions: [CompletedSession] = []
    @Published private(set) var restorableSession: ActiveSessionSnapshot?
    @Published private(set) var lastError: String?
    @Published private(set) var selectedActivityID: UUID?

    private let repository: any SessionRepository
    private let clock: any MonotonicClock
    private let refreshScheduler: any RefreshScheduling
    private var runtime: ActiveRuntime?
    private var counterVisible = true
    private var counterTask: (any RefreshTask)?
    private var deadlineTask: (any RefreshTask)?
    private var didRecoverInterruptedDeliveries = false

    init() {
        do {
            repository = try SwiftDataStore(container: SwiftDataStore.makeInMemoryContainer())
        } catch {
            fatalError("Unable to initialize the in-memory session store: \(error)")
        }
        clock = ContinuousMonotonicClock()
        refreshScheduler = TaskRefreshScheduler()
    }

    init(repository: any SessionRepository, clock: any MonotonicClock, refreshScheduler: any RefreshScheduling) {
        self.repository = repository
        self.clock = clock
        self.refreshScheduler = refreshScheduler
    }

    static func applicationModel() -> AppModel {
        do {
            return try AppModel(repository: SwiftDataStore(container: SwiftDataStore.makeApplicationContainer()), clock: ContinuousMonotonicClock(), refreshScheduler: TaskRefreshScheduler())
        } catch {
            fatalError("Unable to initialize the local session store: \(error)")
        }
    }

    func recoverInterruptedDeliveriesOnce() throws {
        guard !didRecoverInterruptedDeliveries else { return }
        try repository.recoverInterruptedDeliveries()
        didRecoverInterruptedDeliveries = true
    }

    func loadPersistedState() throws {
        activities = try repository.activities()
        completedSessions = try repository.completedSessions()
        restorableSession = try repository.loadActive()
    }

    func createActivity(named rawName: String) throws -> Activity {
        let activity = try repository.createActivity(named: ActivityName(rawName), createdAt: clock.date)
        activities = try repository.activities()
        return activity
    }

    func selectActivity(_ activityID: UUID?) {
        selectedActivityID = activityID
    }

    func startStopwatch(for activityID: UUID) throws { try start(for: activityID, mode: .stopwatch) }
    func startTimer(for activityID: UUID, duration: Duration) throws { try start(for: activityID, mode: .timer(configured: duration)) }

    func pause() throws {
        guard let runtime else { throw AppModelError.noActiveSession }
        try apply(runtime.engine.pause())
    }

    func resume() throws {
        guard let runtime else { throw AppModelError.noActiveSession }
        try apply(runtime.engine.resume())
    }

    func reset() throws {
        guard let runtime else { throw AppModelError.noActiveSession }
        try apply(runtime.engine.reset())
        if self.runtime != nil, runtime.engine.state == .idle { clearRuntime() }
    }

    func cancel() throws {
        guard let runtime else { throw AppModelError.noActiveSession }
        try apply(runtime.engine.cancel())
        if self.runtime != nil, runtime.engine.state == .idle { clearRuntime() }
    }

    func setCounterVisible(_ isVisible: Bool) {
        counterVisible = isVisible
        rescheduleTasks()
    }

    func snapshotForGracefulQuit() throws {
        guard let runtime else {
            try repository.saveActive(nil)
            return
        }
        try apply(runtime.engine.pause())
        guard let snapshot = makeSnapshot() else {
            try repository.saveActive(nil)
            return
        }
        try repository.saveActive(snapshot)
    }

    func resumeRestoredSession() throws {
        guard let snapshot = restorableSession else { return }
        let mode: TimerMode = switch snapshot.mode {
        case .stopwatch: .stopwatch
        case .timer: .timer(configured: snapshot.configuredDuration ?? snapshot.duration)
        }
        let engine = TimerEngine(mode: mode, clock: clock, restoredDuration: snapshot.duration, state: .paused)
        runtime = ActiveRuntime(id: snapshot.id, activityID: snapshot.activityID, title: snapshot.titleSnapshot, engine: engine)
        restorableSession = nil
        try repository.saveActive(nil)
        try apply(engine.resume())
    }

    func discardRestoredSession() throws {
        restorableSession = nil
        try repository.saveActive(nil)
    }

    func refreshHistory() throws { completedSessions = try repository.completedSessions() }

    private func start(for activityID: UUID, mode: TimerMode) throws {
        guard runtime == nil else { throw AppModelError.activeSessionAlreadyExists }
        let storedActivities = try repository.activities()
        guard let activity = activities.first(where: { $0.id == activityID }) ?? storedActivities.first(where: { $0.id == activityID }) else {
            throw AppModelError.activityNotFound
        }
        let engine = TimerEngine(mode: mode, clock: clock)
        runtime = ActiveRuntime(id: UUID(), activityID: activity.id, title: activity.name.value, engine: engine)
        try apply(engine.start())
    }

    private func apply(_ transition: TimerTransition) throws {
        switch transition {
        case .none:
            publishRuntime()
        case .stateChanged:
            publishRuntime()
            rescheduleTasks()
        case let .completion(completion):
            try persist(completion: completion)
            clearRuntime()
        }
    }

    private func persist(completion: TimerCompletion) throws {
        guard let runtime else { return }
        let session = CompletedSession(id: UUID(), activityID: runtime.activityID, titleSnapshot: runtime.title, mode: runtime.engine.mode == .stopwatch ? .stopwatch : .timer, duration: completion.duration, completedAt: completion.completedAt, deliveryState: .pending)
        try repository.saveCompleted(session)
        completedSessions = try repository.completedSessions()
    }

    private func makeSnapshot() -> ActiveSessionSnapshot? {
        guard let runtime, runtime.engine.state != .idle else { return nil }
        let configuredDuration: Duration? = switch runtime.engine.mode {
        case .stopwatch: nil
        case let .timer(configured): configured
        }
        return ActiveSessionSnapshot(id: runtime.id, activityID: runtime.activityID, titleSnapshot: runtime.title, mode: runtime.engine.mode == .stopwatch ? .stopwatch : .timer, configuredDuration: configuredDuration, duration: runtime.engine.displayDuration, state: .paused)
    }

    private func publishRuntime() {
        guard let runtime else {
            activeSession = nil
            displayedDuration = .zero
            return
        }
        let configuredDuration: Duration? = switch runtime.engine.mode {
        case .stopwatch: nil
        case let .timer(configured): configured
        }
        activeSession = ActiveSessionPresentation(id: runtime.id, activityID: runtime.activityID, title: runtime.title, mode: runtime.engine.mode == .stopwatch ? .stopwatch : .timer, state: runtime.engine.state, configuredDuration: configuredDuration)
        displayedDuration = runtime.engine.displayDuration
    }

    private func clearRuntime() {
        counterTask?.cancel()
        deadlineTask?.cancel()
        counterTask = nil
        deadlineTask = nil
        runtime = nil
        publishRuntime()
    }

    private func rescheduleTasks() {
        counterTask?.cancel()
        deadlineTask?.cancel()
        counterTask = nil
        deadlineTask = nil
        guard let runtime, runtime.engine.state == .running else { return }
        if counterVisible {
            counterTask = refreshScheduler.scheduleRepeating(every: .seconds(1)) { [weak self] in self?.refreshDisplay() }
        }
        if runtime.engine.mode != .stopwatch {
            deadlineTask = refreshScheduler.scheduleDeadline(after: runtime.engine.displayDuration) { [weak self] in self?.completeTimerAtDeadline() }
        }
    }

    private func refreshDisplay() {
        // This is presentation-only; persistence happens only on transitions and lifecycle events.
        publishRuntime()
    }

    private func completeTimerAtDeadline() {
        guard let runtime else { return }
        do {
            try apply(runtime.engine.completeIfDue())
        } catch {
            lastError = "The completed session could not be saved."
        }
    }
}

private struct ActiveRuntime {
    let id: UUID
    let activityID: UUID
    let title: String
    let engine: TimerEngine
}
