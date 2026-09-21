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

@MainActor
protocol AppPreferences: AnyObject {
    var notesTargetName: String { get set }
    var notionDataSourceID: String { get set }
}

@MainActor
final class UserDefaultsAppPreferences: AppPreferences {
    static let defaultNotesTargetName = "Productivity Time Sessions"

    private enum Key {
        static let notesTargetName = "notesTargetName"
        static let notionDataSourceID = "notionDataSourceID"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var notesTargetName: String {
        get {
            let trimmed = defaults.string(forKey: Key.notesTargetName)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? Self.defaultNotesTargetName : trimmed
        }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.notesTargetName) }
    }

    var notionDataSourceID: String {
        get { defaults.string(forKey: Key.notionDataSourceID)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.notionDataSourceID) }
    }
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
    @Published private(set) var deliveryRecordsBySessionID: [UUID: [DeliveryDestination: DestinationDelivery]] = [:]
    @Published private(set) var notesTargetName: String
    @Published private(set) var notionDataSourceID: String
    @Published private(set) var isNotionTokenConfigured = false

    private let repository: any SessionRepository
    private let clock: any MonotonicClock
    private let refreshScheduler: any RefreshScheduling
    private let deliveryCoordinator: any DeliveryCoordinating
    private let notificationScheduler: any NotificationScheduling
    private let preferences: any AppPreferences
    private let credentialStore: any NotionCredentialStore
    private let notesSink: any NotesSessionSink
    private let notionSink: any NotionSessionSink
    private var runtime: ActiveRuntime?
    private var counterVisible = true
    private var counterTask: (any RefreshTask)?
    private var deadlineTask: (any RefreshTask)?
    private var didRecoverInterruptedDeliveries = false
    private var notificationGeneration = 0

    init() {
        do {
            repository = try SwiftDataStore(container: SwiftDataStore.makeInMemoryContainer())
        } catch {
            fatalError("Unable to initialize the in-memory session store: \(error)")
        }
        clock = ContinuousMonotonicClock()
        refreshScheduler = TaskRefreshScheduler()
        let preferences = UserDefaultsAppPreferences()
        self.preferences = preferences
        notesTargetName = preferences.notesTargetName
        notionDataSourceID = preferences.notionDataSourceID
        let credentials = KeychainNotionCredentialStore()
        credentialStore = credentials
        notesSink = AppleNotesAdapter()
        notionSink = NotionAPIClient(credentials: credentials)
        notificationScheduler = UserNotificationScheduler()
        deliveryCoordinator = DeliveryCoordinator(
            repository: repository,
            notes: notesSink,
            notion: notionSink,
            notesTarget: { NotesTarget(noteName: preferences.notesTargetName) },
            notionConfiguration: { NotionConfiguration(dataSourceID: preferences.notionDataSourceID) }
        )
        isNotionTokenConfigured = Self.hasStoredToken(credentials)
    }

    init(
        repository: any SessionRepository,
        clock: any MonotonicClock,
        refreshScheduler: any RefreshScheduling,
        deliveryCoordinator: (any DeliveryCoordinating)? = nil,
        notificationScheduler: any NotificationScheduling = UserNotificationScheduler(),
        preferences: any AppPreferences = UserDefaultsAppPreferences(),
        credentialStore: any NotionCredentialStore = KeychainNotionCredentialStore(),
        notesSink: any NotesSessionSink = AppleNotesAdapter(),
        notionSink: any NotionSessionSink = NotionAPIClient()
    ) {
        self.repository = repository
        self.clock = clock
        self.refreshScheduler = refreshScheduler
        self.preferences = preferences
        self.credentialStore = credentialStore
        self.notesSink = notesSink
        self.notionSink = notionSink
        self.notificationScheduler = notificationScheduler
        self.deliveryCoordinator = deliveryCoordinator ?? DeliveryCoordinator(
            repository: repository,
            notes: notesSink,
            notion: notionSink,
            notesTarget: { NotesTarget(noteName: preferences.notesTargetName) },
            notionConfiguration: { NotionConfiguration(dataSourceID: preferences.notionDataSourceID) }
        )
        notesTargetName = preferences.notesTargetName
        notionDataSourceID = preferences.notionDataSourceID
        isNotionTokenConfigured = Self.hasStoredToken(credentialStore)
    }

    static func applicationModel() -> AppModel {
        do {
            let repository = try SwiftDataStore(container: SwiftDataStore.makeApplicationContainer())
            let preferences = UserDefaultsAppPreferences()
            let credentials = KeychainNotionCredentialStore()
            let notes = AppleNotesAdapter()
            let notion = NotionAPIClient(credentials: credentials)
            return AppModel(
                repository: repository,
                clock: ContinuousMonotonicClock(),
                refreshScheduler: TaskRefreshScheduler(),
                notificationScheduler: UserNotificationScheduler(),
                preferences: preferences,
                credentialStore: credentials,
                notesSink: notes,
                notionSink: notion
            )
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
        try refreshDeliveryRecords()
        restorableSession = try repository.loadActive()
    }

    /// Lifecycle calls this exactly once after interrupted-delivery recovery and state loading.
    func deliverAllPendingInBackground() {
        Task { [weak self] in
            guard let self else { return }
            _ = await self.deliveryCoordinator.deliverAllPending()
            self.refreshDeliveryStateAfterDelivery()
        }
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
        // Save the paused representation before cancelling in-memory work so a
        // graceful termination never loses a running session between commands.
        guard let snapshot = makeSnapshot() else { return }
        try repository.saveActive(snapshot)
        try apply(runtime.engine.pause())
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

    func refreshHistory() throws {
        completedSessions = try repository.completedSessions()
        try refreshDeliveryRecords()
    }

    func deliveryRecord(for sessionID: UUID, destination: DeliveryDestination) -> DestinationDelivery? {
        deliveryRecordsBySessionID[sessionID]?[destination]
    }

    func retryDelivery(sessionID: UUID, destination: DeliveryDestination) {
        guard deliveryRecord(for: sessionID, destination: destination)?.phase == .failed else { return }
        Task { [weak self] in
            guard let self else { return }
            _ = await self.deliveryCoordinator.retry(sessionID: sessionID, destination: destination)
            self.refreshDeliveryStateAfterDelivery()
        }
    }

    func updateNotesTarget(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? UserDefaultsAppPreferences.defaultNotesTargetName : trimmed
        preferences.notesTargetName = value
        notesTargetName = value
    }

    func updateNotionDataSourceID(_ rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.notionDataSourceID = value
        notionDataSourceID = value
    }

    func updateNotionToken(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if value.isEmpty {
                try credentialStore.removeToken()
                isNotionTokenConfigured = false
            } else {
                try credentialStore.writeToken(Data(value.utf8))
                isNotionTokenConfigured = true
            }
        } catch {
            lastError = "Notion token could not be updated. Check Keychain access and try again."
            throw error
        }
    }

    func testNotesConnection() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.notesSink.testConnection(to: NotesTarget(noteName: self.notesTargetName))
                _ = await self.deliveryCoordinator.deliverPending(destination: .appleNotes)
                self.refreshDeliveryStateAfterDelivery()
            } catch {
                self.recordIntegrationError(for: .appleNotes)
            }
        }
    }

    func testNotionConnection() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.notionSink.testConnection(configuration: NotionConfiguration(dataSourceID: self.notionDataSourceID))
                _ = await self.deliveryCoordinator.deliverPending(destination: .notion)
                self.refreshDeliveryStateAfterDelivery()
            } catch {
                self.recordIntegrationError(for: .notion)
            }
        }
    }

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
            updateTimerNotificationForCurrentState()
        case let .completion(completion):
            do {
                try persist(completion: completion)
            } catch {
                clearRuntime(shouldRemoveTimerNotification: false)
                record(error)
                throw error
            }
            clearRuntime()
        }
    }

    func record(_ error: Error) {
        lastError = "The session could not be saved. \(error.localizedDescription)"
    }

    private func persist(completion: TimerCompletion) throws {
        guard let runtime else { return }
        let session = CompletedSession(id: UUID(), activityID: runtime.activityID, titleSnapshot: runtime.title, mode: runtime.engine.mode == .stopwatch ? .stopwatch : .timer, duration: completion.duration, completedAt: completion.completedAt, deliveryState: .pending)
        try repository.saveCompleted(session)
        completedSessions = try repository.completedSessions()
        try refreshDeliveryRecords()
        deliverAllPendingInBackground()
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

    private func clearRuntime(shouldRemoveTimerNotification: Bool = true) {
        if shouldRemoveTimerNotification, let runtime, runtime.engine.mode != .stopwatch {
            removeTimerNotification(identifier: runtime.id)
        }
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
            let runtimeID = runtime.id
            counterTask = refreshScheduler.scheduleRepeating(every: .seconds(1)) { [weak self] in self?.refreshDisplay(for: runtimeID) }
        }
        if runtime.engine.mode != .stopwatch {
            let runtimeID = runtime.id
            deadlineTask = refreshScheduler.scheduleDeadline(after: runtime.engine.displayDuration) { [weak self] in self?.completeTimerAtDeadline(for: runtimeID) }
        }
    }

    private func refreshDisplay(for runtimeID: UUID) {
        guard runtime?.id == runtimeID else { return }
        // This is presentation-only; persistence happens only on transitions and lifecycle events.
        publishRuntime()
    }

    private func completeTimerAtDeadline(for runtimeID: UUID) {
        guard let runtime, runtime.id == runtimeID else { return }
        do {
            try apply(runtime.engine.completeIfDue())
        } catch {
            record(error)
        }
    }

    // Used by deterministic composition tests; production timer completion always enters here via the deadline task.
    func completeTimerIfDueForTesting() throws {
        guard let runtime else { throw AppModelError.noActiveSession }
        try apply(runtime.engine.completeIfDue())
    }

    private func updateTimerNotificationForCurrentState() {
        guard let runtime, runtime.engine.mode != .stopwatch else { return }
        switch runtime.engine.state {
        case .running:
            scheduleTimerNotification(for: runtime)
        case .paused, .idle:
            removeTimerNotification(identifier: runtime.id)
        }
    }

    private func scheduleTimerNotification(for runtime: ActiveRuntime) {
        notificationGeneration += 1
        let generation = notificationGeneration
        let identifier = runtime.id.uuidString
        let deadline = clock.date.addingTimeInterval(runtime.engine.displayDuration.timeInterval)
        let title = runtime.title
        let scheduler = notificationScheduler
        Task { [weak self] in
            do {
                guard try await scheduler.requestAuthorization() else {
                    self?.recordNotificationError()
                    return
                }
                guard self?.isCurrentRunningTimer(id: runtime.id, generation: generation) == true else { return }
                try await scheduler.schedule(identifier: identifier, at: deadline, title: title)
                if self?.isCurrentRunningTimer(id: runtime.id, generation: generation) != true {
                    await scheduler.remove(identifier: identifier)
                }
            } catch {
                self?.recordNotificationError()
            }
        }
    }

    private func removeTimerNotification(identifier: UUID) {
        notificationGeneration += 1
        let scheduler = notificationScheduler
        Task { await scheduler.remove(identifier: identifier.uuidString) }
    }

    private func isCurrentRunningTimer(id: UUID, generation: Int) -> Bool {
        notificationGeneration == generation && runtime?.id == id && runtime?.engine.state == .running && runtime?.engine.mode != .stopwatch
    }

    private func refreshDeliveryRecords() throws {
        var values = [UUID: [DeliveryDestination: DestinationDelivery]]()
        for session in completedSessions {
            let records = try repository.deliveryRecords(for: session.id)
            values[session.id] = Dictionary(uniqueKeysWithValues: records.map { ($0.destination, $0) })
        }
        deliveryRecordsBySessionID = values
    }

    private func refreshDeliveryStateAfterDelivery() {
        do {
            completedSessions = try repository.completedSessions()
            try refreshDeliveryRecords()
        } catch {
            record(error)
        }
    }

    private func recordNotificationError() {
        lastError = "Timer notification could not be scheduled. Enable notifications in System Settings and try again."
    }

    private func recordIntegrationError(for destination: DeliveryDestination) {
        switch destination {
        case .appleNotes:
            lastError = "Apple Notes connection failed. Check Automation permission and the target note, then try again."
        case .notion:
            lastError = "Notion connection failed. Check the token, data source, and schema, then try again."
        }
    }

    private static func hasStoredToken(_ credentials: any NotionCredentialStore) -> Bool {
        do {
            return try credentials.readToken()?.isEmpty == false
        } catch {
            return false
        }
    }
}

private struct ActiveRuntime {
    let id: UUID
    let activityID: UUID
    let title: String
    let engine: TimerEngine
}
