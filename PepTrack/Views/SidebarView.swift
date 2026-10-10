import SwiftData
import SwiftUI

struct SidebarView: View {
    let clients: [ClientGroup]
    @Binding var selectedClientID: PersistentIdentifier?
    @Binding var selectedTaskID: PersistentIdentifier?

    @Environment(\.modelContext) private var modelContext
    @State private var clientPendingDeletion: ClientGroup?
    @State private var liftedClientID: PersistentIdentifier?
    @State private var previewClients: [ClientGroup]?

    var body: some View {
        List(selection: listSelection) {
            ForEach(displayedClients) { client in
                ReorderableRow(
                    drag: RowDrag(kind: .client, id: client.persistentModelID),
                    isLifted: liftedClientID == client.persistentModelID
                ) { before in
                    hover(over: client, before: before)
                } onDrop: {
                    commitDrag()
                } content: {
                    ClientRow(client: client)
                        .contextMenu {
                            Button("Delete Client", role: .destructive) {
                                clientPendingDeletion = client
                            }
                        }
                }
                .tag(client.persistentModelID)
            }
        }
        .onDragRelease(isDragging: liftedClientID != nil) {
            endDrag()
        }
        .listStyle(.sidebar)
        .navigationTitle("Clients")
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        .overlay {
            if clients.isEmpty {
                ContentUnavailableView {
                    Label("No Clients", systemImage: "building.2")
                } description: {
                    Text("Add a client to start tracking work.")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                AddClientButton(action: addClient)
            }
            .background(.bar)
        }
        .alert(
            "Delete \(clientPendingDeletion?.name ?? "Client")?",
            isPresented: deleteAlertPresented
        ) {
            Button("Delete", role: .destructive) {
                if let clientPendingDeletion {
                    delete(clientPendingDeletion)
                }
            }
            Button("Cancel", role: .cancel) {
                clientPendingDeletion = nil
            }
        } message: {
            Text("Groups and tasks inside this client will be removed.")
        }
    }

    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: { clientPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    clientPendingDeletion = nil
                }
            }
        )
    }

    private func addClient() {
        let nextIndex = (clients.map(\.sortIndex).max() ?? -1) + 1
        let client = ClientGroup(name: "New Client", sortIndex: nextIndex)
        modelContext.insert(client)
        selectedClientID = client.persistentModelID
        selectedTaskID = nil
        modelContext.persist()
    }

    private var displayedClients: [ClientGroup] {
        previewClients ?? clients
    }

    /// Hides the highlight on the lifted row so its drop slot reads as empty, without changing the real selection.
    private var listSelection: Binding<PersistentIdentifier?> {
        Binding(
            get: {
                guard let liftedClientID, selectedClientID == liftedClientID else { return selectedClientID }
                return nil
            },
            set: { newID in
                guard liftedClientID == nil else { return }
                selectedClientID = newID
            }
        )
    }

    private func lift(_ client: ClientGroup) {
        let id: PersistentIdentifier = client.persistentModelID
        guard liftedClientID != id else { return }
        previewClients = nil
        liftedClientID = id
    }

    private func hover(over target: ClientGroup, before: Bool) {
        guard let liftedClientID else {
            lift(target)
            return
        }
        guard liftedClientID != target.persistentModelID,
              let lifted = clients.first(where: { $0.persistentModelID == liftedClientID }) else { return }
        let current: [ClientGroup] = displayedClients
        var order: [ClientGroup] = current.filter { $0.persistentModelID != liftedClientID }
        guard let index = order.firstIndex(where: { $0.persistentModelID == target.persistentModelID }) else { return }
        order.insert(lifted, at: before ? index : index + 1)
        guard order.map(\.persistentModelID) != current.map(\.persistentModelID) else { return }
        withAnimation(.smooth(duration: 0.2)) {
            previewClients = order
        }
    }

    private func commitDrag() {
        guard liftedClientID != nil else { return }
        for (index, client) in displayedClients.enumerated() where client.sortIndex != index {
            client.sortIndex = index
        }
        modelContext.persist()
        endDrag(animatesReturn: false)
    }

    /// The lifted row reappears in one frame so it reads as landing in its slot.
    /// Only a cancelled drag animates, sliding rows back to their saved order.
    private func endDrag(animatesReturn: Bool = true) {
        guard liftedClientID != nil || previewClients != nil else { return }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            liftedClientID = nil
            if !animatesReturn {
                previewClients = nil
            }
        }
        withAnimation(.smooth(duration: 0.2)) {
            previewClients = nil
        }
    }

    private func delete(_ client: ClientGroup) {
        if selectedClientID == client.persistentModelID {
            selectedClientID = nil
            selectedTaskID = nil
        }
        clientPendingDeletion = nil
        modelContext.deleteAndPersist(client)
    }
}

private struct ClientRow: View {
    @Bindable var client: ClientGroup
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "building.2")
                .foregroundStyle(.secondary)
                .imageScale(.small)
                .frame(width: 16)
            TextField("Client Name", text: $client.name)
                .textFieldStyle(.plain)
                .onSubmit {
                    modelContext.persist()
                }
        }
        .padding(.vertical, 2)
    }
}

private struct AddClientButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label("Add Client", systemImage: "plus")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? Color.primary.opacity(0.08) : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .onHover { isHovering = $0 }
        .help("Add Client")
    }
}
