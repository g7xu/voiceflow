import Foundation
import GRDB

public enum StoreError: Error, CustomStringConvertible {
    case corrupt(column: String, value: String)

    public var description: String {
        switch self {
        case let .corrupt(column, value): "unexpected value \(value) in column \(column)"
        }
    }
}

public final class ItemStore: Sendable {
    private let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// A DatabasePool runs in WAL mode, so a v2 CLI can read while the app writes.
    public static func open(at url: URL) throws -> ItemStore {
        try ItemStore(writer: DatabasePool(path: url.path))
    }

    public static func inMemory() throws -> ItemStore {
        try ItemStore(writer: DatabaseQueue())
    }

    public func items(status: Item.Status? = nil) throws -> [Item] {
        try writer.read { db in
            var request = Item.order(Column("added_at").desc)
            if let status { request = request.filter(Column("status") == status.rawValue) }
            return try request.fetchAll(db)
        }
    }

    /// Inserts items without an id and updates the rest, all in one transaction. Returns them with ids.
    @discardableResult
    public func save(_ items: [Item]) throws -> [Item] {
        try writer.write { db in
            try items.map { item in
                var saved = item
                if saved.id == nil { try saved.insert(db) } else { try saved.update(db) }
                return saved
            }
        }
    }

    /// Marks tracked items done; items already done keep their original reason. Returns how many
    /// changed.
    @discardableResult
    public func markDone(ids: [Int64], reason: Item.DoneReason, at date: Date) throws -> Int {
        try writer.write { db in
            try Item.filter(ids.contains(Column("id")) && Column("status") == Item.Status.tracked.rawValue)
                .updateAll(db, Column("status").set(to: Item.Status.done.rawValue),
                           Column("done_reason").set(to: reason.rawValue),
                           Column("status_at").set(to: date))
        }
    }

    /// Undoes `markDone(reason: .manual)`. Items done for other reasons are left alone: the next
    /// scan would only mark them done again.
    @discardableResult
    public func trackAgain(ids: [Int64], at date: Date) throws -> Int {
        try writer.write { db in
            try Item.filter(ids.contains(Column("id")) && Column("done_reason") == Item.DoneReason.manual.rawValue)
                .updateAll(db, Column("status").set(to: Item.Status.tracked.rawValue),
                           Column("done_reason").set(to: nil),
                           Column("status_at").set(to: date))
        }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "item") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("volume_uuid", .text).notNull()
                t.column("inode", .integer).notNull()
                t.column("is_dir", .boolean).notNull()
                t.column("bookmark", .blob)
                t.column("inbox_path", .text).notNull()
                t.column("current_path", .text)
                t.column("added_at", .datetime).notNull()
                t.column("source_url", .text)
                t.column("referrer_url", .text)
                t.column("saved_by", .text)
                t.column("event_title", .text)
                t.column("event_start", .datetime)
                t.column("event_end", .datetime)
                t.column("event_location", .text)
                t.column("event_calendar", .text)
                t.column("event_match", .text).check { ["during", "after"].contains($0) }
                t.column("day_events", .text).notNull().defaults(to: "[]")
                t.column("status", .text).notNull().check { ["tracked", "done"].contains($0) }
                t.column("done_reason", .text).check { ["moved", "trashed", "gone", "manual"].contains($0) }
                t.column("first_seen_at", .datetime).notNull()
                t.column("status_at", .datetime).notNull()
                t.uniqueKey(["volume_uuid", "inode"])
                t.check(sql: "(status = 'done') = (done_reason IS NOT NULL)")
            }
        }
        return migrator
    }
}

extension Item: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "item"

    public init(row: Row) throws {
        let statusText: String = row["status"]
        guard let status = Status(rawValue: statusText) else { throw StoreError.corrupt(column: "status", value: statusText) }
        let reasonText: String? = row["done_reason"]
        let doneReason = try reasonText.map { text in
            guard let reason = DoneReason(rawValue: text) else { throw StoreError.corrupt(column: "done_reason", value: text) }
            return reason
        }
        let dayEventsJSON: String = row["day_events"]
        let event: EventMatch? = try (row["event_title"] as String?).map { title in
            let kindText: String = row["event_match"]
            guard let kind = EventMatch.Kind(rawValue: kindText) else {
                throw StoreError.corrupt(column: "event_match", value: kindText)
            }
            return EventMatch(title: title, start: row["event_start"], end: row["event_end"],
                              location: row["event_location"], calendarTitle: row["event_calendar"], kind: kind)
        }
        self.init(
            id: row["id"],
            identity: FileIdentity(volumeUUID: row["volume_uuid"], inode: UInt64(bitPattern: row["inode"])),
            isDirectory: row["is_dir"],
            bookmark: row["bookmark"],
            inboxPath: row["inbox_path"],
            currentPath: row["current_path"],
            addedAt: row["added_at"],
            provenance: Provenance(sourceURL: row["source_url"], referrerURL: row["referrer_url"], savedBy: row["saved_by"]),
            event: event,
            dayEvents: try JSONDecoder().decode([String].self, from: Data(dayEventsJSON.utf8)),
            status: status,
            doneReason: doneReason,
            firstSeenAt: row["first_seen_at"],
            statusAt: row["status_at"]
        )
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["volume_uuid"] = identity.volumeUUID
        container["inode"] = Int64(bitPattern: identity.inode)
        container["is_dir"] = isDirectory
        container["bookmark"] = bookmark
        container["inbox_path"] = inboxPath
        container["current_path"] = currentPath
        container["added_at"] = addedAt
        container["source_url"] = provenance.sourceURL
        container["referrer_url"] = provenance.referrerURL
        container["saved_by"] = provenance.savedBy
        container["event_title"] = event?.title
        container["event_start"] = event?.start
        container["event_end"] = event?.end
        container["event_location"] = event?.location
        container["event_calendar"] = event?.calendarTitle
        container["event_match"] = event?.kind.rawValue
        container["day_events"] = String(decoding: try JSONEncoder().encode(dayEvents), as: UTF8.self)
        container["status"] = status.rawValue
        container["done_reason"] = doneReason?.rawValue
        container["first_seen_at"] = firstSeenAt
        container["status_at"] = statusAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
