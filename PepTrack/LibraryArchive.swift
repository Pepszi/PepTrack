import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let peptrackArchive = UTType(exportedAs: "com.peptrack.archive", conformingTo: .json)
}

struct LibraryArchive: Codable {
    static let formatID = "peptrack"
    static let currentVersion = 1

    var format: String
    var version: Int
    var exportedAt: Date
    var clients: [ClientRecord]

    struct ClientRecord: Codable {
        var name: String
        var createdAt: Date
        /// Optional so archives written before clients could be reordered still import.
        var sortIndex: Int?
        var groups: [GroupRecord]
    }

    struct GroupRecord: Codable {
        var name: String
        var createdAt: Date
        var sortIndex: Int
        var tasks: [TaskRecord]
    }

    struct TaskRecord: Codable {
        var title: String
        /// Plain-text task description. Optional so archives written before this field still import.
        var details: String?
        var status: TaskStatus
        var startDate: Date?
        var endDate: Date?
        var timeEstimateHours: Double
        var actualTimeTracked: TimeInterval
        var isTimerRunning: Bool
        var lastTimerStarted: Date?
        var budget: Double
        var isInvoiced: Bool
        var createdAt: Date
        var sortIndex: Int
        var timeEntries: [TimeEntryRecord]

        enum CodingKeys: String, CodingKey {
            case title
            case details = "description"
            case status
            case startDate
            case endDate
            case timeEstimateHours
            case actualTimeTracked
            case isTimerRunning
            case lastTimerStarted
            case budget
            case isInvoiced
            case createdAt
            case sortIndex
            case timeEntries
        }
    }

    struct TimeEntryRecord: Codable {
        var startedAt: Date
        var endedAt: Date?
        var note: String
        var createdAt: Date
    }

    static func suggestedFilename(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return "PepTrack \(formatter.string(from: date))"
    }

    static func snapshot(of context: ModelContext) -> LibraryArchive {
        let stored = (try? context.fetch(
            FetchDescriptor<ClientGroup>(sortBy: [
                SortDescriptor(\.sortIndex),
                SortDescriptor(\.createdAt)
            ])
        )) ?? []
        return LibraryArchive(
            format: formatID,
            version: currentVersion,
            exportedAt: .now,
            clients: stored.filter { !$0.isDeleted }.map { ClientRecord($0) }
        )
    }

    func encodedData() throws -> Data {
        try LibraryJSON.encoder.encode(self)
    }

    static func decode(from data: Data) throws -> LibraryArchive {
        let archive: LibraryArchive
        do {
            archive = try LibraryJSON.decoder.decode(LibraryArchive.self, from: data)
        } catch {
            throw LibraryArchiveError.invalid
        }
        guard archive.format == formatID else {
            throw LibraryArchiveError.invalid
        }
        guard archive.version > 0, archive.version <= currentVersion else {
            throw LibraryArchiveError.unsupportedVersion
        }
        return archive
    }

