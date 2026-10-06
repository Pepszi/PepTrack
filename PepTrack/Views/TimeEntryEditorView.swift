import SwiftData
import SwiftUI

struct TimeEntryEditorView: View {
    @Bindable var task: Task
    let entry: TimeEntry?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var startedAt: Date
    @State private var endedAt: Date
    @State private var note: String

    init(task: Task, entry: TimeEntry?) {
        self.task = task
        self.entry = entry
        if let entry {
            _startedAt = State(initialValue: entry.startedAt)
            _endedAt = State(initialValue: entry.endedAt ?? Date())
            _note = State(initialValue: entry.note)
        } else {
            let end = Date()
            _startedAt = State(initialValue: end.addingTimeInterval(-3600))
            _endedAt = State(initialValue: end)
            _note = State(initialValue: "")
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
                        TextField(
                            "Hours",
                            value: durationBinding,
                            format: .number.precision(.fractionLength(0...2))
                        )
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                        Text("h")
                            .foregroundStyle(.secondary)
                        Text(DurationFormat.clock(draftDuration))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    if !canSave {
                        Text("End time must be after the start time.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(2...4)
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
                endedAt = startedAt.addingTimeInterval(max(0, hours) * 3600)
            }
        )
    }

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let entry {
            task.updateTimeEntry(
                entry,
                startedAt: startedAt,
                endedAt: isRunningEntry ? nil : endedAt,
                note: trimmedNote,
                in: modelContext
            )
        } else {
            task.addTimeEntry(
                startedAt: startedAt,
                endedAt: endedAt,
                note: trimmedNote,
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
