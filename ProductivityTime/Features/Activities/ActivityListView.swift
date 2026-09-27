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
                    ActivitySwipeRow(
                        activity: activity,
                        isActive: model.activeSession?.activityID == activity.id,
                        setPinned: { setPinned(activity, isPinned: !activity.isPinned) },
                        delete: { activityPendingDeletion = activity }
                    )
                    .tag(activity.id)
                    .contextMenu {
                        Button(activity.isPinned ? "Unpin" : "Pin") {
                            setPinned(activity, isPinned: !activity.isPinned)
                        }
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

    private func setPinned(_ activity: Activity, isPinned: Bool) {
        do {
            try model.setActivityPinned(activity.id, isPinned: isPinned)
        } catch {
            model.record(error)
        }
    }
}

/// A visible macOS equivalent of swipe actions. Native `swipeActions` does not
/// consistently reveal for a mouse or trackpad inside a sidebar list, so this
/// row moves with the drag and exposes the available action beneath it.
private struct ActivitySwipeRow: View {
    private enum RevealedAction: Equatable {
        case pin
        case delete
    }

    let activity: Activity
    let isActive: Bool
    let setPinned: () -> Void
    let delete: () -> Void

    @State private var revealedAction: RevealedAction?
    @State private var dragOffset: CGFloat = 0

    private let actionWidth: CGFloat = 88
    private let revealThreshold: CGFloat = 28

    var body: some View {
        ZStack {
            revealedActions

            Label {
                HStack(spacing: 6) {
                    Text(activity.name.value)
                    Spacer(minLength: 4)
                    if isActive {
                        Text("Running")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if activity.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Pinned")
                    }
                }
            } icon: {
                Image(systemName: isActive ? "timer" : "circle")
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(x: displayedOffset)
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture)
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var revealedActions: some View {
        HStack(spacing: 0) {
            if revealedAction == .pin || displayedOffset > 0 {
                actionButton(
                    title: activity.isPinned ? "Unpin" : "Pin",
                    color: .accentColor,
                    accessibilityIdentifier: "activity.pin.\(activity.id.uuidString)",
                    action: {
                        closeActions()
                        setPinned()
                    }
                )
            }

            Spacer(minLength: 0)

            if revealedAction == .delete || displayedOffset < 0 {
                actionButton(
                    title: "Delete",
                    color: .red,
                    disabled: isActive,
                    accessibilityIdentifier: "activity.delete.\(activity.id.uuidString)",
                    action: {
                        closeActions()
                        delete()
                    }
                )
            }
        }
    }

    private func actionButton(
        title: String,
        color: Color,
        disabled: Bool = false,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderless)
            .frame(width: actionWidth)
            .frame(maxHeight: .infinity)
            .foregroundStyle(.white)
            .background(color)
            .accessibilityIdentifier(accessibilityIdentifier)
            .disabled(disabled)
            .opacity(disabled ? 0.45 : 1)
    }

    private var displayedOffset: CGFloat {
        if dragOffset != 0 {
            return dragOffset
        }
        switch revealedAction {
        case .pin: return actionWidth
        case .delete: return -actionWidth
        case nil: return 0
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let translation = value.translation.width
                guard abs(translation) > abs(value.translation.height) else { return }
                dragOffset = min(max(translation, -actionWidth), actionWidth)
            }
            .onEnded { value in
                let translation = value.translation.width
                guard abs(translation) > abs(value.translation.height) else {
                    closeActions()
                    return
                }
                withAnimation(.snappy) {
                    if translation >= revealThreshold {
                        revealedAction = .pin
                    } else if translation <= -revealThreshold {
                        revealedAction = .delete
                    } else {
                        revealedAction = nil
                    }
                    dragOffset = 0
                }
            }
    }

    private func closeActions() {
        withAnimation(.snappy) {
            revealedAction = nil
            dragOffset = 0
        }
    }
}
