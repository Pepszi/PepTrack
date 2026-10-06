import Foundation
import SwiftData

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case toDo
    case inProgress
    case general
    case blocked
    case review
    case completed

    var id: String { rawValue }
}

@Model
final class Task {
    var title: String
    var status: TaskStatus
    var startDate: Date?
    var endDate: Date?
    var timeEstimateHours: Double
    var actualTimeTracked: TimeInterval
    var isTimerRunning: Bool
    var lastTimerStarted: Date?
    var budget: Double
    var isInvoiced: Bool
    var createdAt: Date
    var sortIndex: Int = 0
    var subGroup: SubGroup?

    @Relationship(deleteRule: .cascade, inverse: \TimeEntry.task)
    var timeEntries: [TimeEntry]

    init(
        title: String,
        status: TaskStatus = .toDo,
        startDate: Date? = nil,
        endDate: Date? = nil,
        timeEstimateHours: Double = 0,
        actualTimeTracked: TimeInterval = 0,
        isTimerRunning: Bool = false,
        lastTimerStarted: Date? = nil,
        budget: Double = 0,
        isInvoiced: Bool = false,
        createdAt: Date = .now,
        sortIndex: Int = 0,
        subGroup: SubGroup? = nil
    ) {
        self.title = title
        self.status = status
        self.startDate = startDate
        self.endDate = endDate
        self.timeEstimateHours = timeEstimateHours
        self.actualTimeTracked = actualTimeTracked
        self.isTimerRunning = isTimerRunning
        self.lastTimerStarted = lastTimerStarted
        self.budget = budget
        self.isInvoiced = isInvoiced
        self.createdAt = createdAt
        self.sortIndex = sortIndex
        self.subGroup = subGroup
        self.timeEntries = []
    }
}
