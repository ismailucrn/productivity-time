import Foundation

@MainActor final class DeliveryCoordinator {
    private let repository: any SessionRepository; private let notes: any NotesSessionSink; private let notion: any NotionSessionSink
    private let notesTarget: @Sendable () -> NotesTarget; private let notionConfiguration: @Sendable () -> NotionConfiguration; private let now: @Sendable () -> Date
    private var inFlight = Set<String>()
    init(repository: any SessionRepository, notes: any NotesSessionSink, notion: any NotionSessionSink, notesTarget: @escaping @Sendable () -> NotesTarget, notionConfiguration: @escaping @Sendable () -> NotionConfiguration, now: @escaping @Sendable () -> Date = Date.init) { self.repository = repository; self.notes = notes; self.notion = notion; self.notesTarget = notesTarget; self.notionConfiguration = notionConfiguration; self.now = now }
    func deliverPending(destination: DeliveryDestination) async -> [DeliveryAttemptResult] {
        let jobs: [DestinationDelivery]
        do { jobs = try repository.pendingDeliveryRecords(for: destination, at: now()) }
        catch { return [failed(sessionID: nil, destination: destination, category: .pendingFetch)] }
        var results = [DeliveryAttemptResult](); for job in jobs { results.append(await deliver(sessionID: job.sessionID, destination: destination)) }; return results
    }
    func deliverAllPending() async -> [DeliveryAttemptResult] { await deliverPending(destination: .appleNotes) + deliverPending(destination: .notion) }
    func retry(sessionID: UUID, destination: DeliveryDestination) async -> DeliveryAttemptResult {
        do {
            try repository.retryDelivery(sessionID: sessionID, destination: destination)
            return await deliver(sessionID: sessionID, destination: destination)
        } catch {
            return failed(sessionID: sessionID, destination: destination, category: .retry)
        }
    }
    private func deliver(sessionID: UUID, destination: DeliveryDestination) async -> DeliveryAttemptResult {
        let key = DestinationDeliveryRecord.jobKey(sessionID: sessionID, destination: destination); guard !inFlight.contains(key) else { return DeliveryAttemptResult(sessionID: sessionID, destination: destination, outcome: .skipped) }; inFlight.insert(key); defer { inFlight.remove(key) }

        let claim: DestinationDelivery
        do {
            guard let value = try repository.claimDelivery(sessionID: sessionID, destination: destination, at: now()) else {
                return DeliveryAttemptResult(sessionID: sessionID, destination: destination, outcome: .skipped)
            }
            claim = value
        } catch {
            return failed(sessionID: sessionID, destination: destination, category: .claim)
        }

        let session: CompletedSession
        do {
            guard let value = try repository.completedSessions().first(where: { $0.id == sessionID }) else {
                return await markClaimFailed(sessionID: sessionID, destination: destination, category: DeliveryAttemptFailureCategory.sessionLoad.rawValue, retryNotBefore: nil)
            }
            session = value
        } catch {
            return await markClaimFailed(sessionID: sessionID, destination: destination, category: DeliveryAttemptFailureCategory.sessionLoad.rawValue, retryNotBefore: nil)
        }

        _ = claim
        do {
            switch destination {
            case .appleNotes: _ = try await notes.deliver(session, to: notesTarget())
            case .notion: _ = try await notion.deliver(session, configuration: notionConfiguration())
            }
        } catch let error as DeliveryError {
            return await markClaimFailed(sessionID: sessionID, destination: destination, category: error.category, retryNotBefore: error.retryNotBefore)
        } catch {
            return await markClaimFailed(sessionID: sessionID, destination: destination, category: DeliveryAttemptFailureCategory.unknown.rawValue, retryNotBefore: nil)
        }

        do {
            try repository.markDeliverySucceeded(sessionID: sessionID, destination: destination)
            return DeliveryAttemptResult(sessionID: sessionID, destination: destination, outcome: .delivered)
        } catch {
            return await markClaimFailed(sessionID: sessionID, destination: destination, category: DeliveryAttemptFailureCategory.markSuccess.rawValue, retryNotBefore: nil)
        }
    }

    private func markClaimFailed(sessionID: UUID, destination: DeliveryDestination, category: String, retryNotBefore: Date?) async -> DeliveryAttemptResult {
        do {
            try repository.markDeliveryFailed(sessionID: sessionID, destination: destination, errorCategory: category, retryNotBefore: retryNotBefore)
            return DeliveryAttemptResult(sessionID: sessionID, destination: destination, outcome: .failed(category))
        } catch {
            return failed(sessionID: sessionID, destination: destination, category: .markFailure)
        }
    }

    private func failed(sessionID: UUID?, destination: DeliveryDestination, category: DeliveryAttemptFailureCategory) -> DeliveryAttemptResult {
        DeliveryAttemptResult(sessionID: sessionID, destination: destination, outcome: .failed(category.rawValue))
    }
}
