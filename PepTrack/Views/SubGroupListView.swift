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
    @State private var liftedID: PersistentIdentifier?
    @State private var previewGroups: [SubGroup]?
    @State private var previewTasks: [PersistentIdentifier: [Task]]?

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
            endDrag()
        }
        .onChange(of: hideCompletedTasks) { _, isHiding in
            guard isHiding else { return }
            selectedRowIDs.subtract(completedTaskIDs)
        }
    }

    private func taskList(for client: ClientGroup) -> some View {
        List(selection: listSelection) {
            ForEach(displayedGroups(of: client)) { subGroup in
                DisclosureGroup(isExpanded: expansion(for: subGroup)) {
                    ForEach(visibleTasks(in: subGroup)) { task in
                        ReorderableRow(
                            drag: RowDrag(kind: .task, id: task.persistentModelID),
                            isLifted: liftedID == task.persistentModelID
                        ) { before in
                            hover(over: task, in: subGroup, before: before)
                        } onDrop: {
                            commitDrag()
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
                        isLifted: liftedID == subGroup.persistentModelID
                    ) { before in
                        hover(over: subGroup, before: before)
                    } onDrop: {
                        commitDrag()
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
        .onDragRelease(isDragging: liftedID != nil) {
            endDrag()
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

    private func displayedGroups(of client: ClientGroup) -> [SubGroup] {
        previewGroups ?? client.orderedSubGroups
    }

    private func visibleTasks(in subGroup: SubGroup) -> [Task] {
        let tasks: [Task] = previewTasks?[subGroup.persistentModelID] ?? subGroup.orderedTasks
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

    /// Hides the highlight on the lifted row so its drop slot reads as empty, without changing the real selection.
    private var listSelection: Binding<Set<PersistentIdentifier>> {
        Binding(
            get: {
                guard let liftedID else { return selectedRowIDs }
                return selectedRowIDs.subtracting([liftedID])
            },
            set: { newIDs in
                guard liftedID == nil else { return }
                selectedRowIDs = newIDs
            }
        )
    }

    private func lift(_ id: PersistentIdentifier) {
        guard liftedID != id else { return }
        logReorder("lift row")
        previewGroups = nil
        previewTasks = nil
        liftedID = id
    }

    private func hover(over target: SubGroup, before: Bool) {
        guard let liftedID else {
            lift(target.persistentModelID)
            return
        }
        guard let client else { return }
        if let lifted = subGroup(for: liftedID) {
            guard lifted.persistentModelID != target.persistentModelID else { return }
            let current: [SubGroup] = displayedGroups(of: client)
            var order: [SubGroup] = current.filter { $0.persistentModelID != liftedID }
            guard let index = order.firstIndex(where: { $0.persistentModelID == target.persistentModelID }) else { return }
            order.insert(lifted, at: before ? index : index + 1)
            guard order.map(\.persistentModelID) != current.map(\.persistentModelID) else { return }
            withAnimation(.smooth(duration: 0.2)) {
                previewGroups = order
            }
        } else if let lifted = task(for: liftedID) {
            var layout: [PersistentIdentifier: [Task]] = taskLayoutWithoutLifted()
            let groups: [SubGroup] = displayedGroups(of: client)
            if before,
               let index = groups.firstIndex(where: { $0.persistentModelID == target.persistentModelID }),
               index > 0,
               !collapsedIDs.contains(groups[index - 1].persistentModelID) {
                layout[groups[index - 1].persistentModelID, default: []].append(lifted)
            } else {
                layout[target.persistentModelID, default: []].insert(lifted, at: 0)
            }
            showTaskPreview(layout)
        }
    }

    private func hover(over target: Task, in group: SubGroup, before: Bool) {
        guard let liftedID else {
            lift(target.persistentModelID)
            return
        }
        guard liftedID != target.persistentModelID, let lifted = task(for: liftedID) else { return }
        var layout: [PersistentIdentifier: [Task]] = taskLayoutWithoutLifted()
        var tasks: [Task] = layout[group.persistentModelID] ?? []
        guard let index = tasks.firstIndex(where: { $0.persistentModelID == target.persistentModelID }) else { return }
        tasks.insert(lifted, at: before ? index : index + 1)
        layout[group.persistentModelID] = tasks
        showTaskPreview(layout)
    }

    private func taskLayout() -> [PersistentIdentifier: [Task]] {
        if let previewTasks {
            return previewTasks
        }
        guard let client else { return [:] }
        var layout: [PersistentIdentifier: [Task]] = [:]
        for group in client.subGroups where !group.isDeleted {
            layout[group.persistentModelID] = group.orderedTasks
        }
        return layout
    }

    private func taskLayoutWithoutLifted() -> [PersistentIdentifier: [Task]] {
        taskLayout().mapValues { tasks in
            tasks.filter { $0.persistentModelID != liftedID }
        }
    }

    private func showTaskPreview(_ layout: [PersistentIdentifier: [Task]]) {
        let currentIDs = taskLayout().mapValues { $0.map(\.persistentModelID) }
        guard layout.mapValues({ $0.map(\.persistentModelID) }) != currentIDs else { return }
        withAnimation(.smooth(duration: 0.2)) {
            previewTasks = layout
        }
    }

    private func commitDrag() {
        if let previewGroups {
            for (index, group) in previewGroups.enumerated() where group.sortIndex != index {
                group.sortIndex = index
            }
        }
        if let previewTasks {
            for (groupID, tasks) in previewTasks {
                guard let group = subGroup(for: groupID) else { continue }
                for (index, task) in tasks.enumerated() {
                    if task.subGroup?.persistentModelID != groupID {
                        task.subGroup = group
                    }
                    if task.sortIndex != index {
                        task.sortIndex = index
                    }
                }
                if tasks.contains(where: { $0.persistentModelID == liftedID }) {
                    collapsedIDs.remove(groupID)
                }
            }
        }
        modelContext.persist()
        endDrag(animatesReturn: false)
    }

    /// The lifted row reappears in one frame so it reads as landing in its slot.
    /// Only a cancelled drag animates, sliding rows back to their saved order.
    private func endDrag(animatesReturn: Bool = true) {
        guard liftedID != nil || previewGroups != nil || previewTasks != nil else { return }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            liftedID = nil
            if !animatesReturn {
                previewGroups = nil
                previewTasks = nil
            }
        }
        withAnimation(.smooth(duration: 0.2)) {
            previewGroups = nil
            previewTasks = nil
        }
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
