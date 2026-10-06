import SwiftUI

extension TaskStatus {
    var title: String {
        switch self {
        case .toDo: "To Do"
        case .inProgress: "In Progress"
        case .general: "General"
        case .blocked: "Blocked"
        case .review: "Review"
        case .completed: "Completed"
        }
    }

    var symbolName: String {
        switch self {
        case .toDo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .general: "circle.fill"
        case .blocked: "nosign"
        case .review: "eye"
        case .completed: "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .toDo: Color(red: 96 / 255, green: 96 / 255, blue: 96 / 255)
        case .inProgress: Color(red: 195 / 255, green: 101 / 255, blue: 34 / 255)
        case .general: Color(red: 92 / 255, green: 71 / 255, blue: 205 / 255)
        case .blocked: Color(red: 210 / 255, green: 31 / 255, blue: 36 / 255)
        case .review: Color(red: 255 / 255, green: 197 / 255, blue: 61 / 255)
        case .completed: Color(red: 43 / 255, green: 140 / 255, blue: 94 / 255)
        }
    }
}
