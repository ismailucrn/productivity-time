import Foundation

enum DeliveryResult: Equatable, Sendable { case created, alreadyExists }

enum DeliveryAttemptOutcome: Equatable, Sendable { case delivered, skipped, failed(String) }
struct DeliveryAttemptResult: Equatable, Sendable { let sessionID: UUID?; let destination: DeliveryDestination; let outcome: DeliveryAttemptOutcome }

enum DeliveryAttemptFailureCategory: String, Sendable {
    case pendingFetch
    case retry
    case claim
    case sessionLoad
    case markSuccess
    case markFailure
    case unknown
}

enum DeliveryError: Error, Equatable, Sendable {
    case authorization, configuration, schema, permissionDenied, notesUnavailable, notionUnavailable, network
    case rateLimited(retryNotBefore: Date?)
    case unknown

    var category: String {
        switch self {
        case .authorization: "authorization"
        case .configuration: "configuration"
        case .schema: "schema"
        case .permissionDenied: "permissionDenied"
        case .notesUnavailable: "notesUnavailable"
        case .notionUnavailable: "notionUnavailable"
        case .network, .rateLimited: "network"
        case .unknown: "unknown"
        }
    }

    var retryNotBefore: Date? {
        if case let .rateLimited(value) = self { value } else { nil }
    }
}
