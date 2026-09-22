import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(model.completedSessions) { session in
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.titleSnapshot)
                        .font(.headline)
                    Text("\(SessionPresentation.modeText(session.mode)) · \(SessionPresentation.compactDurationText(for: session.duration))")
                        .foregroundStyle(.secondary)
                    Text(session.completedAt, format: .dateTime.day().month().year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                destinationRow(for: session, destination: .appleNotes, name: "Apple Notes")
                destinationRow(for: session, destination: .notion, name: "Notion")
            }
        }
        .overlay {
            if model.completedSessions.isEmpty {
                ContentUnavailableView(
                    "No Completed Sessions",
                    systemImage: "clock",
                    description: Text("Completed stopwatch and timer sessions will appear here.")
                )
            }
        }
        .accessibilityIdentifier("history.list")
        .padding()
    }

    @ViewBuilder
    private func destinationRow(for session: CompletedSession, destination: DeliveryDestination, name: String) -> some View {
        let record = model.deliveryRecord(for: session.id, destination: destination)
        let presentation = DeliveryStatusPresentation.make(from: record)
        HStack {
            Label("\(name): \(presentation.text)", systemImage: presentation.systemImage)
                .foregroundStyle(statusColor(for: presentation.role))
                .accessibilityLabel("\(name) delivery status: \(presentation.text)")
                .accessibilityIdentifier("history.status.\(destination.rawValue).\(session.id.uuidString)")
            Spacer()
            if presentation.canRetry {
                Button("Retry") { model.retryDelivery(sessionID: session.id, destination: destination) }
                    .accessibilityIdentifier("history.retry.\(destination.rawValue).\(session.id.uuidString)")
                    .accessibilityLabel("Retry \(name) delivery")
            }
        }
        .font(.caption)
    }

    private func statusColor(for role: DeliveryStatusRole) -> Color {
        switch role {
        case .neutral: .secondary
        case .progress: .orange
        case .success: .green
        case .failure: .red
        }
    }
}
