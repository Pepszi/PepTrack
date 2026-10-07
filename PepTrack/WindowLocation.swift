import Foundation
import SwiftData

struct WindowLocation: Codable {
    var clientID: Data?
    var taskID: Data?
    var isInspectorPresented: Bool
    var showsTimeEntries: Bool
    var collapsedGroupIDs: [Data]

    private static let defaultsKey = "windowLocation"

    static func load() -> WindowLocation? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(WindowLocation.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    static func current(
        clientID: PersistentIdentifier?,
        taskID: PersistentIdentifier?,
        isInspectorPresented: Bool,
        showsTimeEntries: Bool,
        collapsedGroupIDs: Set<PersistentIdentifier>
    ) -> WindowLocation {
        WindowLocation(
            clientID: clientID.flatMap(PersistentIDArchive.encode),
            taskID: taskID.flatMap(PersistentIDArchive.encode),
            isInspectorPresented: isInspectorPresented,
            showsTimeEntries: showsTimeEntries,
            collapsedGroupIDs: collapsedGroupIDs.compactMap(PersistentIDArchive.encode)
        )
    }
}

nonisolated enum PersistentIDArchive {
    static func encode(_ id: PersistentIdentifier) -> Data? {
        try? JSONEncoder().encode(id)
    }

    static func decode(_ data: Data) -> PersistentIdentifier? {
        try? JSONDecoder().decode(PersistentIdentifier.self, from: data)
    }
}
