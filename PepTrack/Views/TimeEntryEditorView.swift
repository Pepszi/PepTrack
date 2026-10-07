import SwiftData
import SwiftUI

struct TimeEntryEditorView: View {
    @Bindable var task: Task
    let entry: TimeEntry?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var startedAt: Date
    @State private var endedAt: Date

    init(task: Task, entry: TimeEntry?) {
        self.task = task
        self.entry = entry
        if let entry {
            _startedAt = State(initialValue: entry.startedAt)
            _endedAt = State(initialValue: entry.endedAt ?? Date())
        } else {
            let end = Date()
            _startedAt = State(initialValue: end.addingTimeInterval(-3600))
            _endedAt = State(initialValue: end)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Start",
                    selection: startBinding,
                    displayedComponents: [.date, .hourAndMinute]
                )

                if isRunningEntry {
                    LabeledContent("End") {
                        Text("Running")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Duration") {
                        LiveTimerLabel(
                            accumulated: 0,
                            isRunning: true,
                            startedAt: startedAt
                        )
                    }
                } else {
                    DatePicker(
                        "End",
                        selection: $endedAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    LabeledContent("Duration") {
                        HStack(spacing: 6) {
                            TextField(
                                "",
                                value: durationBinding,
                                format: .number.precision(.fractionLength(0...2)),
                                prompt: Text("Hours")
                            )
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .frame(width: 96)
                            .background(.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
                            }
                            Text("h")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(DurationFormat.clock(draftDuration))
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if !canSave {
                        Text("End time must be after the start time.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(entry == nil ? "New Entry" : "Edit Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                if entry != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", role: .destructive, action: deleteEntry)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 280)
    }

    private var isRunningEntry: Bool {
        entry?.isOpen == true
    }

    private var draftDuration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }

    private var canSave: Bool {
        if isRunningEntry { return true }
        return endedAt > startedAt
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { startedAt },
            set: { newStart in
                let duration = endedAt.timeIntervalSince(startedAt)
                startedAt = newStart
                if !isRunningEntry {
                    endedAt = newStart.addingTimeInterval(max(0, duration))
                }
            }
        )
    }

    private var durationBinding: Binding<Double> {
        Binding(
            get: { draftDuration / 3600 },
            set: { hours in
                let duration = max(0, hours) * 3600
                if entry == nil {
                    let end = Date()
                    endedAt = end
                    startedAt = end.addingTimeInterval(-duration)
                } else {
                    endedAt = startedAt.addingTimeInterval(duration)
                }
            }
        )
    }

    private func save() {
        if let entry {
            task.updateTimeEntry(
                entry,
                startedAt: startedAt,
                endedAt: isRunningEntry ? nil : endedAt,
                in: modelContext
            )
        } else {
            task.addTimeEntry(
                startedAt: startedAt,
                endedAt: endedAt,
                in: modelContext
            )
        }
        dismiss()
    }

    private func deleteEntry() {
        guard let entry else { return }
        dismiss()
        task.deleteTimeEntry(entry, in: modelContext)
    }
}
