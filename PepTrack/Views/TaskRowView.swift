import SwiftData
import SwiftUI

struct TaskRowView: View {
    @Bindable var task: Task
    var onSelect: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var isEditingTitle = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: task.status.symbolName)
                .foregroundStyle(task.status.tint)
                .frame(width: 16)
                .accessibilityLabel(task.status.title)

            title

            if task.isInvoiced {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .help("Invoiced")
                    .accessibilityLabel("Invoiced")
            }

            Spacer(minLength: 8)

            LiveTimerLabel(
                accumulated: task.actualTimeTracked,
                isRunning: task.isTimerRunning,
                startedAt: task.lastTimerStarted
            )

            timerButton
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var title: some View {
        if isEditingTitle {
            TextField("Task Title", text: $task.title)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onSubmit {
                    isEditingTitle = false
                    modelContext.persist()
                }
        } else {
            Text(task.title.isEmpty ? "Untitled Task" : task.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(task.status == .completed ? .secondary : .primary)
                .onTapGesture(count: 2) {
                    isEditingTitle = true
                }
        }
    }

    private var timerButton: some View {
        Button {
            onSelect()
            task.toggleTimer(in: modelContext)
        } label: {
            Image(systemName: task.isTimerRunning ? "pause.fill" : "play.fill")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(TimerButtonStyle())
        .help(task.isTimerRunning ? "Pause" : "Start timer")
        .accessibilityLabel(task.isTimerRunning ? "Pause timer" : "Start timer")
    }
}

private struct TimerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TimerButtonBody(configuration: configuration)
    }
}

private struct TimerButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(isHovering || configuration.isPressed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .background(
                Circle()
                    .fill(fill)
            )
            .onHover { isHovering = $0 }
    }

    private var fill: Color {
        if configuration.isPressed {
            return Color.primary.opacity(0.16)
        }
        if isHovering {
            return Color.primary.opacity(0.08)
        }
        return .clear
    }
}
