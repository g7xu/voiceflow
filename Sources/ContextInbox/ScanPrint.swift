import Foundation
import InboxCore

/// `--scan-print [--inbox PATH]... [--days N] [--no-calendar]`: inbox items as TSV (name, added,
/// kind, source, saved by, event, that day). Reads only; nothing is stored.
enum ScanPrint {
    static func run(_ args: [String]) throws {
        var inboxes: [URL] = []
        var days = 90
        var useCalendar = true
        var rest = args[...]
        while let flag = rest.popFirst() {
            switch flag {
            case "--inbox":
                guard let path = rest.popFirst() else { throw UsageError() }
                inboxes.append(URL(fileURLWithPath: path))
            case "--days":
                guard let n = rest.popFirst().flatMap({ Int($0) }) else { throw UsageError() }
                days = n
            case "--no-calendar":
                useCalendar = false
            default:
                throw UsageError()
            }
        }
        if inboxes.isEmpty {
            let home = FileManager.default.homeDirectoryForCurrentUser
            inboxes = [home.appendingPathComponent("Downloads"), home.appendingPathComponent("Desktop")]
        }

        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let matcher = useCalendar ? makeMatcher(from: cutoff) : nil
        let reader = LiveMetadataReader()
        let dateStyle = Date.ISO8601FormatStyle(timeZone: .current)
        for inbox in inboxes {
            let urls: [URL]
            let inboxPath = Printable.escape(inbox.path)
            do {
                urls = try LiveDirectoryLister().list(inbox)
            } catch {
                print("inbox \(inboxPath): can't list: \(error.localizedDescription)")
                continue
            }
            let read = urls.compactMap { url in (try? reader.read(url)).map { (url: url, raw: $0) } }
            let recent = read.filter { ($0.raw.addedAt ?? .distantPast) >= cutoff }
                .sorted { ($0.raw.addedAt ?? .distantPast) > ($1.raw.addedAt ?? .distantPast) }
            print("inbox \(inboxPath): \(urls.count) items, \(recent.count) added in the last \(days) days, "
                  + "\(urls.count - read.count) unreadable")
            for entry in recent {
                let provenance = MetadataParsing.provenance(entry.raw)
                let match = entry.raw.addedAt.flatMap { matcher?.match(at: $0) }
                let dayEvents = entry.raw.addedAt.map { matcher?.dayEvents(at: $0) ?? [] } ?? []
                print([
                    entry.url.lastPathComponent,
                    entry.raw.addedAt.map { $0.formatted(dateStyle) } ?? "-",
                    entry.raw.isDirectory ? "dir" : "file",
                    MetadataParsing.displaySource(source: provenance.sourceURL, referrer: provenance.referrerURL) ?? "-",
                    provenance.savedBy.map(MetadataParsing.displayAgent) ?? "-",
                    match.map { "\($0.kind.rawValue): \($0.title)" } ?? "-",
                    dayEvents.isEmpty ? "-" : dayEvents.joined(separator: "; "),
                ].map(Printable.escape).joined(separator: "\t"))
            }
        }
    }

    /// Matches against every calendar except birthdays and subscriptions, with the spec's 2 h window.
    private static func makeMatcher(from cutoff: Date) -> EventMatcher? {
        let source = EventKitCalendarSource()
        guard source.hasFullAccess else {
            print("calendar: no full access (grant it with --spike calendar)")
            return nil
        }
        let calendars = source.calendars().filter { !$0.isBackground }
        let window: TimeInterval = 2 * 3600
        let events = source.events(from: cutoff.addingTimeInterval(-window - 86_400), to: Date(),
                                   calendarIDs: Set(calendars.map(\.id)))
        print("calendar: \(calendars.count) calendars, \(events.count) events")
        return EventMatcher(events: events, window: window)
    }

    struct UsageError: Error, CustomStringConvertible {
        var description: String { "usage: --scan-print [--inbox PATH]... [--days N] [--no-calendar]" }
    }
}
