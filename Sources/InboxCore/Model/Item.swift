import Foundation

/// One row of the pointer database: a file or folder that arrived in an inbox.
public struct Item: Equatable, Sendable, Identifiable {
    public enum Status: String, Sendable {
        case tracked, done
    }

    public enum DoneReason: String, Sendable {
        case moved, trashed, gone, manual
    }

    /// nil until the item is first saved.
    public var id: Int64?
    public var identity: FileIdentity
    public var isDirectory: Bool
    /// Created at first sight; it can't be created once the file has left.
    public var bookmark: Data?
    /// Where the item was last seen in an inbox.
    public var inboxPath: String
    /// Where it went after leaving, when the bookmark could follow it.
    public var currentPath: String?
    /// Snapshot of the date added at first sight; macOS resets it when the file changes folder.
    public var addedAt: Date
    public var provenance: Provenance
    public var event: EventMatch?
    public var dayEvents: [String]
    public var status: Status
    /// Set exactly when `status == .done`.
    public var doneReason: DoneReason?
    public var firstSeenAt: Date
    public var statusAt: Date

    public init(id: Int64? = nil, identity: FileIdentity, isDirectory: Bool, bookmark: Data?, inboxPath: String,
                currentPath: String? = nil, addedAt: Date, provenance: Provenance, event: EventMatch? = nil,
                dayEvents: [String] = [], status: Status = .tracked, doneReason: DoneReason? = nil,
                firstSeenAt: Date, statusAt: Date) {
        self.id = id
        self.identity = identity
        self.isDirectory = isDirectory
        self.bookmark = bookmark
        self.inboxPath = inboxPath
        self.currentPath = currentPath
        self.addedAt = addedAt
        self.provenance = provenance
        self.event = event
        self.dayEvents = dayEvents
        self.status = status
        self.doneReason = doneReason
        self.firstSeenAt = firstSeenAt
        self.statusAt = statusAt
    }

    public var name: String { (inboxPath as NSString).lastPathComponent }
}
