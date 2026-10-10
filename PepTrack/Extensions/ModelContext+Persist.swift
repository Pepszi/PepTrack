import Foundation
import SwiftData

extension ModelContext {
    func persist() {
        guard hasChanges else { return }
        try? save()
    }

    func deleteAndPersist(_ model: some PersistentModel) {
        deleteAndPersist([model])
    }

    /// Cascade deletes crash inside `save()` while an undo manager is attached.
    /// SwiftData writes an undo snapshot for related objects that were never snapshotted:
    /// "A snapshot should exist before creating a new snapshot for undo".
    /// Pass parents after their children. A model already removed by an earlier cascade is skipped.
    func deleteAndPersist(_ models: [any PersistentModel]) {
        guard models.contains(where: { !$0.isDeleted }) else { return }
        let undoManager = undoManager
        undoManager?.removeAllActions()
        self.undoManager = nil
        for model in models where !model.isDeleted {
            delete(model)
        }
        persist()
        self.undoManager = undoManager
    }
}
