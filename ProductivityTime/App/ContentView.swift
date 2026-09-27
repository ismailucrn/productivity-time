import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingHistory = false
    @FocusState private var historyHasKeyboardFocus: Bool

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
            Button { showingHistory.toggle() } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .accessibilityIdentifier("history.show")
        }
        .overlay {
            if showingHistory {
                GeometryReader { proxy in
                    ZStack {
                        Button { showingHistory = false } label: {
                            Color.black.opacity(0.14)
                                .ignoresSafeArea()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("history.backdrop")
                        .accessibilityHidden(true)

                        HistoryView()
                            .frame(
                                width: min(500, max(280, proxy.size.width - 48)),
                                height: min(historyCardHeight, max(120, proxy.size.height - 48))
                            )
                            .background {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.regularMaterial)
                                    .accessibilityElement()
                                    .accessibilityLabel("History panel")
                                    .accessibilityIdentifier("history.card")
                                    .accessibilityAction(named: Text("Close History")) {
                                        showingHistory = false
                                    }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(radius: 18)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .focusable()
                    .focused($historyHasKeyboardFocus)
                    .onAppear { historyHasKeyboardFocus = true }
                    .onExitCommand { showingHistory = false }
                }
            }
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

    private var historyCardHeight: CGFloat {
        switch model.completedSessions.count {
        case 0: 120
        case 1: 145
        default: min(145 + CGFloat(model.completedSessions.count - 1) * 35, 220)
        }
    }
}
