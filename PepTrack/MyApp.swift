import SwiftData
import SwiftUI

@main
struct PepTrackApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(
            for: [ClientGroup.self, SubGroup.self, Task.self, TimeEntry.self],
            isUndoEnabled: true
        )
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        #endif
    }
}
