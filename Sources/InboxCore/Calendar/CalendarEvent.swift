import Foundation

public struct CalendarEvent: Equatable, Sendable {
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?
    public var calendarTitle: String
    public var isCanceled: Bool
    /// The user is an attendee and answered no.
    public var isDeclined: Bool

    public init(title: String, start: Date, end: Date, isAllDay: Bool = false, location: String? = nil,
                calendarTitle: String, isCanceled: Bool = false, isDeclined: Bool = false) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.calendarTitle = calendarTitle
        self.isCanceled = isCanceled
        self.isDeclined = isDeclined
    }
}

public struct CalendarInfo: Equatable, Sendable, Identifiable {
    /// EventKit's identifier, which a full resync can change; `title` + `sourceTitle` is the fallback.
    public var id: String
    public var title: String
    public var sourceTitle: String
    /// Birthdays and subscribed calendars (holidays, sports): off by default, they rarely say what
    /// you were doing.
    public var isBackground: Bool

    public init(id: String, title: String, sourceTitle: String, isBackground: Bool) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
        self.isBackground = isBackground
    }
}

/// The event an item is attributed to, copied out of the calendar so it outlives edits and
/// deletions there.
public struct EventMatch: Equatable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable {
        case during, after
    }

    public var title: String
    public var start: Date
    public var end: Date
    public var location: String?
    public var calendarTitle: String
    public var kind: Kind

    public init(title: String, start: Date, end: Date, location: String?, calendarTitle: String, kind: Kind) {
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.calendarTitle = calendarTitle
        self.kind = kind
    }
}

public protocol CalendarSource: Sendable {
    var hasFullAccess: Bool { get }
    func requestAccess() async throws -> Bool
    func calendars() -> [CalendarInfo]
    func events(from start: Date, to end: Date, calendarIDs: Set<String>) -> [CalendarEvent]
}
