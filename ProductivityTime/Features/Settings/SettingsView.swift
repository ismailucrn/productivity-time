import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var notesTargetName = ""
    @State private var notionDataSourceID = ""
    @State private var notionToken = ""

    var body: some View {
        Form {
            Section("Apple Notes") {
                TextField("Target note", text: $notesTargetName)
                    .accessibilityIdentifier("settings.notes.target")
                    .onSubmit { model.updateNotesTarget(notesTargetName); notesTargetName = model.notesTargetName }
                HStack {
                    Button("Save") {
                        model.updateNotesTarget(notesTargetName)
                        notesTargetName = model.notesTargetName
                    }
                    Button("Test Connection") { _ = model.testNotesConnection() }
                        .disabled(model.notesConnectionTestState == .testing)
                        .accessibilityIdentifier("settings.notes.test")
                    connectionStatus(model.notesConnectionTestState)
                        .accessibilityIdentifier("settings.notes.status")
                }
            }
            Section("Notion") {
                TextField("Data source ID", text: $notionDataSourceID)
                    .accessibilityIdentifier("settings.notion.dataSource")
                    .onSubmit { model.updateNotionDataSourceID(notionDataSourceID); notionDataSourceID = model.notionDataSourceID }
                SecureField("Notion token", text: $notionToken)
                    .accessibilityIdentifier("settings.notion.token")
                HStack {
                    Button("Save") { saveNotionSettings() }
                    Button("Remove Token") { removeNotionToken() }
                        .disabled(!model.isNotionTokenConfigured)
                    Button("Test Connection") { _ = model.testNotionConnection() }
                        .disabled(model.notionConnectionTestState == .testing)
                        .accessibilityIdentifier("settings.notion.test")
                    connectionStatus(model.notionConnectionTestState)
                        .accessibilityIdentifier("settings.notion.status")
                }
                Text(model.isNotionTokenConfigured ? "Token configured" : "Token not configured")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.notion.configuration")
            }
            Section("Notifications") {
                notificationStatus(model.notificationAuthorizationState)
                    .accessibilityIdentifier("settings.notifications.status")
                if model.notificationAuthorizationState == .denied {
                    Text("Enable notifications in System Settings to receive timer completion alerts.")
                        .foregroundStyle(.secondary)
                }
            }
            if let error = model.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings.error")
            }
        }
        .padding()
        .frame(width: 440)
        .accessibilityIdentifier("settings.view")
        .onAppear {
            notesTargetName = model.notesTargetName
            notionDataSourceID = model.notionDataSourceID
            notionToken = ""
        }
        .task { await model.refreshNotificationAuthorizationState().value }
    }

    private func saveNotionSettings() {
        model.updateNotionDataSourceID(notionDataSourceID)
        do {
            if !notionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try model.updateNotionToken(notionToken)
            }
            notionToken = ""
        } catch {
            // The model exposes only sanitized, actionable error state.
        }
    }

    private func removeNotionToken() {
        do {
            try model.removeNotionToken()
            notionToken = ""
        } catch {
            // The model exposes only sanitized, actionable error state.
        }
    }

    @ViewBuilder
    private func connectionStatus(_ state: ConnectionTestState) -> some View {
        switch state {
        case .idle:
            Label("Not tested", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .testing:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("Testing connection")
            }
        case .succeeded:
            Label("Connected", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .failed:
            Label("Connection failed", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func notificationStatus(_ state: NotificationAuthorizationState) -> some View {
        switch state {
        case .notDetermined:
            Label("Not requested", systemImage: "bell")
                .foregroundStyle(.secondary)
        case .authorized:
            Label("Allowed", systemImage: "bell.badge")
                .foregroundStyle(.green)
        case .denied:
            Label("Denied", systemImage: "bell.slash")
                .foregroundStyle(.red)
        }
    }
}
