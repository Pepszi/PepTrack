import SwiftData

extension ModelContext {
    func persist() {
        guard hasChanges else { return }
        try? save()
    }
}
