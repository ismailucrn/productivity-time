import Foundation

@MainActor final class DeliveryCoordinator {
    private let repository: any SessionRepository; private let notes: any NotesSessionSink; private let notion: any NotionSessionSink
    private let notesTarget: @Sendable () -> NotesTarget; private let notionConfiguration: @Sendable () -> NotionConfiguration; private let now: @Sendable () -> Date
    private var inFlight = Set<String>()
    init(repository: any SessionRepository, notes: any NotesSessionSink, notion: any NotionSessionSink, notesTarget: @escaping @Sendable () -> NotesTarget, notionConfiguration: @escaping @Sendable () -> NotionConfiguration, now: @escaping @Sendable () -> Date = Date.init) { self.repository = repository; self.notes = notes; self.notion = notion; self.notesTarget = notesTarget; self.notionConfiguration = notionConfiguration; self.now = now }
    func deliverPending(destination: DeliveryDestination) async -> [DeliveryAttemptResult] {
        guard let jobs = try? repository.pendingDeliveryRecords(for: destination, at: now()) else { return [DeliveryAttemptResult(sessionID: UUID(), destination: destination, outcome: .failed("unknown"))] }
        var results = [DeliveryAttemptResult](); for job in jobs { results.append(await deliver(sessionID: job.sessionID, destination: destination)) }; return results
    }
    func deliverAllPending() async -> [DeliveryAttemptResult] { await deliverPending(destination: .appleNotes) + deliverPending(destination: .notion) }
    func retry(sessionID: UUID, destination: DeliveryDestination) async -> DeliveryAttemptResult { do { try repository.retryDelivery(sessionID: sessionID, destination: destination); return await deliver(sessionID: sessionID, destination: destination) } catch { return DeliveryAttemptResult(sessionID: sessionID, destination: destination, outcome: .failed("unknown")) } }
    private func deliver(sessionID: UUID, destination: DeliveryDestination) async -> DeliveryAttemptResult {
        let fallback = DeliveryAttemptResult(sessionID: sessionID, destination: destination, outcome: .failed("unknown"))
        let key = DestinationDeliveryRecord.jobKey(sessionID: sessionID, destination: destination); guard !inFlight.contains(key) else { return DeliveryAttemptResult(sessionID: sessionID, destination: destination, outcome: .skipped) }; inFlight.insert(key); defer { inFlight.remove(key) }
        do {
            guard try repository.claimDelivery(sessionID: sessionID, destination: destination, at: now()) != nil, let session = try repository.completedSessions().first(where: { $0.id == sessionID }) else { return DeliveryAttemptResult(sessionID: sessionID, destination: destination, outcome: .skipped) }
            let result: DeliveryResult = switch destination { case .appleNotes: try await notes.deliver(session, to: notesTarget()); case .notion: try await notion.deliver(session, configuration: notionConfiguration()) }
            _ = result; try repository.markDeliverySucceeded(sessionID: sessionID, destination: destination); return DeliveryAttemptResult(sessionID: sessionID, destination: destination, outcome: .delivered)
        } catch let error as DeliveryError { do { try repository.markDeliveryFailed(sessionID: sessionID, destination: destination, errorCategory: error.category, retryNotBefore: error.retryNotBefore); return DeliveryAttemptResult(sessionID: sessionID, destination: destination, outcome: .failed(error.category)) } catch { return fallback } } catch { do { try repository.markDeliveryFailed(sessionID: sessionID, destination: destination, errorCategory: "unknown", retryNotBefore: nil); return fallback } catch { return fallback } }
    }
}
