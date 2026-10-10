import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let reorderLogger = Logger(subsystem: "com.peptrack", category: "reorder")

func logReorder(_ message: String) {
    reorderLogger.notice("\(message, privacy: .public)")
}

/// A list row that can be dragged and reports where another row hovers over it,
/// so the parent can move rows aside live instead of drawing an insertion line.
struct ReorderableRow<Content: View>: View {
    let drag: RowDrag
    let isLifted: Bool
    let onHover: (_ before: Bool) -> Void
    let onDrop: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var rowHeight: CGFloat = 0

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(isLifted ? 0 : 1)
            .background {
                if isLifted {
                    dropSlot
                }
            }
            .background(TableDropHighlightSuppressor())
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                if rowHeight != newHeight {
                    rowHeight = newHeight
                }
            }
            .draggable(drag)
            .onDrop(
                of: [.peptrackRow],
                delegate: RowDropDelegate(rowHeight: rowHeight, onHover: onHover, onDrop: onDrop)
            )
    }

    private var dropSlot: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.accentColor.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        Color.accentColor.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                    )
            }
            .transition(.identity)
    }
}

private struct RowDropDelegate: DropDelegate {
    let rowHeight: CGFloat
    let onHover: (_ before: Bool) -> Void
    let onDrop: () -> Void

    func dropEntered(info: DropInfo) {
        hover(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        hover(info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        logReorder("perform drop")
        onDrop()
        return true
    }

    /// Right after rows move, SwiftUI can report a location measured against the row's old frame.
    /// It also sends one more update about a third of a second after a drop, once the button is already up.
    private func hover(_ info: DropInfo) {
        guard NSEvent.pressedMouseButtons & 1 != 0,
              rowHeight > 0,
              (0...rowHeight).contains(info.location.y) else { return }
        onHover(info.location.y < rowHeight / 2)
    }
}

/// SwiftUI routes row drops through the list's `NSTableView`, which highlights the row it last
/// computed as the drop target. Rows move during a drag, so that highlight lands on unrelated rows.
private struct TableDropHighlightSuppressor: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {}

    final class ProbeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            var ancestor: NSView? = superview
            while let view = ancestor {
                if let table = view as? NSTableView {
                    if table.draggingDestinationFeedbackStyle != .none {
                        table.draggingDestinationFeedbackStyle = .none
                    }
                    return
                }
                ancestor = view.superview
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

extension View {
    /// SwiftUI doesn't report a cancelled drag, so watch for the mouse button coming up instead.
    /// Two released readings in a row give a drop on a row time to commit first.
    func onDragRelease(isDragging: Bool, perform action: @escaping () -> Void) -> some View {
        task(id: isDragging) {
            guard isDragging else { return }
            var releasedReadings: Int = 0
            while !_Concurrency.Task.isCancelled {
                try? await _Concurrency.Task.sleep(for: .milliseconds(100))
                releasedReadings = NSEvent.pressedMouseButtons & 1 == 0 ? releasedReadings + 1 : 0
                if releasedReadings >= 2 {
                    logReorder("mouse released, ending drag")
                    action()
                    return
                }
            }
        }
    }
}
