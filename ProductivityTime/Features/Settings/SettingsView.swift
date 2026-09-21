import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            TextField("Apple Notes target", text: .constant("Productivity Time Sessions"))
                .disabled(true)
            Text("Apple Notes delivery will be configured in the next milestone.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 380)
        .accessibilityIdentifier("settings.view")
    }
}
