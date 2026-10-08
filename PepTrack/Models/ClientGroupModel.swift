import Foundation
import SwiftData

@Model
final class ClientGroup {
    var name: String
    var createdAt: Date
    var sortIndex: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \SubGroup.clientGroup)
    var subGroups: [SubGroup]

    init(name: String, createdAt: Date = .now, sortIndex: Int = 0) {
        self.name = name
        self.createdAt = createdAt
        self.sortIndex = sortIndex
        self.subGroups = []
    }

    var orderedSubGroups: [SubGroup] {
        subGroups.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex {
                return lhs.sortIndex < rhs.sortIndex
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
}
