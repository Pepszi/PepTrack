import Foundation
import SwiftData

@Model
final class TimeEntry {
    var startedAt: Date
    var endedAt: Date?
    var note: String
    var createdAt: Date
    var task: Task?

    init(
        startedAt: Date,
        endedAt: Date? = nil,
        note: String = "",
        createdAt: Date = .now,
        task: Task? = nil
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.note = note
        self.createdAt = createdAt
        self.task = task
    }

    var isOpen: Bool {
        endedAt == nil
    }

    var closedDuration: TimeInterval {
        guard let endedAt else { return 0 }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }
}
