import Foundation

enum DeliveryDestination: String, CaseIterable, Sendable {
    case appleNotes
    case notion
}

enum DeliveryPhase: String, Equatable, Sendable {
    case pending
    case delivering
    case delivered
    case failed
}

struct DestinationDelivery: Equatable, Sendable, Identifiable {
    let sessionID: UUID
    let destination: DeliveryDestination
    let phase: DeliveryPhase
    let errorCategory: String?
    let retryNotBefore: Date?

    var id: String { DestinationDeliveryRecord.jobKey(sessionID: sessionID, destination: destination) }
}
