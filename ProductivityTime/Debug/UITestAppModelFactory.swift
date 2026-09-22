import Foundation

#if DEBUG
@MainActor
enum UITestAppModelFactory {
    static let sessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    static func makeIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) throws -> AppModel? {
        guard arguments.contains("--ui-test-fixture"), arguments.contains("mixed-history") else { return nil }

        let store = try SwiftDataStore(container: SwiftDataStore.makeInMemoryContainer())
        let activity = try store.createActivity(named: ActivityName("Writing"), createdAt: Date(timeIntervalSince1970: 1_704_067_000))
        let session = CompletedSession(
            id: sessionID,
            activityID: activity.id,
            titleSnapshot: "Writing",
            mode: .timer,
            duration: .seconds(1_500),
            completedAt: Date(timeIntervalSince1970: 1_704_067_200),
            deliveryState: .pending
        )
        try store.saveCompleted(session)
        _ = try store.claimDelivery(sessionID: session.id, destination: .appleNotes, at: Date(timeIntervalSince1970: 1_704_067_201))
        try store.markDeliverySucceeded(sessionID: session.id, destination: .appleNotes)
        _ = try store.claimDelivery(sessionID: session.id, destination: .notion, at: Date(timeIntervalSince1970: 1_704_067_201))
        try store.markDeliveryFailed(sessionID: session.id, destination: .notion, errorCategory: "network", retryNotBefore: nil)

        let model = AppModel(
            repository: store,
            clock: ContinuousMonotonicClock(),
            refreshScheduler: TaskRefreshScheduler(),
            deliveryCoordinator: UITestNoopDeliveryCoordinator(),
            credentialStore: UITestMemoryCredentials()
        )
        try model.loadPersistedState()
        return model
    }
}

@MainActor private final class UITestNoopDeliveryCoordinator: DeliveryCoordinating {
    func deliverPending(destination: DeliveryDestination) async -> [DeliveryAttemptResult] { [] }
    func deliverAllPending() async -> [DeliveryAttemptResult] { [] }
    func retry(sessionID: UUID, destination: DeliveryDestination) async -> DeliveryAttemptResult {
        .init(sessionID: sessionID, destination: destination, outcome: .skipped)
    }
}

private final class UITestMemoryCredentials: NotionCredentialStore, @unchecked Sendable {
    func readToken() throws -> Data? { nil }
    func writeToken(_ token: Data) throws {}
    func removeToken() throws {}
}
#endif
