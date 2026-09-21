import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var notesTargetName = ""
    @State private var notionDataSourceID = ""
    @State private var notionToken = ""

    var body: some View {
        Form {
            Section("Apple Notes") {
                TextField("Apple Notes target", text: $notesTargetName)
                    .accessibilityIdentifier("settings.notes.target")
                    .onSubmit { model.updateNotesTarget(notesTargetName); notesTargetName = model.notesTargetName }
                Button("Save Apple Notes Target") {
                    model.updateNotesTarget(notesTargetName)
                    notesTargetName = model.notesTargetName
                }
                Button("Test Apple Notes Connection") { model.testNotesConnection() }
                    .accessibilityIdentifier("settings.notes.test")
            }
            Section("Notion") {
                TextField("Notion data source ID", text: $notionDataSourceID)
                    .accessibilityIdentifier("settings.notion.dataSource")
                    .onSubmit { model.updateNotionDataSourceID(notionDataSourceID); notionDataSourceID = model.notionDataSourceID }
                SecureField("Notion token", text: $notionToken)
                    .accessibilityIdentifier("settings.notion.token")
                HStack {
                    Button("Save Notion Settings") { saveNotionSettings() }
                    Button("Remove Notion Token") { removeNotionToken() }
                        .disabled(!model.isNotionTokenConfigured)
                }
                Text(model.isNotionTokenConfigured ? "Notion token configured" : "Notion token not configured")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.notion.configuration")
                Button("Test Notion Connection") { model.testNotionConnection() }
                    .accessibilityIdentifier("settings.notion.test")
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
    }

    private func saveNotionSettings() {
        model.updateNotionDataSourceID(notionDataSourceID)
        do {
            try model.updateNotionToken(notionToken)
            notionToken = ""
        } catch {
            // The model exposes only sanitized, actionable error state.
        }
    }

    private func removeNotionToken() {
        do {
            try model.updateNotionToken("")
            notionToken = ""
        } catch {
            // The model exposes only sanitized, actionable error state.
        }
    }
}
