import Foundation

enum DeliveryResult: Equatable, Sendable { case created, alreadyExists }

enum DeliveryError: Error, Equatable, Sendable {
    case authorization, configuration, schema, permissionDenied, unavailable, network
    case rateLimited(retryNotBefore: Date?)
    case unknown

    var category: String {
        switch self {
        case .authorization: "authorization"
        case .configuration: "configuration"
        case .schema: "schema"
        case .permissionDenied: "permissionDenied"
        case .unavailable: "notionUnavailable"
        case .network, .rateLimited: "network"
        case .unknown: "unknown"
        }
    }

    var retryNotBefore: Date? {
        if case let .rateLimited(value) = self { value } else { nil }
    }
}
