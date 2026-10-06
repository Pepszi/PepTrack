import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct RowDrag: Codable, Transferable {
    enum Kind: String, Codable {
        case task
        case folder
    }

    var kind: Kind
    var idData: Data

    init(kind: Kind, id: PersistentIdentifier) {
        self.kind = kind
        self.idData = (try? JSONEncoder().encode(id)) ?? Data()
    }

    var persistentID: PersistentIdentifier? {
        try? JSONDecoder().decode(PersistentIdentifier.self, from: idData)
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}
