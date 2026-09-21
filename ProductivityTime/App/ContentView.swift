import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingHistory = false
    @State private var showingSettings = false

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
            Button("History") { showingHistory = true }.accessibilityIdentifier("history.show")
            Button("Settings") { showingSettings = true }.accessibilityIdentifier("settings.show")
        }
        .sheet(isPresented: $showingHistory) { HistoryView() }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .alert("Resume previous session?", isPresented: Binding(get: { model.restorableSession != nil }, set: { _ in })) {
            Button("Resume") { try? model.resumeRestoredSession() }.accessibilityIdentifier("restore.resume")
            Button("Discard", role: .destructive) { try? model.discardRestoredSession() }.accessibilityIdentifier("restore.discard")
        } message: {
            Text("The saved session was paused when the app quit.")
        }
    }
}
