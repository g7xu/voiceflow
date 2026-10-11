import Foundation
import InboxCore

/// Text for the window. Every string that came from a file, URL or calendar goes through
/// `Printable.escape`: SwiftUI would otherwise render bidi overrides and reorder a name.
enum Display {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    static func tilde(_ path: String) -> String {
        path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    static func name(_ item: Item) -> String {
        Printable.escape(item.name)
    }

    static func groupTitle(_ group: ItemGroup) -> String {
        guard let event = group.event else { return "No calendar event" }
        let title = Printable.escape(event.title)
        return event.kind == .during ? "During “\(title)”" : "After “\(title)”"
    }

    static func groupDetail(_ group: ItemGroup) -> String? {
        guard let event = group.event else { return nil }
        let day = event.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let time = event.kind == .during
            ? "\(event.start.formatted(date: .omitted, time: .shortened))–\(event.end.formatted(date: .omitted, time: .shortened))"
            : "ended \(event.end.formatted(date: .omitted, time: .shortened))"
        return ([day + ", " + time] + [event.location, event.calendarTitle].compactMap { $0 })
            .map(Printable.escape).joined(separator: " · ")
    }

    static func detail(_ item: Item) -> String {
        var parts = [item.addedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())]
        if let source = MetadataParsing.displaySource(source: item.provenance.sourceURL, referrer: item.provenance.referrerURL) {
            parts.append(source)
        }
        if let agent = item.provenance.savedBy { parts.append(MetadataParsing.displayAgent(agent)) }
        if !item.dayEvents.isEmpty { parts.append("that day: " + item.dayEvents.joined(separator: "; ")) }
        return parts.map(Printable.escape).joined(separator: " · ")
    }

    static func doneDetail(_ item: Item) -> String {
        let when = item.statusAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        let what: String
        switch item.doneReason {
        case .moved: what = "Moved to \(Printable.escape(tilde(item.currentPath ?? "?")))"
        case .trashed: what = "Moved to the Trash"
        case .gone: what = "No longer found"
        case .manual: what = "Marked done by you"
        case nil: what = "Done"
        }
        return "\(what) · \(when)"
    }

    static func reportSummary(_ report: ScanReport, at date: Date) -> String {
        var parts = ["Scanned \(date.formatted(date: .omitted, time: .shortened))"]
        if report.added > 0 { parts.append("\(report.added) new") }
        if report.retracked > 0 { parts.append("\(report.retracked) back") }
        for (reason, count) in report.done.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            parts.append("\(count) \(reason.rawValue)")
        }
        return parts.joined(separator: " · ")
    }
}
