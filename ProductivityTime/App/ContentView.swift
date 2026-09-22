import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingHistory = false

    var body: some View {
        NavigationSplitView {
            ActivityListView()
                .navigationTitle("Activities")
        } detail: {
            TimerPanelView()
                .navigationTitle(model.activeSession?.title ?? "Productivity Time")
        }
        .frame(minWidth: 720, minHeight: 460)
        .toolbar {
            Button { showingHistory = true } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .accessibilityIdentifier("history.show")
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView()
        }
        .alert("Resume previous session?", isPresented: Binding(get: { model.restorableSession != nil }, set: { _ in })) {
            Button("Resume") { perform { try model.resumeRestoredSession() } }.accessibilityIdentifier("restore.resume")
            Button("Discard", role: .destructive) { perform { try model.discardRestoredSession() } }.accessibilityIdentifier("restore.discard")
        } message: {
            Text("The saved session was paused when the app quit.")
        }
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            model.record(error)
        }
    }
}
