import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#endif

struct TaskInspectorView: View {
    @Bindable var task: Task
    var titleFocusNonce: Int
    var focusesTitle: Bool
    var onTitleFocusHandled: () -> Void
    var onDelete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @FocusState private var isTitleFocused: Bool
    @State private var isShowingTimeEntries = false
    @State private var isConfirmingDelete = false

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $task.title)
                    .focused($isTitleFocused)
                    .onSubmit {
                        modelContext.persist()
                    }
                Picker("Status", selection: $task.status) {
                    ForEach(TaskStatus.allCases) { status in
                        Label(status.title, systemImage: status.symbolName)
                            .tag(status)
                    }
                }
            }

            Section("Schedule") {
                OptionalDateRow(title: "Start", date: $task.startDate)
                OptionalDateRow(title: "End", date: $task.endDate)
            }

            Section("Time") {
                LabeledContent("Estimate") {
                    HStack(spacing: 4) {
                        TextField(
                            "",
                            value: $task.timeEstimateHours,
                            format: .number.precision(.fractionLength(0...2))
                        )
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .labelsHidden()
                        Text("h")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                LabeledContent("Tracked") {
                    LiveTimerLabel(
                        accumulated: task.actualTimeTracked,
                        isRunning: task.isTimerRunning,
                        startedAt: task.lastTimerStarted
                    )
                }
                HStack(spacing: 8) {
                    Button {
                        task.toggleTimer(in: modelContext)
                    } label: {
                        Label(
                            task.isTimerRunning ? "Pause Timer" : "Start Timer",
                            systemImage: task.isTimerRunning ? "pause.fill" : "play.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }

                    Button {
                        isShowingTimeEntries = true
                    } label: {
                        Label("Time Entries", systemImage: "list.bullet")
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            Section("Billing") {
                LabeledContent("Budget") {
                    TextField("", value: budgetBinding, format: .number)
                        .multilineTextAlignment(.trailing)
                        .labelsHidden()
                }
                Toggle("Invoiced", isOn: $task.isInvoiced)
            }

            Section {
                Button("Delete Task", role: .destructive) {
                    isConfirmingDelete = true
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isShowingTimeEntries) {
            TimeEntryListView(task: task)
        }
        .alert(
            "Delete \(task.title.isEmpty ? "Untitled Task" : task.title)?",
            isPresented: $isConfirmingDelete
        ) {
            Button("Delete", role: .destructive, action: deleteTask)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This task and its time entries will be removed.")
        }
        .onAppear {
            focusTitleIfNeeded()
        }
        .onChange(of: titleFocusNonce) { _, _ in
            focusTitleIfNeeded()
        }
        .onChange(of: task.status) { _, _ in
            modelContext.persist()
        }
        .onChange(of: task.startDate) { _, _ in
            modelContext.persist()
        }
        .onChange(of: task.endDate) { _, _ in
            modelContext.persist()
        }
        .onChange(of: task.timeEstimateHours) { _, _ in
            modelContext.persist()
        }
        .onChange(of: task.budget) { _, _ in
            modelContext.persist()
        }
        .onChange(of: task.isInvoiced) { _, _ in
            modelContext.persist()
        }
        .onDisappear {
            modelContext.persist()
        }
    }

    private func focusTitleIfNeeded() {
        guard focusesTitle else { return }
        isTitleFocused = true
        DispatchQueue.main.async {
            isTitleFocused = true
            DispatchQueue.main.async {
                #if os(macOS)
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                #endif
                onTitleFocusHandled()
            }
        }
    }

    private var budgetBinding: Binding<Int> {
        Binding(
            get: { Int(task.budget.rounded()) },
            set: { task.budget = Double($0) }
        )
    }

    private func deleteTask() {
        if task.isTimerRunning {
            task.stopTimer(in: modelContext)
        }
        onDelete()
        modelContext.delete(task)
        modelContext.persist()
    }
}

private struct OptionalDateRow: View {
    let title: String
    @Binding var date: Date?

    var body: some View {
        LabeledContent(title) {
            if date != nil {
                HStack(spacing: 6) {
                    DatePicker(
                        title,
                        selection: dateBinding,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    Button {
                        date = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Clear \(title) Date")
                }
            } else {
                Button("Add") {
                    date = .now
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { date ?? .now },
            set: { date = $0 }
        )
    }
}
