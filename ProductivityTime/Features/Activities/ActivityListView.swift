import AppKit
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

            ActivityTableView(
                activities: model.activities,
                activeActivityID: model.activeSession?.activityID,
                selectedActivityID: model.selectedActivityID,
                onSelect: model.selectActivity,
                onSetPinned: setPinned,
                onRename: beginRename,
                onDelete: { activityPendingDeletion = $0 }
            )

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

private struct ActivityTableView: NSViewRepresentable {
    let activities: [Activity]
    let activeActivityID: UUID?
    let selectedActivityID: UUID?
    let onSelect: (UUID?) -> Void
    let onSetPinned: (Activity, Bool) -> Void
    let onRename: (Activity) -> Void
    let onDelete: (Activity) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        table.addTableColumn(NSTableColumn(identifier: .init("activity")))
        table.headerView = nil
        table.style = .sourceList
        table.selectionHighlightStyle = .regular
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.rowHeight = 30
        table.intercellSpacing = .zero
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.backgroundColor = .clear
        table.focusRingType = .none
        table.autoresizingMask = [.width]
        table.setAccessibilityIdentifier("activity.table")
        table.dataSource = context.coordinator
        table.delegate = context.coordinator

        let menu = NSMenu()
        menu.delegate = context.coordinator
        table.menu = menu

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = table
        context.coordinator.tableView = table
        context.coordinator.update(with: self)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(with: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        weak var tableView: NSTableView?
        private var configuration: ActivityTableView?
        private var isApplyingUpdate = false
        private var contextActivityID: UUID?

        func update(with configuration: ActivityTableView) {
            self.configuration = configuration
            guard let tableView else { return }
            isApplyingUpdate = true
            tableView.reloadData()
            resizeDocumentView(tableView, for: configuration.activities.count)
            if let selectedActivityID = configuration.selectedActivityID,
               let row = configuration.activities.firstIndex(where: { $0.id == selectedActivityID }) {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            } else {
                tableView.deselectAll(nil)
            }
            isApplyingUpdate = false
        }

        func numberOfRows(in tableView: NSTableView) -> Int { configuration?.activities.count ?? 0 }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let activity = activity(at: row) else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("activity.cell")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? ActivityTableCellView)
                ?? ActivityTableCellView(frame: .zero)
            cell.configure(activity: activity, isActive: activity.id == configuration?.activeActivityID)
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingUpdate, let tableView else { return }
            configuration?.onSelect(activity(at: tableView.selectedRow)?.id)
        }

        func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
            guard let activity = activity(at: row) else { return [] }
            switch edge {
            case .leading:
                let action = NSTableViewRowAction(style: .regular, title: activity.isPinned ? "Unpin" : "Pin") { [weak self] _, actionRow in
                    guard let activity = self?.activity(at: actionRow) else { return }
                    self?.configuration?.onSetPinned(activity, !activity.isPinned)
                }
                action.image = NSImage(
                    systemSymbolName: activity.isPinned ? "pin.slash.fill" : "pin.fill",
                    accessibilityDescription: activity.isPinned ? "Unpin" : "Pin"
                )
                action.backgroundColor = .controlAccentColor
                return [action]
            case .trailing:
                guard activity.id != configuration?.activeActivityID else { return [] }
                let action = NSTableViewRowAction(style: .destructive, title: "Delete") { [weak self] _, actionRow in
                    guard let activity = self?.activity(at: actionRow) else { return }
                    self?.configuration?.onDelete(activity)
                }
                action.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
                return [action]
            @unknown default:
                return []
            }
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tableView, let activity = activity(at: tableView.clickedRow) else { return }
            contextActivityID = activity.id
            let pin = menu.addItem(withTitle: activity.isPinned ? "Unpin" : "Pin", action: #selector(togglePinnedFromMenu), keyEquivalent: "")
            pin.target = self
            let rename = menu.addItem(withTitle: "Rename", action: #selector(renameFromMenu), keyEquivalent: "")
            rename.target = self
            let delete = menu.addItem(withTitle: "Delete", action: #selector(deleteFromMenu), keyEquivalent: "")
            delete.target = self
            delete.isEnabled = activity.id != configuration?.activeActivityID
        }

        @objc private func togglePinnedFromMenu() {
            guard let activity = contextActivity else { return }
            configuration?.onSetPinned(activity, !activity.isPinned)
        }

        @objc private func renameFromMenu() { if let activity = contextActivity { configuration?.onRename(activity) } }

        @objc private func deleteFromMenu() {
            guard let activity = contextActivity, activity.id != configuration?.activeActivityID else { return }
            configuration?.onDelete(activity)
        }

        private func activity(at row: Int) -> Activity? {
            guard let activities = configuration?.activities, activities.indices.contains(row) else { return nil }
            return activities[row]
        }

        private var contextActivity: Activity? {
            guard let contextActivityID else { return nil }
            return configuration?.activities.first(where: { $0.id == contextActivityID })
        }

        private func resizeDocumentView(_ tableView: NSTableView, for rowCount: Int) {
            guard let scrollView = tableView.enclosingScrollView else { return }
            let width = max(scrollView.contentSize.width, 1)
            let rowsHeight = CGFloat(rowCount) * tableView.rowHeight
            let height = max(rowsHeight, scrollView.contentSize.height)
            tableView.setFrameSize(NSSize(width: width, height: height))
        }
    }
}

private final class ActivityTableCellView: NSTableCellView {
    private let title = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let pin = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("activity.cell")
        title.lineBreakMode = .byTruncatingTail
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        pin.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")
        pin.contentTintColor = .secondaryLabelColor
        [title, status, pin].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0) }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            status.centerYAnchor.constraint(equalTo: centerYAnchor),
            pin.leadingAnchor.constraint(equalTo: status.trailingAnchor, constant: 6),
            pin.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            pin.centerYAnchor.constraint(equalTo: centerYAnchor),
            pin.widthAnchor.constraint(equalToConstant: 14),
            pin.heightAnchor.constraint(equalToConstant: 14),
            title.trailingAnchor.constraint(lessThanOrEqualTo: status.leadingAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(activity: Activity, isActive: Bool) {
        title.stringValue = activity.name.value
        title.setAccessibilityLabel(activity.name.value)
        status.stringValue = isActive ? "Running" : ""
        status.isHidden = !isActive
        pin.isHidden = !activity.isPinned
    }
}
