import Foundation
import Testing
@testable import InboxCore

/// Whole seconds: the store keeps millisecond precision, and these values must round-trip exactly.
private let t0 = Date(timeIntervalSince1970: 1_791_600_000)

func sampleItem(inode: UInt64 = 1, path: String = "/Users/you/Downloads/a.pdf") -> Item {
    Item(identity: FileIdentity(volumeUUID: "VOL", inode: inode), isDirectory: false, bookmark: Data([1, 2, 3]),
         inboxPath: path, addedAt: t0,
         provenance: Provenance(sourceURL: "https://cdn.example.com/a", referrerURL: "https://canvas.example.edu/c",
                                savedBy: "Chrome"),
         event: EventMatch(title: "Lecture", start: t0.addingTimeInterval(-600), end: t0.addingTimeInterval(3000),
                           location: "Center Hall 105", calendarTitle: "School", kind: .during),
         dayEvents: ["Career Fair"], firstSeenAt: t0, statusAt: t0)
}

@Suite struct StoreTests {
    @Test func roundTripsEveryField() throws {
        let store = try ItemStore.inMemory()
        let saved = try store.save([sampleItem()])
        #expect(saved[0].id != nil)
        #expect(try store.items() == saved)
    }

    @Test func roundTripsItemWithoutOptionalFields() throws {
        let store = try ItemStore.inMemory()
        var item = sampleItem()
        item.bookmark = nil
        item.event = nil
        item.dayEvents = []
        item.provenance = Provenance()
        let saved = try store.save([item])
        #expect(try store.items() == saved)
    }

    @Test func largeInodesRoundTrip() throws {
        let store = try ItemStore.inMemory()
        let saved = try store.save([sampleItem(inode: UInt64.max - 1)])
        #expect(try store.items().first?.identity.inode == UInt64.max - 1)
        #expect(saved.count == 1)
    }

    @Test func identityIsUnique() throws {
        let store = try ItemStore.inMemory()
        try store.save([sampleItem()])
        #expect(throws: (any Error).self) { try store.save([sampleItem(path: "/elsewhere/a.pdf")]) }
    }

    @Test func doneRequiresReasonAndTrackedForbidsIt() throws {
        let store = try ItemStore.inMemory()
        var done = sampleItem(inode: 1)
        done.status = .done
        #expect(throws: (any Error).self) { try store.save([done]) }
        var tracked = sampleItem(inode: 2)
        tracked.doneReason = .moved
        #expect(throws: (any Error).self) { try store.save([tracked]) }
    }

    @Test func markDoneOnlyTouchesTrackedItems() throws {
        let store = try ItemStore.inMemory()
        var moved = sampleItem(inode: 2)
        moved.status = .done
        moved.doneReason = .moved
        let saved = try store.save([sampleItem(inode: 1), moved])
        let later = t0.addingTimeInterval(60)
        #expect(try store.markDone(ids: saved.compactMap(\.id), reason: .manual, at: later) == 1)
        let byInode = Dictionary(uniqueKeysWithValues: try store.items().map { ($0.identity.inode, $0) })
        #expect(byInode[1]?.doneReason == .manual)
        #expect(byInode[1]?.statusAt == later)
        #expect(byInode[2]?.doneReason == .moved)
    }

    @Test func trackAgainOnlyUndoesManualDone() throws {
        let store = try ItemStore.inMemory()
        var moved = sampleItem(inode: 2)
        moved.status = .done
        moved.doneReason = .moved
        let saved = try store.save([sampleItem(inode: 1), moved])
        let ids = saved.compactMap(\.id)
        try store.markDone(ids: ids, reason: .manual, at: t0)
        #expect(try store.trackAgain(ids: ids, at: t0) == 1)
        let byInode = Dictionary(uniqueKeysWithValues: try store.items().map { ($0.identity.inode, $0) })
        #expect(byInode[1]?.status == .tracked)
        #expect(byInode[1]?.doneReason == nil)
        #expect(byInode[2]?.doneReason == .moved)
    }

    @Test func filtersByStatus() throws {
        let store = try ItemStore.inMemory()
        var done = sampleItem(inode: 2)
        done.status = .done
        done.doneReason = .gone
        try store.save([sampleItem(inode: 1), done])
        #expect(try store.items(status: .tracked).map(\.identity.inode) == [1])
        #expect(try store.items(status: .done).map(\.identity.inode) == [2])
    }

    @Test func reopeningAFileDatabaseKeepsDataAndReRunsMigrationsSafely() throws {
        let tmp = try TempDir()
        let url = tmp.url.appendingPathComponent("items.sqlite")
        try ItemStore.open(at: url).save([sampleItem()])
        #expect(try ItemStore.open(at: url).items().count == 1)
    }
}
