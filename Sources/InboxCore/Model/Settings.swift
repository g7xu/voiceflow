import Foundation

/// A chosen calendar. EventKit IDs can change on a full resync, so title + source is the fallback.
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
    /// nil until the user picks: then every calendar except birthdays and subscriptions counts.
    public var calendars: [CalendarRef]?
    public var matchWindowMinutes: Int
    public var backfillDays: Int
    public var destinationRoot: String?
    public var firstRunDone: Bool

    public init(inboxPaths: [String]? = nil, calendars: [CalendarRef]? = nil, matchWindowMinutes: Int = 120,
                backfillDays: Int = 90, destinationRoot: String? = nil, firstRunDone: Bool = false) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.inboxPaths = inboxPaths ?? ["Downloads", "Desktop"].map { home.appendingPathComponent($0).path }
        self.calendars = calendars
        self.matchWindowMinutes = matchWindowMinutes
        self.backfillDays = backfillDays
        self.destinationRoot = destinationRoot
        self.firstRunDone = firstRunDone
    }

    /// Missing keys take their defaults, so older config files keep loading as settings are added.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = InboxSettings()
        inboxPaths = try c.decodeIfPresent([String].self, forKey: .inboxPaths) ?? defaults.inboxPaths
        calendars = try c.decodeIfPresent([CalendarRef].self, forKey: .calendars)
        matchWindowMinutes = try c.decodeIfPresent(Int.self, forKey: .matchWindowMinutes) ?? defaults.matchWindowMinutes
        backfillDays = try c.decodeIfPresent(Int.self, forKey: .backfillDays) ?? defaults.backfillDays
        destinationRoot = try c.decodeIfPresent(String.self, forKey: .destinationRoot)
        firstRunDone = try c.decodeIfPresent(Bool.self, forKey: .firstRunDone) ?? defaults.firstRunDone
    }

    /// The IDs to match against now: chosen calendars found by ID, else by title + source.
    public func calendarIDs(available: [CalendarInfo]) -> Set<String> {
        guard let calendars else { return Set(available.filter { !$0.isBackground }.map(\.id)) }
        let byID = Set(available.map(\.id))
        return Set(calendars.compactMap { ref in
            byID.contains(ref.id) ? ref.id
                : available.first { $0.title == ref.title && $0.sourceTitle == ref.sourceTitle }?.id
        })
    }

    public func scanSettings(available: [CalendarInfo]) -> ScanSettings {
        ScanSettings(inboxes: inboxPaths.map { URL(fileURLWithPath: $0, isDirectory: true) },
                     backfillDays: backfillDays, matchWindow: TimeInterval(matchWindowMinutes * 60),
                     calendarIDs: calendarIDs(available: available))
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
