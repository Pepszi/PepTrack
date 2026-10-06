import Foundation
import SwiftUI

/// Elapsed time for one task. A running timer ticks only inside this `TimelineView`,
/// so the list and inspector do not redraw every second.
struct LiveTimerLabel: View {
    let accumulated: TimeInterval
    let isRunning: Bool
    let startedAt: Date?

    var body: some View {
        Group {
            if isRunning, let startedAt {
                // Schedule from now so a timer that has been running for hours
                // does not replay every missed second.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = context.date.timeIntervalSince(startedAt)
                    clockText(accumulated + max(0, elapsed))
                }
            } else {
                clockText(accumulated)
            }
        }
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(isRunning ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(minWidth: 84, alignment: .trailing)
        .accessibilityLabel(isRunning ? "Timer running" : "Time tracked")
    }

    private func clockText(_ interval: TimeInterval) -> some View {
        Text(DurationFormat.clock(interval))
            .contentTransition(.numericText())
    }
}
