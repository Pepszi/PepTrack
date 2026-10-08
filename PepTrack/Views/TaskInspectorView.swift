import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#endif

struct TaskInspectorView: View {
    @Bindable var task: Task
    var titleFocusNonce: Int
    var focusesTitle: Bool
    var onTitleFocusHandled: (Int) -> Void
    var onDelete: () -> Void
    @Binding var isShowingTimeEntries: Bool

    @Environment(\.modelContext) private var modelContext
    @FocusState private var isTitleFocused: Bool
    @State private var isConfirmingDelete = false

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $task.title)
                    .focused($isTitleFocused)
                    .accessibilityIdentifier(InspectorTitleFocus.fieldIdentifier)
                    .background {
                        InspectorTitleFocus(
                            token: titleFocusNonce,
                            isActive: focusesTitle,
                            isFocused: isTitleFocused,
                            onClaimFocus: { isTitleFocused = true },
                            onFinished: onTitleFocusHandled
                        )
                    }
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

            Section("Description") {
                TextField("Description", text: $task.details, axis: .vertical)
                    .lineLimit(3...8)
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
        .onChange(of: task.details) { _, _ in
            modelContext.persist()
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

/// Keeps a newly created task's title field first responder.
/// Context menus and the row plus button take key focus back after they run,
/// and the inspector may still be sliding in, so this retries until the title sticks.
private struct InspectorTitleFocus: View {
    static let fieldIdentifier = "inspector-task-title"

    var token: Int
    var isActive: Bool
    var isFocused: Bool
    var onClaimFocus: () -> Void
    var onFinished: (Int) -> Void

    var body: some View {
        #if os(macOS)
        TitleFieldFocusAnchor(
            token: token,
            isActive: isActive,
            isFocused: isFocused,
            onClaimFocus: onClaimFocus,
            onFinished: onFinished
        )
        #else
        Color.clear
            .onAppear { claimIfNeeded(token) }
            .onChange(of: token) { _, newToken in
                claimIfNeeded(newToken)
            }
        #endif
    }

    #if !os(macOS)
    private func claimIfNeeded(_ token: Int) {
        guard isActive else { return }
        onClaimFocus()
        DispatchQueue.main.async {
            onClaimFocus()
            onFinished(token)
        }
    }
    #endif
}

#if os(macOS)
private struct TitleFieldFocusAnchor: NSViewRepresentable {
    var token: Int
    var isActive: Bool
    var isFocused: Bool
    var onClaimFocus: () -> Void
    var onFinished: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        PassthroughView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onClaimFocus = onClaimFocus
        context.coordinator.onFinished = onFinished
        context.coordinator.isFocused = isFocused
        context.coordinator.start(anchor: nsView, token: token, isActive: isActive)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var onClaimFocus: () -> Void = {}
        var onFinished: (Int) -> Void = { _ in }
        var isFocused = false
        private weak var anchor: NSView?
        private var token = 0
        private var attempt = 0
        private var cancelled = false
        private var scheduled = false
        private var didFinish = false
        private var initialText: String?
        private var stableSelectionTicks = 0

        func start(anchor: NSView, token: Int, isActive: Bool) {
            self.anchor = anchor
            guard isActive else { return }
            guard token != self.token else { return }
            self.token = token
            attempt = 0
            cancelled = false
            didFinish = false
            initialText = nil
            stableSelectionTicks = 0
            guard !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.tick()
            }
        }

        func stop() {
            cancelled = true
            anchor = nil
        }

        private func tick() {
            scheduled = false
            guard !cancelled, let anchor else { return }
            attempt += 1
            claimTitleField(from: anchor)
            if attempt == 22 {
                finishIfNeeded()
            }
            guard attempt < 26 else { return }
            scheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.tick()
            }
        }

        private func finishIfNeeded() {
            guard !didFinish, token != 0 else { return }
            didFinish = true
            let finishedToken = token
            DispatchQueue.main.async { [onFinished] in
                onFinished(finishedToken)
            }
        }

        private func claimTitleField(from anchor: NSView) {
            guard let field = titleField(from: anchor), let window = field.window else {
                if !isFocused {
                    onClaimFocus()
                }
                return
            }
            if initialText == nil, !field.stringValue.isEmpty || attempt > 4 {
                initialText = field.stringValue
            }
            let userEdited = initialText != nil && field.stringValue != initialText
            let editor = field.currentEditor()
            let isEditing = editor != nil && window.firstResponder === editor

            if !isFocused {
                onClaimFocus()
            }

            if isEditing, let editor {
                guard !userEdited else { return }
                let fullRange = NSRange(location: 0, length: (editor.string as NSString).length)
                if editor.selectedRange == fullRange {
                    stableSelectionTicks += 1
                } else if stableSelectionTicks < 4 {
                    editor.selectedRange = fullRange
                    stableSelectionTicks = 0
                }
                return
            }

            stableSelectionTicks = 0
            if userEdited {
                window.makeFirstResponder(field)
            } else {
                field.selectText(nil)
            }
        }

        private func titleField(from anchor: NSView) -> NSTextField? {
            if let root = anchor.window?.contentView,
               let field = root.textField(
                   withIdentifier: InspectorTitleFocus.fieldIdentifier,
                   excluding: anchor
               ) {
                return field
            }

            var current = anchor.superview
            var depth = 0
            while let view = current, depth < 10 {
                if let field = view.editableTextField(overlapping: anchor, excluding: anchor) {
                    return field
                }
                current = view.superview
                depth += 1
            }
            return nil
        }
    }
}

private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private extension NSView {
    func textField(withIdentifier identifier: String, excluding excluded: NSView) -> NSTextField? {
        if self !== excluded, accessibilityIdentifier() == identifier || self.identifier?.rawValue == identifier {
            if let field = self as? NSTextField, field.isEditable {
                return field
            }
            return firstEditableTextField(excluding: excluded)
        }
        for subview in subviews where subview !== excluded {
            if let field = subview.textField(withIdentifier: identifier, excluding: excluded) {
                return field
            }
        }
        return nil
    }

    func firstEditableTextField(excluding excluded: NSView) -> NSTextField? {
        if self !== excluded, let field = self as? NSTextField, field.isEditable {
            return field
        }
        for subview in subviews where subview !== excluded {
            if let field = subview.firstEditableTextField(excluding: excluded) {
                return field
            }
        }
        return nil
    }

    func editableTextField(overlapping anchor: NSView, excluding excluded: NSView) -> NSTextField? {
        if self !== excluded,
           let field = self as? NSTextField,
           field.isEditable,
           field.overlaps(anchor) {
            return field
        }
        for subview in subviews where subview !== excluded {
            if let field = subview.editableTextField(overlapping: anchor, excluding: excluded) {
                return field
            }
        }
        return nil
    }

    func overlaps(_ other: NSView) -> Bool {
        let ownFrame = convert(bounds, to: nil)
        let otherFrame = other.convert(other.bounds, to: nil)
        guard ownFrame.width > 1, ownFrame.height > 1, otherFrame.width > 1, otherFrame.height > 1 else {
            return false
        }
        return ownFrame.insetBy(dx: -6, dy: -6).intersects(otherFrame)
    }
}
#endif

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
