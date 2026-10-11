import Foundation
import InboxCore

/// Options shared by the scanning roles:
/// `[--db PATH|:memory:] [--inbox PATH]... [--days N] [--no-calendar | --events FILE [--calendar-denied]]
/// [--trash DIR] [--destination PATH] [--json]`. The database defaults to an in-memory one, so nothing
/// persists unless `--db` names a file. `--events` and `--trash` stand in for EventKit and ~/.Trash
/// in tests; `--calendar-denied` makes the events file behave like revoked calendar access.
struct ScanOptions {
    var dbPath = ":memory:"
    var inboxes: [URL] = []
    var days = 90
    var useCalendar = true
    var eventsFile: URL?
    var calendarDenied = false
    var trash: URL?
    var destination: String?
    var json = false

    static let usage = "[--db PATH|:memory:] [--inbox PATH]... [--days N] "
        + "[--no-calendar | --events FILE [--calendar-denied]] [--trash DIR] [--destination PATH] [--json]"

    init(_ args: [String]) throws {
        var rest = args[...]
        while let flag = rest.popFirst() {
            switch flag {
            case "--db":
                guard let path = rest.popFirst() else { throw UsageError() }
                dbPath = path
            case "--inbox":
                guard let path = rest.popFirst() else { throw UsageError() }
                inboxes.append(URL(fileURLWithPath: path))
            case "--days":
                guard let n = rest.popFirst().flatMap({ Int($0) }) else { throw UsageError() }
                days = n
            case "--no-calendar":
                useCalendar = false
            case "--events":
                guard let path = rest.popFirst() else { throw UsageError() }
                eventsFile = URL(fileURLWithPath: path)
            case "--calendar-denied":
                calendarDenied = true
            case "--trash":
                guard let path = rest.popFirst() else { throw UsageError() }
                trash = URL(fileURLWithPath: path)
            case "--destination":
                guard let path = rest.popFirst() else { throw UsageError() }
                destination = path
            case "--json":
                json = true
            default:
                throw UsageError()
            }
        }
        if inboxes.isEmpty {
            let home = FileManager.default.homeDirectoryForCurrentUser
            inboxes = [home.appendingPathComponent("Downloads"), home.appendingPathComponent("Desktop")]
        }
    }

    func openStore() throws -> ItemStore {
        dbPath == ":memory:" ? try ItemStore.inMemory() : try ItemStore.open(at: URL(fileURLWithPath: dbPath))
    }

    func scan() throws -> (ItemStore, ScanReport) {
        let store = try openStore()
        let calendar: (any CalendarSource)?
        if let eventsFile {
            calendar = try FileCalendarSource(contentsOf: eventsFile, accessGranted: !calendarDenied)
        } else {
            calendar = useCalendar ? EventKitCalendarSource() : nil
        }
        // Every calendar except birthdays and subscriptions; the app uses the user's selection instead.
        let calendarIDs = Set(calendar?.calendars().filter { !$0.isBackground }.map(\.id) ?? [])
        let settings = ScanSettings(inboxes: inboxes, backfillDays: days, calendarIDs: calendarIDs)
        let scanner = trash.map { Scanner(store: store, calendar: calendar, trashRoots: [$0]) }
            ?? Scanner(store: store, calendar: calendar)
        return (store, try scanner.scan(settings))
    }

    struct UsageError: Error, CustomStringConvertible {
        var description: String { "usage: --scan-print|--prompt \(ScanOptions.usage)" }
    }
}

/// `--scan-print OPTIONS`: one scan, then the report and every item as TSV (status, name, added,
/// source, saved by, event, that day, current path). With `--json`, only the report, as one JSON
/// object.
enum ScanPrint {
    static func run(_ args: [String]) throws {
        let options = try ScanOptions(args)
        let (store, report) = try options.scan()
        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            print(String(decoding: try encoder.encode(ReportJSON(report)), as: UTF8.self))
            return
        }

        let done = report.done.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.value) \($0.key.rawValue)" }
        print("scan: \(report.added) added, \(report.retracked) re-tracked, done: "
              + (done.isEmpty ? "none" : done.joined(separator: ", "))
              + String(format: ", %.3f s", report.duration))
        for (path, message) in report.folderErrors.sorted(by: { $0.key < $1.key }) {
            print("folder error: \(Printable.escape(path)): \(message)")
        }
        if let skipped = report.calendarSkipped { print("calendar skipped: \(skipped)") }

        let dateStyle = Date.ISO8601FormatStyle(timeZone: .current)
        for item in try store.items() {
            print([
                item.doneReason.map { "done:\($0.rawValue)" } ?? item.status.rawValue,
                item.name,
                item.addedAt.formatted(dateStyle),
                MetadataParsing.displaySource(source: item.provenance.sourceURL, referrer: item.provenance.referrerURL) ?? "-",
                item.provenance.savedBy.map(MetadataParsing.displayAgent) ?? "-",
                item.event.map { "\($0.kind.rawValue): \($0.title)" } ?? "-",
                item.dayEvents.isEmpty ? "-" : item.dayEvents.joined(separator: "; "),
                item.currentPath ?? "-",
            ].map(Printable.escape).joined(separator: "\t"))
        }
    }

    private struct ReportJSON: Encodable {
        let added: Int
        let retracked: Int
        let done: [String: Int]
        let folderErrors: [String: String]
        let calendarSkipped: String?
        let durationSeconds: Double

        init(_ report: ScanReport) {
            added = report.added
            retracked = report.retracked
            done = Dictionary(uniqueKeysWithValues: report.done.map { ($0.key.rawValue, $0.value) })
            folderErrors = report.folderErrors
            calendarSkipped = report.calendarSkipped
            durationSeconds = report.duration
        }
    }
}

/// `--prompt OPTIONS`: one scan, then the Markdown prompt for every tracked item.
enum PromptRole {
    static func run(_ args: [String]) throws {
        let options = try ScanOptions(args)
        let (store, _) = try options.scan()
        print(PromptGenerator().render(items: try store.items(status: .tracked), inboxPaths: options.inboxes.map(\.path),
                                       destinationRoot: options.destination), terminator: "")
    }
}

/// `--mark-done --db PATH ID...`: what the Mark Done button does, for the given item ids.
enum MarkDoneRole {
    static func run(_ args: [String]) throws {
        guard args.count >= 3, args[0] == "--db" else { throw UsageError() }
        let ids = try args.dropFirst(2).map { text -> Int64 in
            guard let id = Int64(text) else { throw UsageError() }
            return id
        }
        let changed = try ItemStore.open(at: URL(fileURLWithPath: args[1])).markDone(ids: ids, reason: .manual, at: Date())
        print("marked \(changed) done")
    }

    struct UsageError: Error, CustomStringConvertible {
        var description: String { "usage: --mark-done --db PATH ID..." }
    }
}
