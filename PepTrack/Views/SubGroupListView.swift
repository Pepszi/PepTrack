import SwiftData
import SwiftUI

struct SubGroupListView: View {
    let client: ClientGroup?
    @Binding var selectedTaskID: PersistentIdentifier?
    @Binding var collapsedIDs: Set<PersistentIdentifier>
    var pinnedTaskID: PersistentIdentifier?
    var onTaskCreated: (PersistentIdentifier) -> Void

    @Environment(\.modelContext) private var modelContext
    @AppStorage("hideCompletedTasks") private var hideCompletedTasks = false
    @State private var subGroupPendingDeletion: SubGroup?
    @State private var taskPendingDeletion: Task?

    var body: some View {
        Group {
            if let client {
                if client.subGroups.isEmpty {
                    ContentUnavailableView {
                        Label("No Groups", systemImage: "folder")
                    } description: {
                        Text("Add a subgroup to organize tasks.")
                    } actions: {
                        Button("Add Subgroup", action: addSubGroup)
                    }
                } else {
                    taskList(for: client)
                }
            } else {
                ContentUnavailableView {
                    Label("Select a Client", systemImage: "sidebar.left")
                } description: {
                    Text("Choose a client to see groups and tasks.")
                }
            }
        }
        .navigationTitle(client?.name ?? "Tasks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $hideCompletedTasks) {
                    Label("Hide Completed", systemImage: "checkmark.circle")
                }
                .toggleStyle(.button)
                .disabled(client == nil)
                .help(hideCompletedTasks ? "Show completed tasks" : "Hide completed tasks")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: addSubGroup) {
                    Label("Add Subgroup", systemImage: "folder.badge.plus")
                }
                .disabled(client == nil)
                .help("Add Subgroup")
            }
        }
        .alert(
            "Delete \(subGroupPendingDeletion?.name ?? "Group")?",
            isPresented: deleteAlertPresented
        ) {
            Button("Delete", role: .destructive) {
                if let subGroupPendingDeletion {
                    delete(subGroupPendingDeletion)
                }
            }
            Button("Cancel", role: .cancel) {
                subGroupPendingDeletion = nil
            }
        } message: {
            Text("Tasks inside this group will be removed.")
        }
    }

    private func taskList(for client: ClientGroup) -> some View {
        List(selection: taskSelection) {
            ForEach(client.orderedSubGroups) { subGroup in
                DisclosureGroup(isExpanded: expansion(for: subGroup)) {
                    ForEach(visibleTasks(in: subGroup)) { task in
                        ReorderableRow(
                            drag: RowDrag(kind: .task, id: task.persistentModelID),
                            previewTitle: task.title.isEmpty ? "Untitled Task" : task.title
                        ) { drag, before in
                            drop(drag, on: task, before: before)
                        } content: {
                            TaskRowView(task: task) {
                                selectedTaskID = task.persistentModelID
                            }
                            .contextMenu {
                                Button(task.isTimerRunning ? "Pause Timer" : "Start Timer") {
                                    selectedTaskID = task.persistentModelID
                                    task.toggleTimer(in: modelContext)
                                }
                                Button(task.isInvoiced ? "Mark Not Invoiced" : "Mark Invoiced") {
                                    task.isInvoiced.toggle()
                                    modelContext.persist()
                                }
                                Divider()
                                Button("Delete Task", role: .destructive) {
                                    taskPendingDeletion = task
                                }
                            }
                        }
                        .tag(task.persistentModelID)
                    }
                } label: {
                    ReorderableRow(
                        drag: RowDrag(kind: .folder, id: subGroup.persistentModelID),
                        previewTitle: subGroup.name.isEmpty ? "Untitled Group" : subGroup.name
                    ) { drag, before in
                        drop(drag, on: subGroup, before: before)
                    } content: {
                        SubGroupHeader(
                            subGroup: subGroup,
                            taskCount: visibleTasks(in: subGroup).count
                        ) {
                            addTask(to: subGroup)
                        }
                        .contextMenu {
                            Button("Add Task") {
                                addTask(to: subGroup)
                            }
                            Button("Delete Group", role: .destructive) {
                                subGroupPendingDeletion = subGroup
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .id(client.persistentModelID)
        .animation(.smooth(duration: 0.2), value: hideCompletedTasks)
        .alert(
            "Delete \(pendingTaskTitle)?",
            isPresented: taskDeleteAlertPresented
        ) {
            Button("Delete", role: .destructive) {
                if let taskPendingDeletion {
                    delete(taskPendingDeletion)
                }
            }
            Button("Cancel", role: .cancel) {
                taskPendingDeletion = nil
            }
        } message: {
            Text("This task and its time entries will be removed.")
        }
    }

    private var pendingTaskTitle: String {
        let title = taskPendingDeletion?.title ?? ""
        return title.isEmpty ? "Untitled Task" : title
    }

    private var taskDeleteAlertPresented: Binding<Bool> {
        Binding(
            get: { taskPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    taskPendingDeletion = nil
                }
            }
        )
    }

    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: { subGroupPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    subGroupPendingDeletion = nil
                }
            }
        )
    }

    private func visibleTasks(in subGroup: SubGroup) -> [Task] {
        let tasks = subGroup.orderedTasks
        guard hideCompletedTasks else { return tasks }
        return tasks.filter { $0.status != .completed }
    }

    private func expansion(for subGroup: SubGroup) -> Binding<Bool> {
        Binding(
            get: { !collapsedIDs.contains(subGroup.persistentModelID) },
            set: { isExpanded in
                if isExpanded {
                    collapsedIDs.remove(subGroup.persistentModelID)
                } else {
                    collapsedIDs.insert(subGroup.persistentModelID)
                }
            }
        )
    }

    private func addSubGroup() {
        guard let client else { return }
        let nextIndex = (client.subGroups.map(\.sortIndex).max() ?? -1) + 1
        let subGroup = SubGroup(name: "New Group", clientGroup: client, sortIndex: nextIndex)
        modelContext.insert(subGroup)
        collapsedIDs.remove(subGroup.persistentModelID)
        modelContext.persist()
    }

    private var taskSelection: Binding<PersistentIdentifier?> {
        Binding(
            get: {
                guard let selectedTaskID, task(for: selectedTaskID) != nil else { return nil }
                return selectedTaskID
            },
            set: { newValue in
                // The header click that creates a task also clears list selection.
                // Keep the new task selected until its title has taken focus.
                if newValue == nil, let pinnedTaskID, selectedTaskID == pinnedTaskID {
                    return
                }
                // Group rows share this list selection. Their ids are not tasks,
                // and resolving one as a task aborts.
                if let newValue, task(for: newValue) == nil {
                    return
                }
                selectedTaskID = newValue
            }
        )
    }

    private func task(for id: PersistentIdentifier) -> Task? {
        guard let client else { return nil }
        for group in client.subGroups where !group.isDeleted {
            if let task = group.tasks.first(where: { $0.persistentModelID == id && !$0.isDeleted }) {
                return task
            }
        }
        return nil
    }

    private func addTask(to subGroup: SubGroup) {
        let nextIndex = (subGroup.tasks.map(\.sortIndex).max() ?? -1) + 1
        let task = Task(title: "New Task", sortIndex: nextIndex, subGroup: subGroup)
        modelContext.insert(task)
        if !subGroup.tasks.contains(where: { $0 === task }) {
            subGroup.tasks.append(task)
        }
        collapsedIDs.remove(subGroup.persistentModelID)
        modelContext.persist()
        publishNewTask(task)
        // The context menu and plus button restore key focus after the action returns.
        // Publish again on the next turn, once that handoff has started.
        DispatchQueue.main.async {
            publishNewTask(task)
        }
    }

    private func publishNewTask(_ task: Task) {
        if let subgroupID = task.subGroup?.persistentModelID {
            collapsedIDs.remove(subgroupID)
        }
        onTaskCreated(task.persistentModelID)
    }

    private func drop(_ drag: RowDrag, on task: Task, before: Bool) -> Bool {
        guard drag.kind == .task, let dragged = draggedTask(from: drag) else { return false }
        guard let folder = task.subGroup else { return false }
        return move(dragged, into: folder, beside: task, before: before)
    }

    private func drop(_ drag: RowDrag, on folder: SubGroup, before: Bool) -> Bool {
        switch drag.kind {
        case .folder:
            guard let dragged = subGroup(for: drag) else { return false }
            return move(dragged, beside: folder, before: before)
        case .task:
            guard let dragged = draggedTask(from: drag) else { return false }
            return move(dragged, into: folder, beside: nil, before: before)
        case .client:
            return false
        }
    }

    private func move(_ folder: SubGroup, beside target: SubGroup, before: Bool) -> Bool {
        guard folder.persistentModelID != target.persistentModelID, let client else { return false }
        var ordered = client.orderedSubGroups.filter { $0.persistentModelID != folder.persistentModelID }
        guard let index = ordered.firstIndex(where: { $0.persistentModelID == target.persistentModelID }) else {
            return false
        }
        ordered.insert(folder, at: before ? index : index + 1)
        applyFolderOrder(ordered)
        return true
    }

    private func move(_ task: Task, into folder: SubGroup, beside target: Task?, before: Bool) -> Bool {
        if let target, task.persistentModelID == target.persistentModelID {
            return false
        }
        let source = task.subGroup
        if task.subGroup?.persistentModelID != folder.persistentModelID {
            task.subGroup = folder
        }
        var ordered = folder.orderedTasks.filter { $0.persistentModelID != task.persistentModelID }
        if let target, let index = ordered.firstIndex(where: { $0.persistentModelID == target.persistentModelID }) {
            ordered.insert(task, at: before ? index : index + 1)
        } else if before {
            ordered.insert(task, at: 0)
        } else {
            ordered.append(task)
        }
        applyTaskOrder(ordered)
        if let source, source.persistentModelID != folder.persistentModelID {
            let remaining = source.orderedTasks.filter { $0.persistentModelID != task.persistentModelID }
            applyTaskOrder(remaining)
        }
        collapsedIDs.remove(folder.persistentModelID)
        modelContext.persist()
        return true
    }

    private func applyFolderOrder(_ folders: [SubGroup]) {
        withAnimation {
            for (index, folder) in folders.enumerated() where folder.sortIndex != index {
                folder.sortIndex = index
            }
        }
        modelContext.persist()
    }

    private func applyTaskOrder(_ tasks: [Task]) {
        withAnimation {
            for (index, task) in tasks.enumerated() where task.sortIndex != index {
                task.sortIndex = index
            }
        }
        modelContext.persist()
    }

    private func draggedTask(from drag: RowDrag) -> Task? {
        guard let id = drag.persistentID, let client else { return nil }
        for folder in client.subGroups {
            if let task = folder.tasks.first(where: { $0.persistentModelID == id }) {
                return task
            }
        }
        return nil
    }

    private func subGroup(for drag: RowDrag) -> SubGroup? {
        guard let id = drag.persistentID, let client else { return nil }
        return client.subGroups.first { $0.persistentModelID == id }
    }

    private func delete(_ task: Task) {
        if selectedTaskID == task.persistentModelID {
            selectedTaskID = nil
        }
        if task.isTimerRunning {
            task.stopTimer(in: modelContext)
        }
        modelContext.deleteAndPersist(task)
    }

    private func delete(_ subGroup: SubGroup) {
        if let selectedTaskID,
           subGroup.tasks.contains(where: { $0.persistentModelID == selectedTaskID }) {
            self.selectedTaskID = nil
        }
        for task in subGroup.tasks where task.isTimerRunning {
            task.stopTimer(in: modelContext)
        }
        subGroupPendingDeletion = nil
        modelContext.deleteAndPersist(subGroup)
    }
}

private struct SubGroupHeader: View {
    @Bindable var subGroup: SubGroup
    var taskCount: Int
    var onAddTask: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var isHoveringPlus = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .imageScale(.small)
            TextField("Group Name", text: $subGroup.name)
                .textFieldStyle(.plain)
                .font(.headline)
                .onSubmit {
                    modelContext.persist()
                }
            Text("\(taskCount)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            plusButton
        }
        .padding(.vertical, 2)
    }

    private var plusButton: some View {
        Button(action: onAddTask) {
            Image(systemName: "plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(isHoveringPlus ? Color.primary.opacity(0.1) : .clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .onHover { isHoveringPlus = $0 }
        .help("Add Task")
        .accessibilityLabel("Add Task")
    }
}

struct ReorderableRow<Content: View>: View {
    let drag: RowDrag
    let previewTitle: String
    let onDrop: (RowDrag, Bool) -> Bool
    @ViewBuilder var content: () -> Content

    @State private var isTargeted = false
    @State private var rowHeight: CGFloat = 0

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                if rowHeight != newHeight {
                    rowHeight = newHeight
                }
            }
            .draggable(drag) {
                Text(previewTitle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
            }
            .dropDestination(for: RowDrag.self) { items, location in
                guard let item = items.first else { return false }
                let before = location.y < rowHeight / 2
                return onDrop(item, before)
            } isTargeted: { isTargeted = $0 }
            .overlay(alignment: .top) {
                if isTargeted {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                }
            }
    }
}
