import Foundation
import SwiftData

@Model
final class SubGroup {
    var name: String
    var createdAt: Date
    var sortIndex: Int = 0
    var clientGroup: ClientGroup?

    @Relationship(deleteRule: .cascade, inverse: \Task.subGroup)
    var tasks: [Task]

    init(
        name: String,
        clientGroup: ClientGroup? = nil,
        createdAt: Date = .now,
        sortIndex: Int = 0
    ) {
        self.name = name
        self.createdAt = createdAt
        self.sortIndex = sortIndex
        self.clientGroup = clientGroup
        self.tasks = []
    }

    var orderedTasks: [Task] {
        tasks.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex {
                return lhs.sortIndex < rhs.sortIndex
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
}
