import Foundation
import SwiftData

@MainActor
final class SwiftDataStore: SessionRepository {
    private let context: ModelContext

    init(container: ModelContainer) throws {
        context = ModelContext(container)
    }

    static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ActivityRecord.self, SessionRecord.self, ActiveSessionRecord.self, configurations: configuration)
    }

    static func makeApplicationContainer() throws -> ModelContainer {
        try ModelContainer(for: ActivityRecord.self, SessionRecord.self, ActiveSessionRecord.self)
    }

    func createActivity(named name: ActivityName, createdAt: Date) throws -> Activity {
        let normalizedName = ActivityName.stableCaseInsensitiveKey(name.value)
        var descriptor = FetchDescriptor<ActivityRecord>(predicate: #Predicate { $0.normalizedName == normalizedName })
        descriptor.fetchLimit = 1

        guard try context.fetch(descriptor).isEmpty else {
            throw SessionRepositoryError.activityNameConflict
        }

        let record = ActivityRecord(id: UUID(), name: name.value, createdAt: createdAt)
        context.insert(record)
        try context.save()
        return record.activity
    }

    func renameActivity(_ id: UUID, to name: ActivityName) throws -> Activity {
        let record = try fetchActivity(id)
        let normalizedName = ActivityName.stableCaseInsensitiveKey(name.value)
        var duplicateDescriptor = FetchDescriptor<ActivityRecord>(predicate: #Predicate { $0.normalizedName == normalizedName })
        duplicateDescriptor.fetchLimit = 1
        if let duplicate = try context.fetch(duplicateDescriptor).first, duplicate.id != id {
            throw SessionRepositoryError.activityNameConflict
        }
        record.name = name.value
        record.normalizedName = normalizedName
        try context.save()
        return record.activity
    }

    func deleteActivity(_ id: UUID) throws {
        _ = try fetchActivity(id)
        let activeDescriptor = FetchDescriptor<ActiveSessionRecord>(predicate: #Predicate { $0.activityID == id })
        guard try context.fetch(activeDescriptor).isEmpty else {
            throw SessionRepositoryError.activityHasActiveSession
        }
        let record = try fetchActivity(id)
        context.delete(record)
        try context.save()
    }

    func activities() throws -> [Activity] {
        let descriptor = FetchDescriptor<ActivityRecord>(sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.id)])
        return try context.fetch(descriptor).map(\.activity)
    }

    func saveCompleted(_ session: CompletedSession) throws {
        let sessionID = session.id
        var descriptor = FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.id == sessionID })
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else {
            throw SessionRepositoryError.sessionIDConflict
        }
        context.insert(SessionRecord(session: session))
        try context.save()
    }

    func completedSessions() throws -> [CompletedSession] {
        let descriptor = FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
        return try context.fetch(descriptor).map(\.session)
    }

    func pendingDeliverySessions() throws -> [CompletedSession] {
        let descriptor = FetchDescriptor<SessionRecord>(predicate: #Predicate {
            $0.deliveryStateRawValue == "pending" || $0.deliveryStateRawValue == "failed"
        }, sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
        return try context.fetch(descriptor).map(\.session)
    }

    func updateDeliveryState(sessionID: UUID, to state: DeliveryState) throws {
        var descriptor = FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.id == sessionID })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            throw SessionRepositoryError.sessionNotFound
        }
        guard isLegalDeliveryTransition(from: record.deliveryState, to: state) else {
            throw SessionRepositoryError.invalidDeliveryStateTransition
        }
        record.setDeliveryState(state)
        try context.save()
    }

    func saveActive(_ snapshot: ActiveSessionSnapshot?) throws {
        let records = try context.fetch(FetchDescriptor<ActiveSessionRecord>())
        records.forEach(context.delete)
        if let snapshot {
            context.insert(ActiveSessionRecord(snapshot: snapshot))
        }
        try context.save()
    }

    func loadActive() throws -> ActiveSessionSnapshot? {
        try context.fetch(FetchDescriptor<ActiveSessionRecord>()).first?.snapshot
    }

    private func fetchActivity(_ id: UUID) throws -> ActivityRecord {
        var descriptor = FetchDescriptor<ActivityRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            throw SessionRepositoryError.activityNotFound
        }
        return record
    }

    func recoverInterruptedDeliveries() throws {
        let descriptor = FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.deliveryStateRawValue == "delivering" })
        let interruptedRecords = try context.fetch(descriptor)
        guard !interruptedRecords.isEmpty else {
            return
        }
        interruptedRecords.forEach { $0.setDeliveryState(.pending) }
        try context.save()
    }

    private func isLegalDeliveryTransition(from current: DeliveryState, to next: DeliveryState) -> Bool {
        switch (current, next) {
        case (.pending, .delivering), (.failed, .delivering), (.delivering, .delivered), (.delivering, .failed):
            true
        default:
            false
        }
    }
}
