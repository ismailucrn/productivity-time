import Foundation

struct Activity: Equatable, Sendable, Identifiable {
    let id: UUID
    let name: ActivityName
    let createdAt: Date
    let isPinned: Bool

    init(id: UUID, name: ActivityName, createdAt: Date, isPinned: Bool = false) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.isPinned = isPinned
    }
}

enum SessionMode: String, Equatable, Sendable {
    case stopwatch
    case timer
}

enum DeliveryState: Equatable, Sendable {
    case pending
    case delivering
    case delivered
    case failed(errorCategory: String)
}

struct CompletedSession: Equatable, Sendable, Identifiable {
    let id: UUID
    let activityID: UUID
    let titleSnapshot: String
    let mode: SessionMode
    let duration: Duration
    let completedAt: Date
    let deliveryState: DeliveryState
}

struct ActiveSessionSnapshot: Equatable, Sendable, Identifiable {
    let id: UUID
    let activityID: UUID
    let titleSnapshot: String
    let mode: SessionMode
    let configuredDuration: Duration?
    let duration: Duration
    let state: TimerState
}
