import Foundation

/// Renders the Markdown handed to Claude (spec §8). Pure: the same items, settings, zone and
/// locale always give the same text.
public struct PromptGenerator: Sendable {
    public var timeZone: TimeZone
    public var locale: Locale
    /// Abbreviated to `~` in the folder names of the header; item paths stay absolute for `mv`.
    public var homeDirectory: String

    public init(timeZone: TimeZone = .current, locale: Locale = Locale(identifier: "en_US_POSIX"),
                homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.timeZone = timeZone
        self.locale = locale
        self.homeDirectory = homeDirectory
    }

    public func render(items: [Item], inboxPaths: [String], destinationRoot: String?) -> String {
        let format = Formats(timeZone: timeZone, locale: locale)
        var lines = [
            "# Files to organize",
            "",
            "These files landed in my inbox folders (\(inboxPaths.map(tilde).joined(separator: ", "))). "
                + "For each one I've noted where it",
            "came from and what was on my calendar when it arrived; you can't get that from the files themselves.",
            "Open any file if you need its contents.",
            "",
        ]
        if let destinationRoot {
            lines += ["Destination: organize into subfolders of \(Printable.escape(tilde(destinationRoot))).", ""]
        }
        lines += [
            "1. Propose a folder structure and a destination for every file. Show me the plan before moving anything.",
            "2. Once I approve, move them with `mv` using the absolute paths below. Rename only files whose names",
            "   carry no meaning (screenshots, \"document (3).pdf\", IMG_1234).",
            "3. Don't delete anything. List likely junk under \"Suggest deleting\" and leave it in place.",
        ]
        for group in groupItems(items) {
            lines += ["", header(group.event, format)]
            let headerDay = group.event.map { format.day.string(from: $0.start) }
            lines += group.items.map { line($0, headerDay: headerDay, format) }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func header(_ event: EventMatch?, _ format: Formats) -> String {
        guard let event else { return "## No calendar event" }
        let title = Printable.escape(event.title)
        let startDay = format.day.string(from: event.start)
        let endDay = format.day.string(from: event.end)
        let when: String
        switch event.kind {
        case .during:
            let end = startDay == endDay ? format.time.string(from: event.end) : "\(endDay) \(format.time.string(from: event.end))"
            when = "During \"\(title)\" — \(startDay), \(format.time.string(from: event.start))–\(end)"
        case .after:
            when = "After \"\(title)\" — \(endDay), ended \(format.time.string(from: event.end))"
        }
        let location = event.location.map { " · \(Printable.escape($0))" } ?? ""
        return "## \(when)\(location) · calendar: \(Printable.escape(event.calendarTitle))"
    }

    private func line(_ item: Item, headerDay: String?, _ format: Formats) -> String {
        let day = format.day.string(from: item.addedAt)
        let time = format.time.string(from: item.addedAt)
        var parts = ["added " + (day == headerDay ? time : "\(day) \(time)")]
        let source = MetadataParsing.displaySource(source: item.provenance.sourceURL, referrer: item.provenance.referrerURL)
        let agent = item.provenance.savedBy.map(MetadataParsing.displayAgent)
        switch (source, agent) {
        case let (source?, agent?): parts.append("from \(source) (\(agent))")
        case let (source?, nil): parts.append("from \(source)")
        case let (nil, agent?): parts.append(agent)
        case (nil, nil): break
        }
        if !item.dayEvents.isEmpty { parts.append("that day: " + item.dayEvents.joined(separator: "; ")) }
        // A trailing slash marks folders (and packages such as .app bundles), which `mv` moves whole.
        let path = Printable.escape(item.inboxPath) + (item.isDirectory ? "/" : "")
        return "- \(Self.codeSpan(path)) — " + parts.map(Printable.escape).joined(separator: " · ")
    }

    private func tilde(_ path: String) -> String {
        path == homeDirectory ? "~" : path.hasPrefix(homeDirectory + "/") ? "~" + path.dropFirst(homeDirectory.count) : path
    }

    /// An inline code span that survives backticks in the text: the fence is one backtick longer
    /// than the longest run inside, padded with a space when the text starts or ends with one.
    static func codeSpan(_ text: String) -> String {
        var longest = 0
        var run = 0
        for character in text {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        let fence = String(repeating: "`", count: longest + 1)
        let pad = text.hasPrefix("`") || text.hasSuffix("`") ? " " : ""
        return fence + pad + text + pad + fence
    }

    private struct Formats {
        let day: DateFormatter
        let time: DateFormatter

        init(timeZone: TimeZone, locale: Locale) {
            day = DateFormatter()
            day.dateFormat = "EEE MMM d"
            time = DateFormatter()
            time.dateFormat = "HH:mm"
            for formatter in [day, time] {
                formatter.timeZone = timeZone
                formatter.locale = locale
            }
        }
    }
}