    func replaceContents(of context: ModelContext) throws {
        // SwiftData still writes undo snapshots inside save() whenever an undo
        // manager is attached, including after disableUndoRegistration().
        // Replacing every object in that state crashes with
        // "A snapshot should exist before creating a new snapshot for undo".
        let undoManager = context.undoManager
        undoManager?.removeAllActions()
        context.undoManager = nil
        defer {
            context.undoManager = undoManager
            undoManager?.removeAllActions()
        }

        do {
            let existing = try context.fetch(FetchDescriptor<ClientGroup>())
            for client in existing {
                context.delete(client)
            }
            for record in clients {
                insert(record, into: context)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func insert(_ record: ClientRecord, into context: ModelContext) {
        let client = ClientGroup(
            name: record.name,
            createdAt: record.createdAt,
            sortIndex: record.sortIndex ?? 0
        )
        context.insert(client)

        for groupRecord in record.groups {
            let group = SubGroup(
                name: groupRecord.name,
                clientGroup: client,
                createdAt: groupRecord.createdAt,
                sortIndex: groupRecord.sortIndex
            )
            context.insert(group)
            if !client.subGroups.contains(where: { $0 === group }) {
                client.subGroups.append(group)
            }

            for taskRecord in groupRecord.tasks {
                let task = Task(
                    title: taskRecord.title,
                    details: taskRecord.details ?? "",
                    status: taskRecord.status,
                    startDate: taskRecord.startDate,
                    endDate: taskRecord.endDate,
                    timeEstimateHours: taskRecord.timeEstimateHours,
                    actualTimeTracked: taskRecord.actualTimeTracked,
                    isTimerRunning: taskRecord.isTimerRunning,
                    lastTimerStarted: taskRecord.lastTimerStarted,
                    budget: taskRecord.budget,
                    isInvoiced: taskRecord.isInvoiced,
                    createdAt: taskRecord.createdAt,
                    sortIndex: taskRecord.sortIndex,
                    subGroup: group
                )
                context.insert(task)
                if !group.tasks.contains(where: { $0 === task }) {
                    group.tasks.append(task)
                }

                for entryRecord in taskRecord.timeEntries {
                    let entry = TimeEntry(
                        startedAt: entryRecord.startedAt,
                        endedAt: entryRecord.endedAt,
                        note: entryRecord.note,
                        createdAt: entryRecord.createdAt,
                        task: task
                    )
                    context.insert(entry)
                    if !task.timeEntries.contains(where: { $0 === entry }) {
                        task.timeEntries.append(entry)
                    }
                }

                if task.isTimerRunning, task.openTimeEntry == nil {
                    let start = task.lastTimerStarted ?? task.createdAt
                    let entry = TimeEntry(startedAt: start, createdAt: start, task: task)
                    context.insert(entry)
                    task.timeEntries.append(entry)
                    task.lastTimerStarted = start
                } else if task.isTimerRunning, task.lastTimerStarted == nil {
                    task.lastTimerStarted = task.openTimeEntry?.startedAt
                }

                task.refreshTrackedTotal()
            }
        }
    }
}

extension LibraryArchive.ClientRecord {
    init(_ client: ClientGroup) {
        name = client.name
        createdAt = client.createdAt
        sortIndex = client.sortIndex
        groups = client.orderedSubGroups
            .filter { !$0.isDeleted }
            .map { LibraryArchive.GroupRecord($0) }
    }
}

extension LibraryArchive.GroupRecord {
    init(_ group: SubGroup) {
        name = group.name
        createdAt = group.createdAt
        sortIndex = group.sortIndex
        tasks = group.orderedTasks
            .filter { !$0.isDeleted }
            .map { LibraryArchive.TaskRecord($0) }
    }
}

extension LibraryArchive.TaskRecord {
    init(_ task: Task) {
        title = task.title
        details = task.details
        status = task.status
        startDate = task.startDate
        endDate = task.endDate
        timeEstimateHours = task.timeEstimateHours
        actualTimeTracked = task.actualTimeTracked
        isTimerRunning = task.isTimerRunning
        lastTimerStarted = task.lastTimerStarted
        budget = task.budget
        isInvoiced = task.isInvoiced
        createdAt = task.createdAt
        sortIndex = task.sortIndex
        timeEntries = task.timeEntries
            .filter { !$0.isDeleted }
            .sorted { lhs, rhs in
                if lhs.startedAt != rhs.startedAt {
                    return lhs.startedAt < rhs.startedAt
                }
                return lhs.createdAt < rhs.createdAt
            }
            .map { LibraryArchive.TimeEntryRecord($0) }
    }
}

extension LibraryArchive.TimeEntryRecord {
    init(_ entry: TimeEntry) {
        startedAt = entry.startedAt
        endedAt = entry.endedAt
        note = entry.note
        createdAt = entry.createdAt
    }
}

enum LibraryArchiveError: LocalizedError {
    case unreadable
    case invalid
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "The file could not be read."
        case .invalid:
            "This file is not a PepTrack archive."
        case .unsupportedVersion:
            "This archive was created by a newer version of PepTrack."
        }
    }
}

private enum LibraryJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom(LibraryDate.encode)
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(LibraryDate.decode)
        return decoder
    }()
}

private nonisolated enum LibraryDate {
    static func encode(_ date: Date, encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string(from: date))
    }

    static func decode(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let date = date(from: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 date."
            )
        }
        return date
    }

    static func string(from date: Date) -> String {
        fractional.string(from: date)
    }

    static func date(from value: String) -> Date? {
        fractional.date(from: value) ?? wholeSeconds.date(from: value)
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let wholeSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

struct LibraryFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.peptrackArchive, .json]
    }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw LibraryArchiveError.unreadable
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct LibraryActions {
    var exportLibrary: () -> Void
    var importLibrary: () -> Void
}

private struct LibraryActionsKey: FocusedValueKey {
    typealias Value = LibraryActions
}

extension FocusedValues {
    var libraryActions: LibraryActions? {
        get { self[LibraryActionsKey.self] }
        set { self[LibraryActionsKey.self] = newValue }
    }
}

struct LibraryCommands: Commands {
    @FocusedValue(\.libraryActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Button("Export Library…") {
                actions?.exportLibrary()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(actions == nil)

            Button("Import Library…") {
                actions?.importLibrary()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(actions == nil)
        }
    }
}
