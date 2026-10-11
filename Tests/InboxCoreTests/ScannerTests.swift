import Foundation
import Testing
@testable import InboxCore

final class FakeCalendar: CalendarSource, @unchecked Sendable {
    var hasFullAccess = true
    var available: [CalendarInfo] = [CalendarInfo(id: "cal", title: "School", sourceTitle: "Google", isBackground: false)]
    var stored: [CalendarEvent] = []

    func requestAccess() async throws -> Bool { hasFullAccess }
    func calendars() -> [CalendarInfo] { available }
    func events(from start: Date, to end: Date, calendarIDs: Set<String>) -> [CalendarEvent] {
        stored.filter { $0.end >= start && $0.start <= end }
    }
}

struct ThrowingLister: DirectoryLister {
    func list(_ folder: URL) throws -> [URL] { throw CocoaError(.fileReadNoPermission) }
}

/// Lists every folder normally except one, which fails as if its access were revoked.
struct OneFolderUnreadable: DirectoryLister {
    let unreadable: URL

    func list(_ folder: URL) throws -> [URL] {
        if folder.standardizedFileURL == unreadable.standardizedFileURL { throw CocoaError(.fileReadNoPermission) }
        return try LiveDirectoryLister().list(folder)
    }
}

/// What revoked folder access looks like to the classifier: nothing resolves.
struct UnresolvableBookmarks: BookmarkResolving {
    func create(_ url: URL) -> Data? { nil }
    func resolve(_ data: Data) -> URL? { nil }
}

/// Live metadata with knobs: fail for some names, or pretend a different date added.
struct TweakedMetadata: MetadataReading {
    var failing: Set<String> = []
    var addedAt: Date?

    func read(_ url: URL) throws -> RawMetadata {
        if failing.contains(url.lastPathComponent) { throw CocoaError(.fileReadUnknown) }
        var raw = try LiveMetadataReader().read(url)
        if let addedAt { raw.addedAt = addedAt }
        return raw
    }

    func identity(of url: URL) throws -> FileIdentity { try LiveMetadataReader().identity(of: url) }
}

/// An inbox, a Trash and an "elsewhere" folder in one temp directory, plus an in-memory store.
final class Fixture {
    let tmp: TempDir
    let inbox: URL
    let trash: URL
    let elsewhere: URL
    let store: ItemStore
    let calendar = FakeCalendar()

    init() throws {
        tmp = try TempDir()
        inbox = try tmp.dir("Downloads")
        trash = try tmp.dir("Trash")
        elsewhere = try tmp.dir("Documents")
        store = try ItemStore.inMemory()
    }

    var settings: ScanSettings { ScanSettings(inboxes: [inbox], calendarIDs: ["cal"]) }

    @discardableResult
    func scan(lister: any DirectoryLister = LiveDirectoryLister(), metadata: any MetadataReading = LiveMetadataReader(),
              bookmarks: any BookmarkResolving = LiveBookmarks(), calendar: (any CalendarSource)? = nil,
              settings: ScanSettings? = nil) throws -> ScanReport {
        try Scanner(store: store, lister: lister, metadata: metadata, bookmarks: bookmarks,
                    calendar: calendar ?? self.calendar, trashRoots: [trash]).scan(settings ?? self.settings)
    }

    @discardableResult
    func add(_ name: String) throws -> URL {
        try tmp.file("Downloads/\(name)")
    }

    func move(_ name: String, to folder: URL, as newName: String? = nil) throws {
        try FileManager.default.moveItem(at: inbox.appendingPathComponent(name),
                                         to: folder.appendingPathComponent(newName ?? name))
    }

    func item(named name: String) throws -> Item? {
        try store.items().first { $0.name == name }
    }
}

@Suite struct ScannerTests {
    @Test func firstScanAddsAndSecondScanIsQuiet() throws {
        let f = try Fixture()
        try f.add("a.pdf")
        try f.add("Screenshot.png")
        let first = try f.scan()
        #expect(first.added == 2)
        let second = try f.scan()
        #expect(second.added == 0)
        #expect(second.done.isEmpty)
        #expect(try f.store.items(status: .tracked).count == 2)
    }

    @Test func movedIntoSubfolderIsMovedWithNewPath() throws {
        let f = try Fixture()
        try f.add("a.pdf")
        try f.scan()
        let sub = try f.tmp.dir("Downloads/School")
        try f.move("a.pdf", to: sub)
        let report = try f.scan()
        #expect(report.done == [.moved: 1])
        let item = try #require(try f.item(named: "a.pdf"))
        #expect(item.status == .done)
        #expect(item.currentPath?.hasSuffix("/Downloads/School/a.pdf") == true)
    }

