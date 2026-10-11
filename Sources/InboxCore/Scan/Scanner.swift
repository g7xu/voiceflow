import Foundation

public struct ScanSettings: Sendable {
    public var inboxes: [URL]
    public var backfillDays: Int
    public var matchWindow: TimeInterval
    public var calendarIDs: Set<String>

    public init(inboxes: [URL], backfillDays: Int = 90, matchWindow: TimeInterval = 7200, calendarIDs: Set<String>) {
        self.inboxes = inboxes
        self.backfillDays = backfillDays
        self.matchWindow = matchWindow
        self.calendarIDs = calendarIDs
    }
}

public struct ScanReport: Sendable {
    public var added = 0
    public var retracked = 0
    public var done: [Item.DoneReason: Int] = [:]
    /// Inbox path → why it couldn't be listed. Nothing in these folders was marked done.
    public var folderErrors: [String: String] = [:]
    /// Why event fields were left as they were, when calendar matching was skipped.
    public var calendarSkipped: String?
    public var duration: TimeInterval = 0
}

/// Reconciles the inbox folders with the database (spec §6). The ground rule: a scan only marks
/// an item done on positive evidence that it left. Anything it couldn't observe stays as it was.
public final class Scanner: Sendable {
    private let store: ItemStore
    private let lister: any DirectoryLister
    private let metadata: any MetadataReading
    private let bookmarks: any BookmarkResolving
    private let calendar: (any CalendarSource)?
    private let trashRoots: [URL]
    private let now: @Sendable () -> Date

    public init(store: ItemStore, lister: any DirectoryLister = LiveDirectoryLister(),
                metadata: any MetadataReading = LiveMetadataReader(),
                bookmarks: any BookmarkResolving = LiveBookmarks(), calendar: (any CalendarSource)?,
                trashRoots: [URL] = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")],
                now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.lister = lister
        self.metadata = metadata
        self.bookmarks = bookmarks
        self.calendar = calendar
        self.trashRoots = trashRoots
        self.now = now
    }

    public func scan(_ settings: ScanSettings) throws -> ScanReport {
        let started = Date()
        let now = now()
        var report = ScanReport()

        // Phase 1: observe. Only a successful listing is evidence about what's absent.
        var present: [FileIdentity: (url: URL, raw: RawMetadata)] = [:]
        var failedRoots = Set<String>()
        var unreadablePaths = Set<String>()
        for inbox in settings.inboxes {
            do {
                for url in try lister.list(inbox) {
                    do {
                        let raw = try metadata.read(url)
                        present[raw.identity] = (url, raw)
                    } catch {
                        unreadablePaths.insert(url.path)
                    }
                }
            } catch {
                failedRoots.insert(Paths.canonicalDirectory(inbox))
                report.folderErrors[inbox.path] = error.localizedDescription
            }
        }

        let existing = try store.items()
        let backfillStart = now.addingTimeInterval(-Double(settings.backfillDays) * 86_400)
        let matcher = makeMatcher(settings, existing: existing, from: backfillStart, to: now, report: &report)

        // Phase 2: reconcile items that are present.
        var changes: [Item] = []
        var seen = Set<FileIdentity>()
        for original in existing {
            seen.insert(original.identity)
            guard let entry = present[original.identity] else { continue }
            var item = original
            if item.status == .done {
                if item.doneReason == .manual { continue }
                item.status = .tracked
                item.doneReason = nil
                item.currentPath = nil
                item.statusAt = now
                report.retracked += 1
            }
            item.inboxPath = entry.url.path
            item.isDirectory = entry.raw.isDirectory
            if item.bookmark == nil { item.bookmark = bookmarks.create(entry.url) }
            if let matcher { Self.applyMatch(matcher, to: &item) }
            if item != original { changes.append(item) }
        }
        for (identity, entry) in present where !seen.contains(identity) {
            let addedAt = entry.raw.addedAt ?? now
            guard addedAt >= backfillStart else { continue }
            var item = Item(identity: identity, isDirectory: entry.raw.isDirectory, bookmark: bookmarks.create(entry.url),
                            inboxPath: entry.url.path, addedAt: addedAt, provenance: MetadataParsing.provenance(entry.raw),
                            firstSeenAt: now, statusAt: now)
            if let matcher { Self.applyMatch(matcher, to: &item) }
            changes.append(item)
            report.added += 1
        }

        // Phase 3: tracked items a successful listing no longer shows.
        let classifier = DepartureClassifier(metadata: metadata, bookmarks: bookmarks, trashRoots: trashRoots,
                                             inboxRoots: settings.inboxes, someInboxUnreadable: !failedRoots.isEmpty)
        let configuredRoots = Set(settings.inboxes.map(Paths.canonicalDirectory))
        for var item in existing where item.status == .tracked && present[item.identity] == nil {
            let root = Paths.canonicalDirectory(URL(fileURLWithPath: item.inboxPath).deletingLastPathComponent())
            guard configuredRoots.contains(root), !failedRoots.contains(root),
                  !unreadablePaths.contains(item.inboxPath) else { continue }
            guard case let .done(reason, currentPath) = classifier.classify(item) else { continue }
            item.status = .done
            item.doneReason = reason
            item.currentPath = currentPath
            item.statusAt = now
            changes.append(item)
            report.done[reason, default: 0] += 1
        }

        try store.save(changes)
        report.duration = Date().timeIntervalSince(started)
        return report
    }

    /// nil (with the reason recorded) when matching would have to run blind. Event fields are then
    /// kept, since clearing them destroys context that can't be rebuilt.
    private func makeMatcher(_ settings: ScanSettings, existing: [Item], from backfillStart: Date, to now: Date,
                             report: inout ScanReport) -> EventMatcher? {
        guard let calendar else {
            report.calendarSkipped = "calendar disabled"
            return nil
        }
        guard calendar.hasFullAccess else {
            report.calendarSkipped = "no calendar access"
            return nil
        }
        let available = Set(calendar.calendars().map(\.id)).intersection(settings.calendarIDs)
        guard !available.isEmpty else {
            report.calendarSkipped = "none of the selected calendars exist"
            return nil
        }
        let oldestTracked = existing.filter { $0.status == .tracked }.map(\.addedAt).min() ?? backfillStart
        let start = min(oldestTracked, backfillStart).addingTimeInterval(-settings.matchWindow - 86_400)
        return EventMatcher(events: calendar.events(from: start, to: now, calendarIDs: available),
                            window: settings.matchWindow)
    }

    private static func applyMatch(_ matcher: EventMatcher, to item: inout Item) {
        item.event = matcher.match(at: item.addedAt)
        item.dayEvents = matcher.dayEvents(at: item.addedAt)
    }
}
