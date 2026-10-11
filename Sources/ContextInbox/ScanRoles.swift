import Foundation
import InboxCore

/// Options shared by the scanning roles:
/// `[--db PATH|:memory:] [--inbox PATH]... [--days N] [--no-calendar] [--destination PATH]`.
/// The database defaults to an in-memory one, so nothing persists unless `--db` names a file.
struct ScanOptions {
    var dbPath = ":memory:"
    var inboxes: [URL] = []
    var days = 90
    var useCalendar = true
    var destination: String?

    static let usage = "[--db PATH|:memory:] [--inbox PATH]... [--days N] [--no-calendar] [--destination PATH]"

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
            case "--destination":
                guard let path = rest.popFirst() else { throw UsageError() }
                destination = path
            default:
                throw UsageError()
            }
        }
        if inboxes.isEmpty {
            let home = FileManager.default.homeDirectoryForCurrentUser
            inboxes = [home.appendingPathComponent("Downloads"), home.appendingPathComponent("Desktop")]
        }
    }

    func scan() throws -> (ItemStore, ScanReport) {
        let store = dbPath == ":memory:" ? try ItemStore.inMemory() : try ItemStore.open(at: URL(fileURLWithPath: dbPath))
        let calendar = useCalendar ? EventKitCalendarSource() : nil
        // Every calendar except birthdays and subscriptions; the app uses the user's selection instead.
        let calendarIDs = Set(calendar?.calendars().filter { !$0.isBackground }.map(\.id) ?? [])
        let settings = ScanSettings(inboxes: inboxes, backfillDays: days, calendarIDs: calendarIDs)
        return (store, try Scanner(store: store, calendar: calendar).scan(settings))
    }

    struct UsageError: Error, CustomStringConvertible {
        var description: String { "usage: --scan-print|--prompt \(ScanOptions.usage)" }
    }
}

/// `--scan-print OPTIONS`: one scan, then the report and every item as TSV (status, name, added,
/// source, saved by, event, that day, current path).
enum ScanPrint {
    static func run(_ args: [String]) throws {
        let (store, report) = try ScanOptions(args).scan()

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
