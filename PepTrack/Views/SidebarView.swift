import SwiftData
import SwiftUI

struct SidebarView: View {
    let clients: [ClientGroup]
    @Binding var selectedClientID: PersistentIdentifier?
    @Binding var selectedTaskID: PersistentIdentifier?

    @Environment(\.modelContext) private var modelContext
    @State private var clientPendingDeletion: ClientGroup?

    var body: some View {
        List(selection: $selectedClientID) {
            ForEach(clients) { client in
                ClientRow(client: client)
                    .tag(client.persistentModelID)
                    .contextMenu {
                        Button("Delete Client", role: .destructive) {
                            clientPendingDeletion = client
                        }
                    }
            }
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
        let client = ClientGroup(name: "New Client")
        modelContext.insert(client)
        selectedClientID = client.persistentModelID
        selectedTaskID = nil
        modelContext.persist()
    }

    private func delete(_ client: ClientGroup) {
        if selectedClientID == client.persistentModelID {
            selectedClientID = nil
            selectedTaskID = nil
        }
        modelContext.delete(client)
        clientPendingDeletion = nil
        modelContext.persist()
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
