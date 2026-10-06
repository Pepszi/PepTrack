import Foundation

enum DurationFormat {
    static func clock(_ interval: TimeInterval) -> String {
        let safeInterval = interval.isFinite ? max(0, interval) : 0
        let totalSeconds = Int(safeInterval.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
