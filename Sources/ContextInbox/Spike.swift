@preconcurrency import EventKit
import Foundation
import InboxCore

/// M0 checks that the "rebuild context after the fact" premise holds on this Mac. Output is
/// tab-separated so it can be diffed against `mdls`, `stat` and `xattr` run from Terminal.
enum Spike {
    static func run(_ args: [String]) async throws {
        switch args.first {
        case "metadata":
            try metadata(count: args.dropFirst().first.flatMap(Int.init) ?? 10)
        case "calendar":
            try await calendar()
        case "bookmark-create":
            guard let path = args.dropFirst().first else { throw SpikeError.usage }
            try bookmarkCreate(path)
        case "bookmark-resolve":
            try bookmarkResolve()
        default:
            throw SpikeError.usage
        }
    }

    enum SpikeError: Error, CustomStringConvertible {
        case usage
        case noBookmark

        var description: String {
            switch self {
            case .usage: "usage: --spike metadata [N] | calendar | bookmark-create PATH | bookmark-resolve"
            case .noBookmark: "run bookmark-create first"
            }
        }
    }

    /// name, added (unix s), inode, http(s) WhereFroms count, raw quarantine — newest N in Downloads.
    static func metadata(count: Int) throws {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let reader = LiveMetadataReader()
        let urls = try FileManager.default.contentsOfDirectory(
            at: downloads, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        let rows = urls.compactMap { url in (try? reader.read(url)).map { (url, $0) } }
            .sorted { ($0.1.addedAt ?? .distantPast) > ($1.1.addedAt ?? .distantPast) }
            .prefix(count)
        print("listed \(urls.count) entries, read \(rows.count)")
        for (url, meta) in rows {
            let origins = meta.whereFroms.map(MetadataParsing.webOrigins)
            let webCount = [origins?.source, origins?.referrer].compactMap { $0 }.count
            let added = meta.addedAt.map { String(Int($0.timeIntervalSince1970)) } ?? "-"
            print([url.lastPathComponent, added, String(meta.identity.inode), String(webCount),
                   meta.quarantine ?? "-"].map(Printable.escape).joined(separator: "\t"))
        }
    }

    /// Event counts per calendar in 30-day buckets going back about a year, newest bucket first.
    /// Prints counts only, never event titles.
    static func calendar() async throws {
        let store = EKEventStore()
        print("status before: \(EKEventStore.authorizationStatus(for: .event).rawValue)")
        let granted = try await store.requestFullAccessToEvents()
        print("full access: \(granted)")
        guard granted else { return }

        let now = Date()
        let day: TimeInterval = 86_400
        for source in store.sources.sorted(by: { $0.title < $1.title }) {
            let calendars = source.calendars(for: .event).sorted { $0.title < $1.title }
            guard !calendars.isEmpty else { continue }
            print("source: \(Printable.escape(source.title)) (type \(source.sourceType.rawValue))")
            for calendar in calendars {
                var buckets: [Int] = []
                var oldest: Date?
                for i in 0..<13 {
                    let end = now.addingTimeInterval(-Double(i) * 30 * day)
                    let start = end.addingTimeInterval(-30 * day)
                    let events = store.events(matching: store.predicateForEvents(withStart: start, end: end,
                                                                                  calendars: [calendar]))
                    buckets.append(events.count)
                    if let first = events.map(\.startDate).min() { oldest = min(oldest ?? first, first) }
                }
                let oldestText = oldest.map { ISO8601DateFormatter().string(from: $0) } ?? "-"
                print("  \(Printable.escape(calendar.title)) (type \(calendar.type.rawValue)): "
                      + buckets.map(String.init).joined(separator: " ") + "  oldest \(oldestText)")
            }
        }
    }

    private static var bookmarkFile: URL { AppPaths.live().root.appendingPathComponent("spike-bookmark.plist") }

    static func bookmarkCreate(_ path: String) throws {
        let url = URL(fileURLWithPath: path)
        let identity = try LiveMetadataReader().identity(of: url)
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        try AppPaths.live().ensureExists()
        let record: [String: Any] = ["bookmark": data, "path": path,
                                     "volume": identity.volumeUUID, "inode": Int64(identity.inode)]
        try PropertyListSerialization.data(fromPropertyList: record, format: .binary, options: 0)
            .write(to: bookmarkFile)
        print("saved bookmark for \(Printable.escape(path)) inode \(identity.inode)")
    }

    static func bookmarkResolve() throws {
        guard let data = try? Data(contentsOf: bookmarkFile),
              let record = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bookmark = record["bookmark"] as? Data
        else { throw SpikeError.noBookmark }
        print("created for: \(Printable.escape(record["path"] as? String ?? "?")) inode \(record["inode"] ?? "?")")
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            let identity = try? LiveMetadataReader().identity(of: url)
            let same = identity.map { $0.inode == UInt64(record["inode"] as? Int64 ?? -1) } ?? false
            print("resolved: \(Printable.escape(url.path))\nstale: \(stale)\ninode now: \(identity.map { String($0.inode) } ?? "-")"
                  + "\nsame file: \(same)")
        } catch {
            print("resolve failed: \(error.localizedDescription)")
        }
    }
}
