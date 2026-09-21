import Foundation
import SwiftData

@Model
final class SessionRecord {
    @Attribute(.unique) var id: UUID
    var activityID: UUID
    var titleSnapshot: String
    var modeRawValue: String
    var durationSeconds: TimeInterval
    var completedAt: Date
    var deliveryStateRawValue: String
    var deliveryErrorCategory: String?

    init(session: CompletedSession) {
        id = session.id
        activityID = session.activityID
        titleSnapshot = session.titleSnapshot
        modeRawValue = session.mode.rawValue
        durationSeconds = session.duration.timeInterval
        completedAt = session.completedAt
        deliveryStateRawValue = "pending"
        deliveryErrorCategory = nil
    }

    func session(deliveryState: DeliveryState? = nil) -> CompletedSession {
        CompletedSession(
            id: id,
            activityID: activityID,
            titleSnapshot: titleSnapshot,
            mode: SessionMode(rawValue: modeRawValue) ?? .stopwatch,
            duration: .seconds(durationSeconds),
            completedAt: completedAt,
            deliveryState: deliveryState ?? self.deliveryState
        )
    }

    var deliveryState: DeliveryState {
        switch deliveryStateRawValue {
        case "delivering": .delivering
        case "delivered": .delivered
        case "failed": .failed(errorCategory: deliveryErrorCategory ?? "unknown")
        default: .pending
        }
    }

    func setDeliveryState(_ state: DeliveryState) {
        switch state {
        case .pending:
            deliveryStateRawValue = "pending"
            deliveryErrorCategory = nil
        case .delivering:
            deliveryStateRawValue = "delivering"
            deliveryErrorCategory = nil
        case .delivered:
            deliveryStateRawValue = "delivered"
            deliveryErrorCategory = nil
        case let .failed(errorCategory):
            deliveryStateRawValue = "failed"
            deliveryErrorCategory = errorCategory
        }
    }
}
