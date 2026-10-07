import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var isShowingTimeEntries = false
    @State private var collapsedGroupIDs: Set<PersistentIdentifier> = []
    @State private var didRestoreWindow = false
    @State private var isRestoringWindow = false
    @State private var taskIDPendingTitleFocus: PersistentIdentifier?
    @State private var titleFocusNonce = 0
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportDocument = LibraryFileDocument()
    @State private var exportFilename = "PepTrack"
    @State private var pendingImport: LibraryArchive?
    @State private var transferFailure: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                clients: clients,
                selectedClientID: clientSelection,
                selectedTaskID: $selectedTaskID
            )
        } detail: {
            SubGroupListView(
                client: selectedClient,
                selectedTaskID: $selectedTaskID,
                collapsedIDs: $collapsedGroupIDs,
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
        .focusedSceneValue(
            \.libraryActions,
            LibraryActions(exportLibrary: exportLibrary, importLibrary: importLibrary)
        )
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .peptrackArchive,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result, !error.isCancellation {
                transferFailure = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.peptrackArchive, .json]
        ) { result in
            switch result {
            case .success(let url):
                stageImport(from: url)
            case .failure(let error):
                if !error.isCancellation {
                    transferFailure = error.localizedDescription
                }
            }
        }
        .alert(
            "Replace Current Library?",
            isPresented: replaceAlertPresented
        ) {
            Button("Replace", role: .destructive) {
                if let pendingImport {
                    applyImport(pendingImport)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingImport = nil
            }
        } message: {
            Text("This replaces every client, group, task, and time entry with the imported file.")
        }
        .alert(
            "Couldn’t Transfer Library",
            isPresented: failureAlertPresented
        ) {
            Button("OK", role: .cancel) {
                transferFailure = nil
            }
        } message: {
            Text(transferFailure ?? "")
        }
        .onChange(of: selectedClientID) { _, newClientID in
            if !isRestoringWindow {
                deselectTask(outside: newClientID)
            }
            saveWindowLocation()
        }
        .onChange(of: selectedTaskID) { _, newID in
            guard let newID else {
                if !isRestoringWindow {
                    isShowingTimeEntries = false
                }
                saveWindowLocation()
                return
            }
            if !isRestoringWindow,
               let ownerID = taskAnywhere(newID)?.subGroup?.clientGroup?.persistentModelID,
               ownerID != selectedClientID {
                selectedTaskID = nil
                return
            }
            if !isRestoringWindow {
                isInspectorPresented = true
                isShowingTimeEntries = false
            }
            if newID != taskIDPendingTitleFocus {
                taskIDPendingTitleFocus = nil
            }
            saveWindowLocation()
        }
        .onChange(of: isInspectorPresented) { _, isPresented in
            if !isPresented, !isRestoringWindow {
                isShowingTimeEntries = false
            }
            saveWindowLocation()
        }
        .onChange(of: isShowingTimeEntries) { _, _ in
            saveWindowLocation()
        }
        .onChange(of: collapsedGroupIDs) { _, _ in
            saveWindowLocation()
        }
        .onAppear {
            PepTrack.Task.migrateLegacyTimeEntries(in: modelContext)
            restoreWindow()
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
                },
                isShowingTimeEntries: $isShowingTimeEntries
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

    /// Clears the task in the same update as the client, before the task list renders.
    private var clientSelection: Binding<PersistentIdentifier?> {
        Binding(
            get: { selectedClientID },
            set: { newClientID in
                if newClientID != selectedClientID {
                    deselectTask(outside: newClientID)
                }
                selectedClientID = newClientID
            }
        )
    }

    private func deselectTask(outside clientID: PersistentIdentifier?) {
        guard !isRestoringWindow, let selectedTaskID else { return }
        let ownerID = taskAnywhere(selectedTaskID)?.subGroup?.clientGroup?.persistentModelID
        guard ownerID != clientID else { return }
        self.selectedTaskID = nil
        taskIDPendingTitleFocus = nil
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
        let folders = selectedClient?.subGroups ?? allClients().flatMap(\.subGroups)
        for folder in folders where !folder.isDeleted {
            if let task = folder.tasks.first(where: { $0.persistentModelID == id && !$0.isDeleted }) {
                return task
            }
        }
        return nil
    }

    private func restoreWindow() {
        guard !didRestoreWindow else { return }
        didRestoreWindow = true
        guard let saved = WindowLocation.load() else { return }

        let client = saved.clientID.flatMap { storedClient(id: $0) }
        let task = saved.taskID.flatMap { storedTask(id: $0) }
        let taskClientID = task?.subGroup?.clientGroup?.persistentModelID
        let restoredClient = client ?? task?.subGroup?.clientGroup
        let taskBelongsToClient = restoredClient != nil && taskClientID == restoredClient?.persistentModelID
        let restoredTask = taskBelongsToClient ? task : nil

        var collapsed = Set(saved.collapsedGroupIDs.compactMap(PersistentIDArchive.decode))
        if let groupID = restoredTask?.subGroup?.persistentModelID {
            collapsed.remove(groupID)
        }

        isRestoringWindow = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedClientID = restoredClient?.persistentModelID
            isInspectorPresented = restoredTask != nil && saved.isInspectorPresented
            isShowingTimeEntries = isInspectorPresented && saved.showsTimeEntries
            collapsedGroupIDs = collapsed
        }

        // Selecting during the list's first layout leaves the highlight on the wrong frame.
        let taskID = restoredTask?.persistentModelID
        DispatchQueue.main.async {
            var selection = Transaction()
            selection.disablesAnimations = true
            withTransaction(selection) {
                selectedTaskID = taskID
            }
            DispatchQueue.main.async {
                isRestoringWindow = false
            }
        }
    }

    private func saveWindowLocation() {
        guard !isRestoringWindow else { return }
        WindowLocation.current(
            clientID: selectedClientID,
            taskID: selectedTaskID,
            isInspectorPresented: isInspectorPresented,
            showsTimeEntries: isShowingTimeEntries,
            collapsedGroupIDs: collapsedGroupIDs
        ).save()
    }

    private func storedClient(id data: Data) -> ClientGroup? {
        guard let id = PersistentIDArchive.decode(data) else { return nil }
        return allClients().first { $0.persistentModelID == id }
    }

    private func storedTask(id data: Data) -> Task? {
        guard let id = PersistentIDArchive.decode(data) else { return nil }
        return taskAnywhere(id)
    }

    private func taskAnywhere(_ id: PersistentIdentifier) -> Task? {
        for client in allClients() {
            for group in client.subGroups where !group.isDeleted {
                if let task = group.tasks.first(where: { $0.persistentModelID == id && !$0.isDeleted }) {
                    return task
                }
            }
        }
        return nil
    }

    private func allClients() -> [ClientGroup] {
        let stored = (try? modelContext.fetch(FetchDescriptor<ClientGroup>())) ?? []
        return stored.filter { !$0.isDeleted }
    }

    private var replaceAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingImport != nil },
            set: { isPresented in
                if !isPresented {
                    pendingImport = nil
                }
            }
        )
    }

    private var failureAlertPresented: Binding<Bool> {
        Binding(
            get: { transferFailure != nil },
            set: { isPresented in
                if !isPresented {
                    transferFailure = nil
                }
            }
        )
    }

    private func exportLibrary() {
        guard !isExporting else { return }
        PepTrack.Task.checkpointRunningTimers(in: modelContext)
        let archive = LibraryArchive.snapshot(of: modelContext)
        do {
            exportDocument = LibraryFileDocument(data: try archive.encodedData())
            exportFilename = LibraryArchive.suggestedFilename(at: archive.exportedAt)
            DispatchQueue.main.async {
                isExporting = true
            }
        } catch {
            transferFailure = error.localizedDescription
        }
    }

    private func importLibrary() {
        guard !isImporting else { return }
        isImporting = true
    }

    private func stageImport(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let archive = try LibraryArchive.decode(from: data)
            DispatchQueue.main.async {
                if clients.isEmpty {
                    applyImport(archive)
                } else {
                    pendingImport = archive
                }
            }
        } catch {
            let message = error.localizedDescription
            DispatchQueue.main.async {
                transferFailure = message
            }
        }
    }

    private func applyImport(_ archive: LibraryArchive) {
        pendingImport = nil
        selectedClientID = nil
        selectedTaskID = nil
        taskIDPendingTitleFocus = nil
        do {
            try archive.replaceContents(of: modelContext)
            let stored = try modelContext.fetch(
                FetchDescriptor<ClientGroup>(sortBy: [SortDescriptor(\.createdAt)])
            )
            selectedClientID = stored.first?.persistentModelID
        } catch {
            let message = error.localizedDescription
            DispatchQueue.main.async {
                transferFailure = message
            }
        }
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

private extension Error {
    var isCancellation: Bool {
        if self is CancellationError {
            return true
        }
        let nsError = self as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }
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
