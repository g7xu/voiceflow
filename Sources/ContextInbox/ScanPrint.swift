import Foundation
import InboxCore

/// `--scan-print [--inbox PATH]... [--days N]`: inbox items and their provenance as TSV
/// (name, added, kind, source, saved by). Reads only; nothing is stored.
enum ScanPrint {
    static func run(_ args: [String]) throws {
        var inboxes: [URL] = []
        var days = 90
        var rest = args[...]
        while let flag = rest.popFirst() {
            switch (flag, rest.popFirst()) {
            case let ("--inbox", path?): inboxes.append(URL(fileURLWithPath: path))
            case let ("--days", n?): days = Int(n) ?? days
            default: throw UsageError()
            }
        }
        if inboxes.isEmpty {
            let home = FileManager.default.homeDirectoryForCurrentUser
            inboxes = [home.appendingPathComponent("Downloads"), home.appendingPathComponent("Desktop")]
        }

        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let reader = LiveMetadataReader()
        let dateStyle = Date.ISO8601FormatStyle(timeZone: .current)
        for inbox in inboxes {
            let urls: [URL]
            do {
                urls = try LiveDirectoryLister().list(inbox)
            } catch {
                print("inbox \(inbox.path): can't list: \(error.localizedDescription)")
                continue
            }
            let read = urls.compactMap { url in (try? reader.read(url)).map { (url: url, raw: $0) } }
            let recent = read.filter { ($0.raw.addedAt ?? .distantPast) >= cutoff }
                .sorted { ($0.raw.addedAt ?? .distantPast) > ($1.raw.addedAt ?? .distantPast) }
            print("inbox \(inbox.path): \(urls.count) items, \(recent.count) added in the last \(days) days, "
                  + "\(urls.count - read.count) unreadable")
            for entry in recent {
                let provenance = MetadataParsing.provenance(entry.raw)
                print([
                    entry.url.lastPathComponent,
                    entry.raw.addedAt.map { $0.formatted(dateStyle) } ?? "-",
                    entry.raw.isDirectory ? "dir" : "file",
                    MetadataParsing.displaySource(source: provenance.sourceURL, referrer: provenance.referrerURL) ?? "-",
                    provenance.savedBy.map(MetadataParsing.displayAgent) ?? "-",
                ].joined(separator: "\t"))
            }
        }
    }

    struct UsageError: Error, CustomStringConvertible {
        var description: String { "usage: --scan-print [--inbox PATH]... [--days N]" }
    }
}
