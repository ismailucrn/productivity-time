import SwiftUI

struct ActivityListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading) {
            List(selection: Binding(get: { model.selectedActivityID }, set: model.selectActivity)) {
                ForEach(model.activities) { activity in
                    Text(activity.name.value).tag(activity.id)
                }
            }
            HStack {
                TextField("New activity", text: $name)
                    .accessibilityIdentifier("activity.name")
                Button("Add") { addActivity() }
                    .accessibilityIdentifier("activity.add")
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .accessibilityIdentifier("activity.list")
        .padding()
    }

    private func addActivity() {
        guard !name.isEmpty else { return }
        if let activity = try? model.createActivity(named: name) {
            model.selectActivity(activity.id)
            name = ""
        }
    }
}
