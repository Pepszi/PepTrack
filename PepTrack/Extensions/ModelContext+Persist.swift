import Foundation
import SwiftData

extension ModelContext {
    func persist() {
        guard hasChanges else { return }
        try? save()
    }

    /// Cascade deletes crash inside `save()` while an undo manager is attached.
    /// SwiftData writes an undo snapshot for related objects that were never snapshotted:
    /// "A snapshot should exist before creating a new snapshot for undo".
    func deleteAndPersist(_ model: some PersistentModel) {
        let undoManager = undoManager
        undoManager?.removeAllActions()
        self.undoManager = nil
        delete(model)
        persist()
        self.undoManager = undoManager
    }
}
