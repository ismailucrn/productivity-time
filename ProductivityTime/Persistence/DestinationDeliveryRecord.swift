import Foundation
import SwiftData

@Model
final class DestinationDeliveryRecord {
    @Attribute(.unique) var jobKey: String
    var sessionID: UUID
    var destinationRawValue: String
    var phaseRawValue: String
    var errorCategory: String?
    var retryNotBefore: Date?

    init(sessionID: UUID, destination: DeliveryDestination, phase: DeliveryPhase = .pending, errorCategory: String? = nil, retryNotBefore: Date? = nil) {
        jobKey = Self.jobKey(sessionID: sessionID, destination: destination)
        self.sessionID = sessionID
        destinationRawValue = destination.rawValue
        phaseRawValue = phase.rawValue
        self.errorCategory = errorCategory
        self.retryNotBefore = retryNotBefore
    }

    var destination: DeliveryDestination {
        DeliveryDestination(rawValue: destinationRawValue) ?? .appleNotes
    }

    var phase: DeliveryPhase {
        DeliveryPhase(rawValue: phaseRawValue) ?? .pending
    }

    var delivery: DestinationDelivery {
        DestinationDelivery(sessionID: sessionID, destination: destination, phase: phase, errorCategory: errorCategory, retryNotBefore: retryNotBefore)
    }

    static func jobKey(sessionID: UUID, destination: DeliveryDestination) -> String {
        "\(sessionID.uuidString.lowercased())|\(destination.rawValue)"
    }
}
