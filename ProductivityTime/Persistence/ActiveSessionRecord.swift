import Foundation
import SwiftData

@Model
final class ActiveSessionRecord {
    @Attribute(.unique) var singletonKey: String
    var id: UUID
    var activityID: UUID
    var titleSnapshot: String
    var modeRawValue: String
    var configuredDurationSeconds: TimeInterval?
    var durationSeconds: TimeInterval
    var stateRawValue: String

    init(snapshot: ActiveSessionSnapshot) {
        singletonKey = "active-session"
        id = snapshot.id
        activityID = snapshot.activityID
        titleSnapshot = snapshot.titleSnapshot
        modeRawValue = snapshot.mode.rawValue
        configuredDurationSeconds = snapshot.configuredDuration?.timeInterval
        durationSeconds = snapshot.duration.timeInterval
        stateRawValue = switch snapshot.state {
        case .idle: "idle"
        case .running: "running"
        case .paused: "paused"
        }
    }

    var snapshot: ActiveSessionSnapshot {
        let state: TimerState = switch stateRawValue {
        case "running": .running
        case "paused": .paused
        default: .idle
        }
        return ActiveSessionSnapshot(
            id: id,
            activityID: activityID,
            titleSnapshot: titleSnapshot,
            mode: SessionMode(rawValue: modeRawValue) ?? .stopwatch,
            configuredDuration: configuredDurationSeconds.map(Duration.seconds),
            duration: .seconds(durationSeconds),
            state: state
        )
    }
}