    @Test func movedElsewhereIsMoved() throws {
        let f = try Fixture()
        try f.add("a.pdf")
        try f.scan()
        try f.move("a.pdf", to: f.elsewhere, as: "Lecture 5.pdf")
        #expect(try f.scan().done == [.moved: 1])
        #expect(try f.item(named: "a.pdf")?.currentPath?.hasSuffix("/Documents/Lecture 5.pdf") == true)
    }

    @Test func trashedIsTrashed() throws {
        let f = try Fixture()
        try f.add("a.pdf")
        try f.scan()
        try f.move("a.pdf", to: f.trash)
        #expect(try f.scan().done == [.trashed: 1])
    }

    @Test func deletedIsGone() throws {
        let f = try Fixture()
        let file = try f.add("a.pdf")
        try f.scan()
        try FileManager.default.removeItem(at: file)
        #expect(try f.scan().done == [.gone: 1])
        #expect(try f.item(named: "a.pdf")?.currentPath == nil)
    }

    @Test func replacementUnderTheSameNameIsANewItem() throws {
        let f = try Fixture()
        try f.add("a.pdf")
        try f.scan()
        try f.move("a.pdf", to: f.elsewhere)
        try f.add("a.pdf")
        let report = try f.scan()
        #expect(report.added == 1)
        #expect(report.done.values.reduce(0, +) == 1)
        let rows = try f.store.items().filter { $0.name == "a.pdf" }
        #expect(rows.count == 2)
        #expect(rows.filter { $0.status == .tracked }.count == 1)
    }

    @Test func renameInPlaceKeepsTheRow() throws {
        let f = try Fixture()
        try f.add("document (3).pdf")
        try f.scan()
        let id = try f.item(named: "document (3).pdf")?.id
        try f.move("document (3).pdf", to: f.inbox, as: "lease.pdf")
        let report = try f.scan()
        #expect(report.added == 0)
        #expect(report.done.isEmpty)
        #expect(try f.item(named: "lease.pdf")?.id == id)
    }

    @Test func listingFailureMarksNothingDone() throws {
        let f = try Fixture()
        try f.add("a.pdf")
        try f.scan()
        let report = try f.scan(lister: ThrowingLister(), bookmarks: UnresolvableBookmarks())
        #expect(report.done.isEmpty)
        #expect(report.folderErrors.count == 1)
        #expect(try f.store.items(status: .tracked).count == 1)
    }

    @Test func unreadableEntryIsNotMarkedDone() throws {
        let f = try Fixture()
        try f.add("a.pdf")
        try f.scan()
        let report = try f.scan(metadata: TweakedMetadata(failing: ["a.pdf"]), bookmarks: UnresolvableBookmarks())
        #expect(report.done.isEmpty)
        #expect(try f.item(named: "a.pdf")?.status == .tracked)
    }

    @Test func fileMovedIntoAnUnreadableInboxStaysTracked() throws {
        let f = try Fixture()
        let desktop = try f.tmp.dir("Desktop")
        let shot = try f.tmp.file("Desktop/shot.png")
        let both = ScanSettings(inboxes: [f.inbox, desktop], calendarIDs: ["cal"])
        try f.scan(settings: both)
        try FileManager.default.moveItem(at: shot, to: f.inbox.appendingPathComponent("shot.png"))
        let report = try f.scan(lister: OneFolderUnreadable(unreadable: f.inbox), bookmarks: UnresolvableBookmarks(),
                                settings: both)
        #expect(report.done.isEmpty)
        #expect(try f.item(named: "shot.png")?.status == .tracked)
    }

    @Test func unfollowableFileIsGoneWhenEveryInboxListed() throws {
        let f = try Fixture()
        try f.add("a.pdf")
        try f.scan()
        try f.move("a.pdf", to: f.elsewhere)
        #expect(try f.scan(bookmarks: UnresolvableBookmarks()).done == [.gone: 1])
    }

    @Test func itemsOfARemovedInboxAreLeftAlone() throws {
        let f = try Fixture()
        let desktop = try f.tmp.dir("Desktop")
        try f.tmp.file("Desktop/shot.png")
        try f.scan(settings: ScanSettings(inboxes: [f.inbox, desktop], calendarIDs: ["cal"]))
        let report = try f.scan()
        #expect(report.done.isEmpty)
        #expect(try f.item(named: "shot.png")?.status == .tracked)
    }

