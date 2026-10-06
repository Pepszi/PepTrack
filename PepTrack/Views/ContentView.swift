import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \ClientGroup.createdAt) private var clients: [ClientGroup]

    @State private var selectedClientID: PersistentIdentifier?
    @State private var selectedTaskID: PersistentIdentifier?
    @State private var isInspectorPresented = false
    @State private var taskIDPendingTitleFocus: PersistentIdentifier?
    @State private var titleFocusNonce = 0

    var body: some View {
        NavigationSplitView {
            SidebarView(
                clients: clients,
                selectedClientID: $selectedClientID,
                selectedTaskID: $selectedTaskID
            )
        } detail: {
            SubGroupListView(
                client: selectedClient,
                selectedTaskID: $selectedTaskID,
                pinnedTaskID: taskIDPendingTitleFocus,
                onTaskCreated: focusNewTask
            )
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $isInspectorPresented) {
            inspector
                .inspectorColumnWidth(min: 300, ideal: 360, max: 460)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help(isInspectorPresented ? "Hide Inspector" : "Show Inspector")
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        .onChange(of: selectedClientID) { _, _ in
            guard let selectedTask else { return }
            if selectedTask.subGroup?.clientGroup?.persistentModelID != selectedClientID {
                selectedTaskID = nil
            }
        }
        .onChange(of: selectedTaskID) { _, newID in
            guard let newID else { return }
            isInspectorPresented = true
            if newID != taskIDPendingTitleFocus {
                taskIDPendingTitleFocus = nil
            }
        }
        .onAppear {
            PepTrack.Task.migrateLegacyTimeEntries(in: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            PepTrack.Task.checkpointRunningTimers(in: modelContext)
        }
        .onAppBackground {
            PepTrack.Task.checkpointRunningTimers(in: modelContext)
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let selectedTask {
            TaskInspectorView(
                task: selectedTask,
                titleFocusNonce: titleFocusNonce,
                focusesTitle: taskIDPendingTitleFocus == selectedTask.persistentModelID,
                onTitleFocusHandled: { token in
                    guard token == titleFocusNonce else { return }
                    taskIDPendingTitleFocus = nil
                },
                onDelete: {
                    selectedTaskID = nil
                }
            )
            .id(selectedTask.persistentModelID)
        } else {
            ContentUnavailableView {
                Label("No Task Selected", systemImage: "checklist")
            } description: {
                Text("Select a task to edit its schedule, status, and budget.")
            }
        }
    }

    private var selectedClient: ClientGroup? {
        guard let selectedClientID else { return nil }
        return clients.first { $0.persistentModelID == selectedClientID }
    }

    private var selectedTask: Task? {
        guard let selectedTaskID else { return nil }
        guard let task = task(for: selectedTaskID), !task.isDeleted else { return nil }
        if let selectedClientID,
           let ownerID = task.subGroup?.clientGroup?.persistentModelID,
           ownerID != selectedClientID {
            return nil
        }
        return task
    }

    private func task(for id: PersistentIdentifier) -> PepTrack.Task? {
        if let task: PepTrack.Task = modelContext.registeredModel(for: id) {
            return task
        }
        for folder in selectedClient?.subGroups ?? [] {
            if let task = folder.tasks.first(where: { $0.persistentModelID == id }) {
                return task
            }
        }
        return nil
    }

    private func focusNewTask(_ id: PersistentIdentifier) {
        taskIDPendingTitleFocus = id
        titleFocusNonce += 1
        isInspectorPresented = true
        selectedTaskID = id
        let nonce = titleFocusNonce
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            guard titleFocusNonce == nonce else { return }
            taskIDPendingTitleFocus = nil
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [ClientGroup.self, SubGroup.self, Task.self, TimeEntry.self],
            inMemory: true
        )
}

private extension View {
    @ViewBuilder
    func onAppBackground(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        self.onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            action()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            action()
        }
        #else
        self
        #endif
    }
}
