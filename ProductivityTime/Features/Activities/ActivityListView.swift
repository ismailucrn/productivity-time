import SwiftUI

struct ActivityListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var name = ""
    @State private var activityPendingRename: Activity?
    @State private var renamedActivityName = ""
    @State private var activityPendingDeletion: Activity?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activities")
                .font(.headline)

            List(selection: Binding(get: { model.selectedActivityID }, set: model.selectActivity)) {
                ForEach(model.activities) { activity in
                    Label {
                        HStack {
                            Text(activity.name.value)
                            Spacer()
                            if model.activeSession?.activityID == activity.id {
                                Text("Running")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: model.activeSession?.activityID == activity.id ? "timer" : "circle")
                    }
                    .tag(activity.id)
                    .contextMenu {
                        Button("Rename") { beginRename(activity) }
                        Button("Delete", role: .destructive) {
                            activityPendingDeletion = activity
                        }
                        .disabled(model.activeSession?.activityID == activity.id)
                    }
                }
            }

            if model.activities.isEmpty {
                Text("Add your first activity below.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                TextField("New activity", text: $name)
                    .accessibilityIdentifier("activity.name")
                Button("Add") { addActivity() }
                    .accessibilityIdentifier("activity.add")
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding()
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        .alert("Rename Activity", isPresented: Binding(get: { activityPendingRename != nil }, set: { isPresented in
            if !isPresented { activityPendingRename = nil }
        })) {
            TextField("Activity name", text: $renamedActivityName)
                .accessibilityIdentifier("activity.rename.name")
            Button("Rename") { renameActivity() }
                .accessibilityIdentifier("activity.rename.confirm")
            Button("Cancel", role: .cancel) { activityPendingRename = nil }
        } message: {
            Text("Choose a new name for \(activityPendingRename?.name.value ?? "this activity").")
        }
        .alert("Delete Activity?", isPresented: Binding(get: { activityPendingDeletion != nil }, set: { isPresented in
            if !isPresented { activityPendingDeletion = nil }
        })) {
            Button("Delete", role: .destructive) { deleteActivity() }
                .accessibilityIdentifier("activity.delete.confirm")
            Button("Cancel", role: .cancel) { activityPendingDeletion = nil }
        } message: {
            Text("Delete \(activityPendingDeletion?.name.value ?? "this activity")? This cannot be undone.")
        }
    }

    private func addActivity() {
        guard !name.isEmpty else { return }
        do {
            let activity = try model.createActivity(named: name)
            model.selectActivity(activity.id)
            name = ""
        } catch {
            model.record(error)
        }
    }

    private func beginRename(_ activity: Activity) {
        activityPendingRename = activity
        renamedActivityName = activity.name.value
    }

    private func renameActivity() {
        guard let activity = activityPendingRename else { return }
        do {
            try model.renameActivity(activity.id, to: renamedActivityName)
            activityPendingRename = nil
        } catch {
            model.record(error)
        }
    }

    private func deleteActivity() {
        guard let activity = activityPendingDeletion else { return }
        do {
            try model.deleteActivity(activity.id)
            activityPendingDeletion = nil
        } catch {
            model.record(error)
        }
    }
}
