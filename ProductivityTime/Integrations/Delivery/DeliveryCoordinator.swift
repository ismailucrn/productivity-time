import Foundation

@MainActor final class DeliveryCoordinator {
    private let repository: any SessionRepository; private let notes: any NotesSessionSink; private let notion: any NotionSessionSink
    private let notesTarget: @Sendable () -> NotesTarget; private let notionConfiguration: @Sendable () -> NotionConfiguration; private let now: @Sendable () -> Date
    private var inFlight = Set<String>()
    init(repository: any SessionRepository, notes: any NotesSessionSink, notion: any NotionSessionSink, notesTarget: @escaping @Sendable () -> NotesTarget, notionConfiguration: @escaping @Sendable () -> NotionConfiguration, now: @escaping @Sendable () -> Date = Date.init) { self.repository = repository; self.notes = notes; self.notion = notion; self.notesTarget = notesTarget; self.notionConfiguration = notionConfiguration; self.now = now }
    func deliverAllPending() async { await deliverPending(destination: .appleNotes); await deliverPending(destination: .notion) }
    func deliverPending(destination: DeliveryDestination) async { let jobs = (try? repository.pendingDeliveryRecords(for: destination, at: now())) ?? []; for job in jobs { await deliver(sessionID: job.sessionID, destination: destination) } }
    func retry(sessionID: UUID, destination: DeliveryDestination) async { do { try repository.retryDelivery(sessionID: sessionID, destination: destination); await deliver(sessionID: sessionID, destination: destination) } catch {} }
    private func deliver(sessionID: UUID, destination: DeliveryDestination) async {
        let key = DestinationDeliveryRecord.jobKey(sessionID: sessionID, destination: destination); guard !inFlight.contains(key) else { return }; inFlight.insert(key); defer { inFlight.remove(key) }
        do {
            guard try repository.claimDelivery(sessionID: sessionID, destination: destination, at: now()) != nil, let session = try repository.completedSessions().first(where: { $0.id == sessionID }) else { return }
            let result: DeliveryResult = switch destination { case .appleNotes: try await notes.deliver(session, to: notesTarget()); case .notion: try await notion.deliver(session, configuration: notionConfiguration()) }
            _ = result; try repository.markDeliverySucceeded(sessionID: sessionID, destination: destination)
        } catch let error as DeliveryError { try? repository.markDeliveryFailed(sessionID: sessionID, destination: destination, errorCategory: error.category, retryNotBefore: error.retryNotBefore) } catch { try? repository.markDeliveryFailed(sessionID: sessionID, destination: destination, errorCategory: "unknown", retryNotBefore: nil) }
    }
}
