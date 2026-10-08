import SwiftUI

#if os(macOS)
import AppKit
#endif

extension TaskStatus {
    var title: String {
        switch self {
        case .toDo: "To Do"
        case .inProgress: "In Progress"
        case .general: "General"
        case .blocked: "Blocked"
        case .review: "Review"
        case .completed: "Completed"
        }
    }

    var symbolName: String {
        switch self {
        case .toDo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .general: "circle.fill"
        case .blocked: "nosign"
        case .review: "eye"
        case .completed: "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .toDo: Color(red: 96 / 255, green: 96 / 255, blue: 96 / 255)
        case .inProgress: Color(red: 195 / 255, green: 101 / 255, blue: 34 / 255)
        case .general: Color(red: 92 / 255, green: 71 / 255, blue: 205 / 255)
        case .blocked: Color(red: 210 / 255, green: 31 / 255, blue: 36 / 255)
        case .review: Color(red: 255 / 255, green: 197 / 255, blue: 61 / 255)
        case .completed: Color(red: 43 / 255, green: 140 / 255, blue: 94 / 255)
        }
    }

    /// Colored status symbol for menus. Popup menus redraw template images in the label color,
    /// so this bakes in the same tint the task rows use.
    var menuIcon: Image {
        #if os(macOS)
        Image(nsImage: tintedMenuSymbol).renderingMode(.original)
        #else
        Image(systemName: symbolName)
        #endif
    }

    #if os(macOS)
    private var tintedMenuSymbol: NSImage {
        let color = NSColor(tint)
        let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) ?? NSImage()
        let symbol = base.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        ) ?? base
        let size = symbol.size == .zero ? NSSize(width: 13, height: 13) : symbol.size
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            rect.fill()
            symbol.draw(
                in: rect,
                from: NSRect(origin: .zero, size: symbol.size),
                operation: .destinationIn,
                fraction: 1
            )
            return true
        }
        image.isTemplate = false
        return image
    }
    #endif
}
