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
        return try ModelContainer(for: ActivityRecord.self, SessionRecord.self, ActiveSessionRecord.self, DestinationDeliveryRecord.self, configurations: configuration)
    }

    static func makeApplicationContainer() throws -> ModelContainer {
        try ModelContainer(for: ActivityRecord.self, SessionRecord.self, ActiveSessionRecord.self, DestinationDeliveryRecord.self)
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
        DeliveryDestination.allCases.forEach { destination in
            context.insert(DestinationDeliveryRecord(sessionID: session.id, destination: destination))
        }
        try context.save()
    }

    func deliveryRecords(for sessionID: UUID) throws -> [DestinationDelivery] {
        try migrateLegacyDeliveryRecordsIfNeeded()
        let descriptor = FetchDescriptor<DestinationDeliveryRecord>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.jobKey)]
        )
        return try context.fetch(descriptor).map(\.delivery)
    }

    func completedSessions() throws -> [CompletedSession] {
        let descriptor = FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
        try migrateLegacyDeliveryRecordsIfNeeded()
        return try context.fetch(descriptor).map { record in
            try completedSession(for: record)
        }
    }

    func pendingDeliverySessions() throws -> [CompletedSession] {
        try migrateLegacyDeliveryRecordsIfNeeded()
        let descriptor = FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
        return try context.fetch(descriptor).compactMap { record in
            switch try aggregateDeliveryState(for: record.id) {
            case .pending, .failed:
                return try completedSession(for: record)
            case .delivering, .delivered:
                return nil
            }
        }
    }

    func updateDeliveryState(sessionID: UUID, to state: DeliveryState) throws {
        try migrateLegacyDeliveryRecordsIfNeeded()
        let records = try destinationRecords(for: sessionID)
        guard records.count == DeliveryDestination.allCases.count else { throw SessionRepositoryError.destinationDeliveryNotFound }
        guard records.allSatisfy({ isLegalDeliveryTransition(from: $0.phase, to: state) }) else {
            throw SessionRepositoryError.invalidDeliveryStateTransition
        }
        records.forEach { set($0, to: state) }
        try updateLegacyAggregateState(for: sessionID)
        try context.save()
    }

    func pendingDeliveryRecords(for destination: DeliveryDestination, at date: Date) throws -> [DestinationDelivery] {
        try migrateLegacyDeliveryRecordsIfNeeded()
        let rawValue = destination.rawValue
        let descriptor = FetchDescriptor<DestinationDeliveryRecord>(
            predicate: #Predicate { $0.destinationRawValue == rawValue },
            sortBy: [SortDescriptor(\.jobKey)]
        )
        return try context.fetch(descriptor).compactMap { record in
            switch record.phase {
            case .pending:
                return record.delivery
            case .failed where record.retryNotBefore == nil || record.retryNotBefore! <= date:
                return record.delivery
            case .delivering, .delivered, .failed:
                return nil
            }
        }
    }

    func claimDelivery(sessionID: UUID, destination: DeliveryDestination, at date: Date) throws -> DestinationDelivery? {
        try migrateLegacyDeliveryRecordsIfNeeded()
        let record = try fetchDestinationRecord(sessionID: sessionID, destination: destination)
        switch record.phase {
        case .pending:
            break
        case .failed where record.retryNotBefore == nil || record.retryNotBefore! <= date:
            break
        case .delivering, .delivered, .failed:
            return nil
        }
        record.phaseRawValue = DeliveryPhase.delivering.rawValue
        record.errorCategory = nil
        record.retryNotBefore = nil
        try updateLegacyAggregateState(for: sessionID)
        try context.save()
        return record.delivery
    }

    func markDeliverySucceeded(sessionID: UUID, destination: DeliveryDestination) throws {
        try migrateLegacyDeliveryRecordsIfNeeded()
        let record = try fetchDestinationRecord(sessionID: sessionID, destination: destination)
        guard record.phase == .delivering else { throw SessionRepositoryError.invalidDeliveryStateTransition }
        record.phaseRawValue = DeliveryPhase.delivered.rawValue
        record.errorCategory = nil
        record.retryNotBefore = nil
        try updateLegacyAggregateState(for: sessionID)
        try context.save()
    }

    func markDeliveryFailed(sessionID: UUID, destination: DeliveryDestination, errorCategory: String, retryNotBefore: Date?) throws {
        try migrateLegacyDeliveryRecordsIfNeeded()
        let record = try fetchDestinationRecord(sessionID: sessionID, destination: destination)
        guard record.phase == .delivering else { throw SessionRepositoryError.invalidDeliveryStateTransition }
        record.phaseRawValue = DeliveryPhase.failed.rawValue
        record.errorCategory = sanitizedErrorCategory(errorCategory)
        record.retryNotBefore = retryNotBefore
        try updateLegacyAggregateState(for: sessionID)
        try context.save()
    }

    func retryDelivery(sessionID: UUID, destination: DeliveryDestination) throws {
        try migrateLegacyDeliveryRecordsIfNeeded()
        let record = try fetchDestinationRecord(sessionID: sessionID, destination: destination)
        guard record.phase == .failed else { throw SessionRepositoryError.invalidDeliveryStateTransition }
        record.phaseRawValue = DeliveryPhase.pending.rawValue
        record.errorCategory = nil
        record.retryNotBefore = nil
        try updateLegacyAggregateState(for: sessionID)
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
        try migrateLegacyDeliveryRecordsIfNeeded()
        let descriptor = FetchDescriptor<DestinationDeliveryRecord>(predicate: #Predicate { $0.phaseRawValue == "delivering" })
        let interruptedRecords = try context.fetch(descriptor)
        guard !interruptedRecords.isEmpty else {
            return
        }
        let sessionIDs = Set(interruptedRecords.map(\.sessionID))
        interruptedRecords.forEach {
            $0.phaseRawValue = DeliveryPhase.pending.rawValue
            $0.errorCategory = nil
            $0.retryNotBefore = nil
        }
        try sessionIDs.forEach(updateLegacyAggregateState(for:))
        try context.save()
    }

    private func isLegalDeliveryTransition(from current: DeliveryPhase, to next: DeliveryState) -> Bool {
        switch (current, next) {
        case (.pending, .delivering), (.failed, .delivering), (.delivering, .delivered), (.delivering, .failed):
            true
        default:
            false
        }
    }

    private func destinationRecords(for sessionID: UUID) throws -> [DestinationDeliveryRecord] {
        let descriptor = FetchDescriptor<DestinationDeliveryRecord>(predicate: #Predicate { $0.sessionID == sessionID })
        return try context.fetch(descriptor)
    }

    private func fetchDestinationRecord(sessionID: UUID, destination: DeliveryDestination) throws -> DestinationDeliveryRecord {
        let jobKey = DestinationDeliveryRecord.jobKey(sessionID: sessionID, destination: destination)
        var descriptor = FetchDescriptor<DestinationDeliveryRecord>(predicate: #Predicate { $0.jobKey == jobKey })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { throw SessionRepositoryError.destinationDeliveryNotFound }
        return record
    }

    private func completedSession(for record: SessionRecord) throws -> CompletedSession {
        record.session(deliveryState: try aggregateDeliveryState(for: record.id))
    }

    private func aggregateDeliveryState(for sessionID: UUID) throws -> DeliveryState {
        let records = try destinationRecords(for: sessionID)
        guard records.count == DeliveryDestination.allCases.count else { return .pending }
        if records.allSatisfy({ $0.phase == .delivered }) { return .delivered }
        if records.contains(where: { $0.phase == .delivering }) { return .delivering }
        if let failed = records.first(where: { $0.phase == .failed }) { return .failed(errorCategory: failed.errorCategory ?? "unknown") }
        return .pending
    }

    private func updateLegacyAggregateState(for sessionID: UUID) throws {
        var descriptor = FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.id == sessionID })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { throw SessionRepositoryError.sessionNotFound }
        record.setDeliveryState(try aggregateDeliveryState(for: sessionID))
    }

    private func set(_ record: DestinationDeliveryRecord, to state: DeliveryState) {
        switch state {
        case .pending:
            record.phaseRawValue = DeliveryPhase.pending.rawValue
            record.errorCategory = nil
            record.retryNotBefore = nil
        case .delivering:
            record.phaseRawValue = DeliveryPhase.delivering.rawValue
            record.errorCategory = nil
            record.retryNotBefore = nil
        case .delivered:
            record.phaseRawValue = DeliveryPhase.delivered.rawValue
            record.errorCategory = nil
            record.retryNotBefore = nil
        case let .failed(errorCategory):
            record.phaseRawValue = DeliveryPhase.failed.rawValue
            record.errorCategory = sanitizedErrorCategory(errorCategory)
            record.retryNotBefore = nil
        }
    }

    private func migrateLegacyDeliveryRecordsIfNeeded() throws {
        let sessions = try context.fetch(FetchDescriptor<SessionRecord>())
        var didCreateRecords = false
        for session in sessions {
            let existingDestinations = Set(try destinationRecords(for: session.id).map(\.destination))
            for destination in DeliveryDestination.allCases where !existingDestinations.contains(destination) {
                // The legacy aggregate represented the original Apple Notes outbox.
                // A migration preserves it there and starts Notion pending, avoiding
                // any false claim that a legacy session reached both destinations.
                let legacyState: DeliveryState = destination == .appleNotes ? session.deliveryState : .pending
                let record = DestinationDeliveryRecord(sessionID: session.id, destination: destination)
                set(record, to: legacyState)
                context.insert(record)
                didCreateRecords = true
            }
        }
        if didCreateRecords { try context.save() }
    }

    private func sanitizedErrorCategory(_ rawValue: String) -> String {
        switch rawValue {
        case "authorization", "configuration", "network", "notesUnavailable", "notionUnavailable", "permissionDenied", "schema", "unknown":
            rawValue
        default:
            "unknown"
        }
    }
}
