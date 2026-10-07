import Foundation
import SwiftData

extension Task {
    var openTimeEntry: TimeEntry? {
        timeEntries.first { entry in
            !entry.isDeleted && entry.isOpen
        }
    }

    var entriesByNewest: [TimeEntry] {
        timeEntries
            .filter { !$0.isDeleted }
            .sorted { lhs, rhs in
                if lhs.startedAt != rhs.startedAt {
                    return lhs.startedAt > rhs.startedAt
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    func refreshTrackedTotal() {
        let total = timeEntries.reduce(0) { partial, entry in
            guard !entry.isDeleted else { return partial }
            return partial + entry.closedDuration
        }
        if actualTimeTracked != total {
            actualTimeTracked = total
        }
    }

    func toggleTimer(in context: ModelContext) {
        if isTimerRunning {
            stopTimer(in: context)
        } else {
            startTimer(in: context)
        }
    }

    func startTimer(in context: ModelContext) {
        let now = Date()
        haltOtherRunningTimers(in: context, at: now)
        closeOpenEntry(at: now, in: context, discardSubsecond: true)
        attach(TimeEntry(startedAt: now), in: context)
        isTimerRunning = true
        lastTimerStarted = now
        refreshTrackedTotal()
        context.persist()
    }

    func stopTimer(in context: ModelContext) {
        closeOpenEntry(at: .now, in: context, discardSubsecond: true)
        isTimerRunning = false
        lastTimerStarted = nil
        refreshTrackedTotal()
        context.persist()
    }

    func addTimeEntry(startedAt: Date, endedAt: Date, in context: ModelContext) {
        let entry = TimeEntry(
            startedAt: startedAt,
            endedAt: endedAt
        )
        attach(entry, in: context)
        refreshTrackedTotal()
        context.persist()
    }

    func updateTimeEntry(
        _ entry: TimeEntry,
        startedAt: Date,
        endedAt: Date?,
        in context: ModelContext
    ) {
        entry.startedAt = startedAt
        entry.endedAt = endedAt
        if endedAt == nil {
            isTimerRunning = true
            lastTimerStarted = startedAt
        }
        refreshTrackedTotal()
        context.persist()
    }

    func deleteTimeEntry(_ entry: TimeEntry, in context: ModelContext) {
        let wasOpen = entry.isOpen
        context.delete(entry)
        if wasOpen {
            isTimerRunning = false
            lastTimerStarted = nil
        }
        refreshTrackedTotal()
        context.persist()
    }

    /// The open session is already a `TimeEntry`. This only repairs a running
    /// timer that was started before entries existed.
    func checkpointRunningTimer(at now: Date, in context: ModelContext) {
        guard isTimerRunning else { return }
        ensureOpenEntry(at: now, in: context)
    }

    static func checkpointRunningTimers(in context: ModelContext) {
        let descriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                task.isTimerRunning
            }
        )
        let running = (try? context.fetch(descriptor)) ?? []
        guard !running.isEmpty else { return }
        let now = Date()
        for task in running {
            task.checkpointRunningTimer(at: now, in: context)
        }
        context.persist()
    }

    /// Turns a pre-entry cumulative total into one closed entry, once.
    static func migrateLegacyTimeEntries(in context: ModelContext) {
        let tasks = (try? context.fetch(FetchDescriptor<Task>())) ?? []
        for task in tasks {
            task.importLegacyTotalIfNeeded(in: context)
            task.ensureOpenEntry(at: .now, in: context)
            task.refreshTrackedTotal()
        }
        context.persist()
    }

    private func importLegacyTotalIfNeeded(in context: ModelContext) {
        guard timeEntries.isEmpty, actualTimeTracked > 0 else { return }
        let anchor = lastTimerStarted ?? Date()
        let start = anchor.addingTimeInterval(-actualTimeTracked)
        attach(TimeEntry(startedAt: start, endedAt: anchor), in: context)
    }

    private func ensureOpenEntry(at now: Date, in context: ModelContext) {
        guard isTimerRunning, openTimeEntry == nil else { return }
        let start = lastTimerStarted ?? now
        attach(TimeEntry(startedAt: start), in: context)
        lastTimerStarted = start
    }

    private func haltOtherRunningTimers(in context: ModelContext, at now: Date) {
        let descriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                task.isTimerRunning
            }
        )
        let running = (try? context.fetch(descriptor)) ?? []
        for other in running where other.persistentModelID != persistentModelID {
            other.closeOpenEntry(at: now, in: context, discardSubsecond: true)
            other.isTimerRunning = false
            other.lastTimerStarted = nil
            other.refreshTrackedTotal()
        }
    }

    private func closeOpenEntry(at now: Date, in context: ModelContext, discardSubsecond: Bool) {
        guard let open = openTimeEntry else {
            guard isTimerRunning, let lastTimerStarted else { return }
            let duration = now.timeIntervalSince(lastTimerStarted)
            guard duration > 0 else { return }
            if discardSubsecond, duration < 1 { return }
            attach(TimeEntry(startedAt: lastTimerStarted, endedAt: now), in: context)
            return
        }

        let duration = now.timeIntervalSince(open.startedAt)
        if discardSubsecond, duration < 1 {
            context.delete(open)
            return
        }
        open.endedAt = now
    }

    private func attach(_ entry: TimeEntry, in context: ModelContext) {
        entry.task = self
        context.insert(entry)
        if !timeEntries.contains(where: { $0 === entry }) {
            timeEntries.append(entry)
        }
    }
}
