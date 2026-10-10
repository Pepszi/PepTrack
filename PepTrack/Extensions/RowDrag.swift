import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let peptrackRow = UTType(exportedAs: "com.peptrack.row")
}

nonisolated struct RowDrag: Codable, Transferable, Identifiable {
    enum Kind: String, Codable {
        case task
        case folder
        case client
    }

    var kind: Kind
    var id: PersistentIdentifier

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .peptrackRow)
    }
}