    @Test func manualDoneNeverRetracks() throws {
        let f = try Fixture()
        try f.add("keep-here.pdf")
        try f.scan()
        let id = try #require(try f.item(named: "keep-here.pdf")?.id)
        try f.store.markDone(ids: [id], reason: .manual, at: Date())
        let report = try f.scan()
        #expect(report.retracked == 0)
        #expect(try f.item(named: "keep-here.pdf")?.doneReason == .manual)
    }

    @Test func movedBackRetracksAndKeepsOriginalContext() throws {
        let f = try Fixture()
        try f.add("a.pdf")
        try f.scan()
        let original = try #require(try f.item(named: "a.pdf"))
        try f.move("a.pdf", to: f.elsewhere)
        try f.scan()
        try FileManager.default.moveItem(at: f.elsewhere.appendingPathComponent("a.pdf"),
                                         to: f.inbox.appendingPathComponent("a.pdf"))
        let report = try f.scan()
        #expect(report.retracked == 1)
        let item = try #require(try f.item(named: "a.pdf"))
        #expect(item.status == .tracked)
        #expect(item.doneReason == nil)
        #expect(item.currentPath == nil)
        #expect(item.addedAt == original.addedAt)
        #expect(item.id == original.id)
    }

    @Test func itemsOlderThanTheBackfillWindowAreIgnored() throws {
        let f = try Fixture()
        try f.add("old.pdf")
        let report = try f.scan(metadata: TweakedMetadata(addedAt: Date().addingTimeInterval(-91 * 86_400)))
        #expect(report.added == 0)
    }

    @Test func provenanceIsRecordedOnInsert() throws {
        let f = try Fixture()
        let file = try f.add("lec05.pdf")
        try setXAttr(file, "com.apple.quarantine", Data("0081;6ac9778d;Chrome;E0FE4E62-2ACD-4FB2-B032-24C3CBD0791B".utf8))
        try f.scan()
        #expect(try f.item(named: "lec05.pdf")?.provenance.savedBy == "Chrome")
        #expect(try f.item(named: "lec05.pdf")?.bookmark != nil)
    }
}

@Suite struct ScannerCalendarTests {
    let now = Date()

    func lecture(around t: Date) -> CalendarEvent {
        CalendarEvent(title: "Lecture", start: t.addingTimeInterval(-1800), end: t.addingTimeInterval(1800),
                      calendarTitle: "School")
    }

    @Test func matchesOnInsert() throws {
        let f = try Fixture()
        f.calendar.stored = [lecture(around: now)]
        try f.add("lec05.pdf")
        try f.scan()
        #expect(try f.item(named: "lec05.pdf")?.event?.title == "Lecture")
    }

    @Test func rematchesWhenEventsSyncLate() throws {
        let f = try Fixture()
        try f.add("lec05.pdf")
        try f.scan()
        #expect(try f.item(named: "lec05.pdf")?.event == nil)
        f.calendar.stored = [lecture(around: now)]
        try f.scan()
        #expect(try f.item(named: "lec05.pdf")?.event?.kind == .during)
    }

    @Test func lostAccessKeepsEventFields() throws {
        let f = try Fixture()
        f.calendar.stored = [lecture(around: now)]
        try f.add("lec05.pdf")
        try f.scan()
        f.calendar.hasFullAccess = false
        let report = try f.scan()
        #expect(report.calendarSkipped != nil)
        #expect(try f.item(named: "lec05.pdf")?.event?.title == "Lecture")
    }

    @Test func vanishedCalendarsKeepEventFields() throws {
        let f = try Fixture()
        f.calendar.stored = [lecture(around: now)]
        try f.add("lec05.pdf")
        try f.scan()
        f.calendar.available = [CalendarInfo(id: "other", title: "Home", sourceTitle: "iCloud", isBackground: false)]
        let report = try f.scan()
        #expect(report.calendarSkipped != nil)
        #expect(try f.item(named: "lec05.pdf")?.event?.title == "Lecture")
    }

    @Test func noCalendarSourceKeepsEventFields() throws {
        let f = try Fixture()
        f.calendar.stored = [lecture(around: now)]
        try f.add("lec05.pdf")
        try f.scan()
        let report = try Scanner(store: f.store, calendar: nil, trashRoots: [f.trash]).scan(f.settings)
        #expect(report.calendarSkipped != nil)
        #expect(try f.item(named: "lec05.pdf")?.event?.title == "Lecture")
    }
}
