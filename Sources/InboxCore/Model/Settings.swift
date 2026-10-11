import Foundation

/// A calendar the user toggled. EventKit IDs can change on a full resync, so title + source is the
/// fallback when the ID is gone.
public struct CalendarRef: Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var sourceTitle: String

    public init(_ info: CalendarInfo) {
        id = info.id
        title = info.title
        sourceTitle = info.sourceTitle
    }
}

public struct InboxSettings: Codable, Equatable, Sendable {
    public var inboxPaths: [String]
    /// Calendars the user switched off. Stored as exclusions so an account added later (say, Google
    /// after first run) counts without another trip to Settings.
    public var excludedCalendars: [CalendarRef]
    /// Birthday and subscribed calendars are off unless listed here.
    public var includedBackgroundCalendars: [CalendarRef]
    public var matchWindowMinutes: Int
    public var backfillDays: Int
    public var destinationRoot: String?
    public var firstRunDone: Bool

    public init(inboxPaths: [String]? = nil, excludedCalendars: [CalendarRef] = [],
                includedBackgroundCalendars: [CalendarRef] = [], matchWindowMinutes: Int = 120,
                backfillDays: Int = 90, destinationRoot: String? = nil, firstRunDone: Bool = false) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.inboxPaths = inboxPaths ?? ["Downloads", "Desktop"].map { home.appendingPathComponent($0).path }
        self.excludedCalendars = excludedCalendars
        self.includedBackgroundCalendars = includedBackgroundCalendars
        self.matchWindowMinutes = matchWindowMinutes
        self.backfillDays = backfillDays
        self.destinationRoot = destinationRoot
        self.firstRunDone = firstRunDone
    }

    /// Missing keys take their defaults, so older config files keep loading as settings change.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = InboxSettings()
        inboxPaths = try c.decodeIfPresent([String].self, forKey: .inboxPaths) ?? defaults.inboxPaths
        excludedCalendars = try c.decodeIfPresent([CalendarRef].self, forKey: .excludedCalendars) ?? []
        includedBackgroundCalendars = try c.decodeIfPresent([CalendarRef].self, forKey: .includedBackgroundCalendars) ?? []
        matchWindowMinutes = try c.decodeIfPresent(Int.self, forKey: .matchWindowMinutes) ?? defaults.matchWindowMinutes
        backfillDays = try c.decodeIfPresent(Int.self, forKey: .backfillDays) ?? defaults.backfillDays
        destinationRoot = try c.decodeIfPresent(String.self, forKey: .destinationRoot)
        firstRunDone = try c.decodeIfPresent(Bool.self, forKey: .firstRunDone) ?? defaults.firstRunDone
    }

    public func isEnabled(_ info: CalendarInfo, available: [CalendarInfo]) -> Bool {
        let ids = Set(available.map(\.id))
        return info.isBackground
            ? Self.list(includedBackgroundCalendars, refersTo: info, availableIDs: ids)
            : !Self.list(excludedCalendars, refersTo: info, availableIDs: ids)
    }

    public mutating func setEnabled(_ enabled: Bool, _ info: CalendarInfo, available: [CalendarInfo]) {
        let ids = Set(available.map(\.id))
        let addToList = info.isBackground == enabled
        if info.isBackground {
            includedBackgroundCalendars.removeAll { Self.ref($0, refersTo: info, availableIDs: ids) }
            if addToList { includedBackgroundCalendars.append(CalendarRef(info)) }
        } else {
            excludedCalendars.removeAll { Self.ref($0, refersTo: info, availableIDs: ids) }
            if addToList { excludedCalendars.append(CalendarRef(info)) }
        }
    }

    /// The IDs to match against now.
    public func calendarIDs(available: [CalendarInfo]) -> Set<String> {
        Set(available.filter { isEnabled($0, available: available) }.map(\.id))
    }

    public func scanSettings(available: [CalendarInfo]) -> ScanSettings {
        ScanSettings(inboxes: inboxPaths.map { URL(fileURLWithPath: $0, isDirectory: true) },
                     backfillDays: backfillDays, matchWindow: TimeInterval(matchWindowMinutes * 60),
                     calendarIDs: calendarIDs(available: available))
    }

    private static func list(_ refs: [CalendarRef], refersTo info: CalendarInfo, availableIDs: Set<String>) -> Bool {
        refs.contains { ref($0, refersTo: info, availableIDs: availableIDs) }
    }

    /// By ID; by title + source only when the stored ID no longer exists, so two calendars that share
    /// a name (two "Work" calendars in one account) stay independent.
    private static func ref(_ ref: CalendarRef, refersTo info: CalendarInfo, availableIDs: Set<String>) -> Bool {
        ref.id == info.id
            || (!availableIDs.contains(ref.id) && ref.title == info.title && ref.sourceTitle == info.sourceTitle)
    }
}

public struct SettingsStore: Sendable {
    public let paths: AppPaths

    public init(paths: AppPaths) {
        self.paths = paths
    }

    /// Defaults when the file is missing. A file that exists but doesn't parse throws instead, so a
    /// typo never silently resets the user's choices.
    public func load() throws -> InboxSettings {
        guard FileManager.default.fileExists(atPath: paths.config.path) else { return InboxSettings() }
        return try JSONDecoder().decode(InboxSettings.self, from: Data(contentsOf: paths.config))
    }

    public func save(_ settings: InboxSettings) throws {
        try paths.ensureExists()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: paths.config, options: .atomic)
    }
}

public enum InboxFolderCheck {
    /// Why `url` can't be an inbox folder, or nil when it can.
    public static func problem(with url: URL) -> String? {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .volumeSupportsPersistentIDsKey])
        guard values?.isDirectory == true else { return "\(url.lastPathComponent) isn't a folder." }
        guard values?.volumeSupportsPersistentIDs == true else {
            return "\(url.lastPathComponent) is on a drive without stable file IDs (such as exFAT), so moves can't be tracked."
        }
        return nil
    }
}
