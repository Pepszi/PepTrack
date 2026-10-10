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
    @State private var selectedRowIDs: Set<PersistentIdentifier> = []
    @State private var pendingDeletion: PendingDeletion?

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
                Button(action: deleteSelection) {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedRowIDs.isEmpty)
                .help(deleteHelp)
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $hideCompletedTasks) {
                    Label("Hide Completed", systemImage: "checkmark.circle")
                }
                .toggleStyle(.button)
                .disabled(client == nil)
                .help(hideCompletedTasks ? "Show completed tasks" : "Hide completed tasks")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Expand All", systemImage: "chevron.down", action: expandAllGroups)
                        .disabled(allGroupsExpanded)
                        .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                    Button("Collapse All", systemImage: "chevron.right", action: collapseAllGroups)
                        .disabled(allGroupsCollapsed)
                        .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                } label: {
                    Label("Groups", systemImage: "rectangle.expand.vertical")
                }
                .disabled(client?.subGroups.isEmpty ?? true)
                .help("Expand or collapse every group")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: addSubGroup) {
                    Label("Add Subgroup", systemImage: "folder.badge.plus")
                }
                .disabled(client == nil)
                .help("Add Subgroup")
            }
        }
        .onDeleteCommand(perform: selectedRowIDs.isEmpty ? nil : { deleteSelection() })
        .onChange(of: selectedTaskID, initial: true) { _, newID in
            adoptExternalTaskSelection(newID)
        }
        .onChange(of: clientIdentity) { _, _ in
            selectedRowIDs = []
        }
        .onChange(of: hideCompletedTasks) { _, isHiding in
            guard isHiding else { return }
            selectedRowIDs.subtract(completedTaskIDs)
        }
    }

    private func taskList(for client: ClientGroup) -> some View {
        List(selection: $selectedRowIDs) {
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
                                selectedRowIDs = [task.persistentModelID]
                            }
                            .contextMenu {
                                Button(task.isTimerRunning ? "Pause Timer" : "Start Timer") {
                                    selectedRowIDs = [task.persistentModelID]
                                    task.toggleTimer(in: modelContext)
                                }
                                Button(task.isInvoiced ? "Mark Not Invoiced" : "Mark Invoiced") {
                                    task.isInvoiced.toggle()
                                    modelContext.persist()
                                }
                                Divider()
                                Button(deleteTitle(including: task.persistentModelID, single: "Delete Task"), role: .destructive) {
                                    stageDeletion(including: task.persistentModelID)
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
                            Divider()
                            Button("Expand All", action: expandAllGroups)
                                .disabled(allGroupsExpanded)
                            Button("Collapse All", action: collapseAllGroups)
                                .disabled(allGroupsCollapsed)
                            Divider()
                            Button(deleteTitle(including: subGroup.persistentModelID, single: "Delete Group"), role: .destructive) {
                                stageDeletion(including: subGroup.persistentModelID)
                            }
                        }
                    }
                }
                .tag(subGroup.persistentModelID)
            }
        }
        .listStyle(.inset)
        .id(client.persistentModelID)
        .animation(.smooth(duration: 0.2), value: hideCompletedTasks)
        .onChange(of: selectedRowIDs) { _, ids in
            applyRowSelection(ids)
        }
        .alert(
            deletionTitle,
            isPresented: deletionAlertPresented
        ) {
            Button("Delete", role: .destructive, action: performDeletion)
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text(deletionMessage)
        }
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

    private var allGroupsExpanded: Bool {
        guard let client, !client.subGroups.isEmpty else { return true }
        return client.subGroups.allSatisfy { !collapsedIDs.contains($0.persistentModelID) }
    }

    private var allGroupsCollapsed: Bool {
        guard let client, !client.subGroups.isEmpty else { return true }
        return client.subGroups.allSatisfy { collapsedIDs.contains($0.persistentModelID) }
    }

    private func expandAllGroups() {
        guard let client else { return }
        withAnimation(.smooth(duration: 0.2)) {
            for group in client.subGroups {
                collapsedIDs.remove(group.persistentModelID)
            }
        }
    }

    private func collapseAllGroups() {
        guard let client else { return }
        withAnimation(.smooth(duration: 0.2)) {
            for group in client.subGroups {
                collapsedIDs.insert(group.persistentModelID)
            }
        }
    }

    private func addSubGroup() {
        guard let client else { return }
        let nextIndex = (client.subGroups.map(\.sortIndex).max() ?? -1) + 1
        let subGroup = SubGroup(name: "New Group", clientGroup: client, sortIndex: nextIndex)
        modelContext.insert(subGroup)
        collapsedIDs.remove(subGroup.persistentModelID)
        modelContext.persist()
    }

    private var clientIdentity: PersistentIdentifier? {
        client?.persistentModelID
    }

    private var deleteHelp: String {
        switch selectedRowIDs.count {
        case 0: "Delete"
        case 1: "Delete Selected"
        default: "Delete \(selectedRowIDs.count) Items"
        }
    }

    private var deletionTitle: String {
        guard let pendingDeletion else { return "Delete?" }
        if pendingDeletion.groupIDs.count == 1, pendingDeletion.taskIDs.isEmpty {
            return "Delete \(groupName(pendingDeletion.groupIDs[0]))?"
        }
        if pendingDeletion.taskIDs.count == 1, pendingDeletion.groupIDs.isEmpty {
            return "Delete \(taskTitle(pendingDeletion.taskIDs[0]))?"
        }
        return "Delete \(pendingDeletion.groupIDs.count + pendingDeletion.taskIDs.count) Items?"
    }

    private var deletionMessage: String {
        guard let pendingDeletion else { return "" }
        switch (pendingDeletion.groupIDs.isEmpty, pendingDeletion.taskIDs.isEmpty) {
        case (false, true):
            return pendingDeletion.groupIDs.count == 1
                ? "Tasks inside this group will be removed."
                : "Tasks inside these groups will be removed."
        case (true, false):
            return pendingDeletion.taskIDs.count == 1
                ? "This task and its time entries will be removed."
                : "These tasks and their time entries will be removed."
        default:
            return "Selected groups are removed with every task inside them. Other selected tasks are removed with their time entries."
        }
    }

    private var deletionAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletion = nil
                }
            }
        )
    }

    private var completedTaskIDs: Set<PersistentIdentifier> {
        guard let client else { return [] }
        return Set(client.subGroups.flatMap(\.tasks).filter { $0.status == .completed }.map(\.persistentModelID))
    }

    /// The header click that creates a task also clears list selection.
    /// Keep that new task selected until its title has taken focus.
    private func applyRowSelection(_ ids: Set<PersistentIdentifier>) {
        if ids.isEmpty, let pinnedTaskID, selectedTaskID == pinnedTaskID {
            selectedRowIDs = [pinnedTaskID]
            return
        }
        if ids.count == 1, let id = ids.first, task(for: id) != nil {
            if selectedTaskID != id {
                selectedTaskID = id
            }
            return
        }
        if selectedTaskID != nil {
            selectedTaskID = nil
        }
    }

    private func adoptExternalTaskSelection(_ newID: PersistentIdentifier?) {
        guard let newID else {
            guard selectedRowIDs.count == 1, let only = selectedRowIDs.first, subGroup(for: only) == nil else {
                return
            }
            selectedRowIDs = []
            return
        }
        if selectedRowIDs != [newID] {
            selectedRowIDs = [newID]
        }
    }

    private func deleteTitle(including id: PersistentIdentifier, single: String) -> String {
        guard selectedRowIDs.contains(id), selectedRowIDs.count > 1 else { return single }
        return "Delete \(selectedRowIDs.count) Items"
    }

    private func deleteSelection() {
        stageDeletion(of: selectedRowIDs)
    }

    private func stageDeletion(including id: PersistentIdentifier) {
        if selectedRowIDs.contains(id), selectedRowIDs.count > 1 {
            stageDeletion(of: selectedRowIDs)
        } else {
            stageDeletion(of: [id])
        }
    }

    private func stageDeletion(of ids: Set<PersistentIdentifier>) {
        guard let client, !ids.isEmpty else { return }
        var groupIDs: [PersistentIdentifier] = []
        var taskIDs: [PersistentIdentifier] = []
        for group in client.orderedSubGroups where !group.isDeleted {
            let groupID = group.persistentModelID
            let groupIsSelected = ids.contains(groupID)
            if groupIsSelected {
                groupIDs.append(groupID)
            }
            for task in group.orderedTasks where !task.isDeleted && ids.contains(task.persistentModelID) && !groupIsSelected {
                taskIDs.append(task.persistentModelID)
            }
        }
        guard !groupIDs.isEmpty || !taskIDs.isEmpty else { return }
        pendingDeletion = PendingDeletion(groupIDs: groupIDs, taskIDs: taskIDs)
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
        guard let id = drag.persistentID else { return nil }
        return subGroup(for: id)
    }

    private func subGroup(for id: PersistentIdentifier) -> SubGroup? {
        guard let client else { return nil }
        return client.subGroups.first { $0.persistentModelID == id && !$0.isDeleted }
    }

    private func groupName(_ id: PersistentIdentifier) -> String {
        let name = subGroup(for: id)?.name ?? ""
        return name.isEmpty ? "Untitled Group" : name
    }

    private func taskTitle(_ id: PersistentIdentifier) -> String {
        let title = task(for: id)?.title ?? ""
        return title.isEmpty ? "Untitled Task" : title
    }

    private func performDeletion() {
        guard let pendingDeletion, let client else { return }
        let groups = pendingDeletion.groupIDs.compactMap { subGroup(for: $0) }
        let groupIDs = Set(groups.map(\.persistentModelID))
        var tasks: [Task] = []
        for group in client.subGroups where !group.isDeleted {
            for task in group.tasks where !task.isDeleted && pendingDeletion.taskIDs.contains(task.persistentModelID) {
                if let parentID = task.subGroup?.persistentModelID, groupIDs.contains(parentID) {
                    continue
                }
                tasks.append(task)
            }
        }

        var seenTimers = Set<PersistentIdentifier>()
        let runningTasks = tasks.filter(\.isTimerRunning) + groups.flatMap { group in
            group.tasks.filter { $0.isTimerRunning && !$0.isDeleted }
        }
        for task in runningTasks where seenTimers.insert(task.persistentModelID).inserted {
            task.stopTimer(in: modelContext)
        }

        var removedIDs = Set(pendingDeletion.groupIDs + pendingDeletion.taskIDs)
        for group in groups {
            removedIDs.formUnion(group.tasks.map(\.persistentModelID))
            collapsedIDs.remove(group.persistentModelID)
        }
        if let selectedTaskID, removedIDs.contains(selectedTaskID) {
            self.selectedTaskID = nil
        }
        selectedRowIDs.subtract(removedIDs)
        self.pendingDeletion = nil
        modelContext.deleteAndPersist(tasks.map { $0 as any PersistentModel } + groups.map { $0 as any PersistentModel })
    }
}

private struct PendingDeletion: Equatable {
    var groupIDs: [PersistentIdentifier]
    var taskIDs: [PersistentIdentifier]
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
                .foregroundStyle(taskCount == 0 ? .tertiary : .primary)
                .monospacedDigit()
            plusButton
        }
        .padding(.vertical, 2)
    }

    private var plusButton: some View {
        Button(action: onAddTask) {
            Image(systemName: "plus")
                .font(.caption.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.white)
                .opacity(1)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(isHoveringPlus ? Color.white.opacity(0.12) : .clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white)
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
