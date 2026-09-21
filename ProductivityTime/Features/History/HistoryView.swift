import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(model.completedSessions) { session in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(session.titleSnapshot)
                    Spacer()
                    Text(session.duration.timeInterval.formatted())
                        .foregroundStyle(.secondary)
                }
                destinationRow(for: session, destination: .appleNotes, name: "Apple Notes")
                destinationRow(for: session, destination: .notion, name: "Notion")
            }
        }
        .overlay { if model.completedSessions.isEmpty { ContentUnavailableView("No completed sessions", systemImage: "clock") } }
        .accessibilityIdentifier("history.list")
        .padding()
    }

    @ViewBuilder
    private func destinationRow(for session: CompletedSession, destination: DeliveryDestination, name: String) -> some View {
        let record = model.deliveryRecord(for: session.id, destination: destination)
        HStack {
            Text("\(name): \(statusText(record))")
                .accessibilityLabel("\(name) delivery status: \(statusText(record))")
            Spacer()
            if record?.phase == .failed {
                Button("Retry \(name)") { model.retryDelivery(sessionID: session.id, destination: destination) }
                    .accessibilityIdentifier("history.retry.\(destination.rawValue).\(session.id.uuidString)")
                    .accessibilityLabel("Retry \(name) delivery. Previous delivery failed; this retries only \(name).")
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
        .font(.caption)
        .foregroundStyle(record?.phase == .failed ? .red : .secondary)
    }

    private func statusText(_ record: DestinationDelivery?) -> String {
        switch record?.phase {
        case .pending: "Pending"
        case .delivering: "Delivering"
        case .delivered: "Delivered"
        case .failed: "Failed"
        case nil: "Pending"
        }
    }
}
