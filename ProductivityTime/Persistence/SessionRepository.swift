import Foundation

enum SessionRepositoryError: Error, Equatable {
    case activityNameConflict
    case activityNotFound
    case activityHasActiveSession
    case sessionIDConflict
    case sessionNotFound
    case destinationDeliveryNotFound
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
    func deliveryRecords(for sessionID: UUID) throws -> [DestinationDelivery]
    func pendingDeliveryRecords(for destination: DeliveryDestination, at date: Date) throws -> [DestinationDelivery]
    func claimDelivery(sessionID: UUID, destination: DeliveryDestination, at date: Date) throws -> DestinationDelivery?
    func markDeliverySucceeded(sessionID: UUID, destination: DeliveryDestination) throws
    func markDeliveryFailed(sessionID: UUID, destination: DeliveryDestination, errorCategory: String, retryNotBefore: Date?) throws
    func retryDelivery(sessionID: UUID, destination: DeliveryDestination) throws
    func recoverInterruptedDeliveries() throws
    func updateDeliveryState(sessionID: UUID, to state: DeliveryState) throws
    func saveActive(_ snapshot: ActiveSessionSnapshot?) throws
    func loadActive() throws -> ActiveSessionSnapshot?
}
