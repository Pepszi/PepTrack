import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#endif

enum PepTrackStore {
    static let container: ModelContainer = {
        do {
            let container = try ModelContainer(
                for: ClientGroup.self,
                SubGroup.self,
                Task.self,
                TimeEntry.self
            )
            container.mainContext.undoManager = UndoManager()
            return container
        } catch {
            fatalError("Could not open the PepTrack library: \(error.localizedDescription)")
        }
    }()
}

@main
struct PepTrackApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(PepTrackAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(PepTrackStore.container)
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        #endif
        .commands {
            LibraryCommands()
        }
    }
}

#if os(macOS)
final class PepTrackAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = runningTasks()
        guard !running.isEmpty else { return .terminateNow }

        switch quitAlert(for: running).runModal() {
        case .alertFirstButtonReturn:
            return .terminateNow
        case .alertSecondButtonReturn:
            for task in running {
                task.stopTimer(in: PepTrackStore.container.mainContext)
            }
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    private func runningTasks() -> [Task] {
        let descriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                task.isTimerRunning
            }
        )
        let tasks = (try? PepTrackStore.container.mainContext.fetch(descriptor)) ?? []
        return tasks.filter { !$0.isDeleted }
    }

    private func quitAlert(for tasks: [Task]) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "A timer is still running"
        alert.informativeText = quitMessage(for: tasks)
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Stop and Quit")
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"
        return alert
    }

    private func quitMessage(for tasks: [Task]) -> String {
        if tasks.count == 1 {
            return "“\(tasks[0].displayTitle)” is still tracking. Quit without stopping it?"
        }
        let names = tasks.map(\.displayTitle).formatted(.list(type: .and))
        return "\(names) are still tracking. Quit without stopping them?"
    }
}

private extension Task {
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Task" : trimmed
    }
}
#endif
