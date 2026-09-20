import Foundation

enum SessionRepositoryError: Error, Equatable {
    case activityNameConflict
    case activityNotFound
    case activityHasActiveSession
    case sessionIDConflict
    case sessionNotFound
    case invalidDeliveryStateTransition
}

@MainActor
protocol SessionRepository {
    func createActivity(named name: ActivityName, createdAt: Date) throws -> Activity
    func renameActivity(_ id: UUID, to name: ActivityName) throws -> Activity
    func deleteActivity(_ id: UUID) throws
    func activities() throws -> [Activity]
    func saveCompleted(_ session: CompletedSession) throws
    func completedSessions() throws -> [CompletedSession]
    func pendingDeliverySessions() throws -> [CompletedSession]
    func recoverInterruptedDeliveries() throws
    func updateDeliveryState(sessionID: UUID, to state: DeliveryState) throws
    func saveActive(_ snapshot: ActiveSessionSnapshot?) throws
    func loadActive() throws -> ActiveSessionSnapshot?
}
