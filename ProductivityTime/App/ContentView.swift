import AppKit
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
        .sheet(isPresented: $showingHistory) {
            HistoryView()
                .dismissOnOutsideClick(isPresented: $showingHistory)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .dismissOnOutsideClick(isPresented: $showingSettings)
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

private extension View {
    func dismissOnOutsideClick(isPresented: Binding<Bool>) -> some View {
        modifier(SheetOutsideClickDismissModifier(isPresented: isPresented))
    }
}

private struct SheetOutsideClickDismissModifier: ViewModifier {
    @Binding var isPresented: Bool
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .background(
                WindowAccessor { sheetWindow in
                    setupMonitor(for: sheetWindow)
                }
            )
            .onExitCommand {
                isPresented = false
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
            }
    }

    private func setupMonitor(for sheetWindow: NSWindow) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak sheetWindow] event in
            guard let sheetWindow else { return event }
            if event.window === sheetWindow {
                return event
            }
            DispatchQueue.main.async {
                isPresented = false
            }
            return nil
        }
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onResolve(window)
            }
        }
    }
}
