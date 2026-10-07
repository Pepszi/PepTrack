import SwiftData
import SwiftUI

struct TimeEntryListView: View {
    @Bindable var task: Task

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isCreating = false
    @State private var editingEntry: TimeEntry?

    var body: some View {
        NavigationStack {
            Group {
                if task.entriesByNewest.isEmpty {
                    ContentUnavailableView {
                        Label("No Time Entries", systemImage: "clock")
                    } description: {
                        Text("Add an entry or start the timer.")
                    } actions: {
                        Button("Add Entry") {
                            isCreating = true
                        }
                    }
                } else {
                    List {
                        ForEach(task.entriesByNewest) { entry in
                            TimeEntryRow(
                                entry: entry,
                                onEdit: { editingEntry = entry },
                                onDelete: { task.deleteTimeEntry(entry, in: modelContext) }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Time Entries")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreating = true
                    } label: {
                        Label("Add Entry", systemImage: "plus")
                    }
                }
            }
        }
        .frame(minWidth: 440, minHeight: 360)
        .sheet(isPresented: $isCreating) {
            TimeEntryEditorView(task: task, entry: nil)
        }
        .sheet(item: $editingEntry) { entry in
            TimeEntryEditorView(task: task, entry: entry)
        }
    }
}

private struct TimeEntryRow: View {
    let entry: TimeEntry
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onEdit) {
                Text(rangeLabel)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            durationLabel

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete Entry")
            .accessibilityLabel("Delete Entry")
        }
        .contextMenu {
            Button("Edit Entry", action: onEdit)
            Button("Delete Entry", role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder
    private var durationLabel: some View {
        if entry.isOpen {
            LiveTimerLabel(
                accumulated: 0,
                isRunning: true,
                startedAt: entry.startedAt
            )
        } else {
            Text(DurationFormat.clock(entry.closedDuration))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 84, alignment: .trailing)
        }
    }

    private var rangeLabel: String {
        let day = entry.startedAt.formatted(date: .abbreviated, time: .omitted)
        let startTime = entry.startedAt.formatted(date: .omitted, time: .shortened)
        guard let endedAt = entry.endedAt else {
            return "\(day)  \(startTime) – Running"
        }
        let sameDay = Calendar.current.isDate(entry.startedAt, inSameDayAs: endedAt)
        let endTime = endedAt.formatted(date: .omitted, time: .shortened)
        if sameDay {
            return "\(day)  \(startTime)–\(endTime)"
        }
        let end = endedAt.formatted(date: .abbreviated, time: .shortened)
        let start = entry.startedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(start) – \(end)"
    }
}
