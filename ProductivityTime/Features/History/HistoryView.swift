import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(model.completedSessions) { session in
            HStack { Text(session.titleSnapshot); Spacer(); Text(session.duration.timeInterval.formatted()) }
        }
        .overlay { if model.completedSessions.isEmpty { ContentUnavailableView("No completed sessions", systemImage: "clock") } }
        .toolbar { Button("Retry") {}.accessibilityIdentifier("history.retry").disabled(true) }
        .accessibilityIdentifier("history.list")
        .padding()
    }
}
