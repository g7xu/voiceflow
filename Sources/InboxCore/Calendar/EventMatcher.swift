import Foundation

/// Attributes a moment to a calendar event (spec §5).
public struct EventMatcher: Sendable {
    /// Timed events longer than this are treated as all-day: a "Trip to NYC" or "On call" block
    /// would otherwise claim every file added during it.
    public static let longEventThreshold: TimeInterval = 12 * 3600

    private let timed: [CalendarEvent]
    private let dayLong: [CalendarEvent]
    private let window: TimeInterval

    public init(events: [CalendarEvent], window: TimeInterval) {
        let eligible = events.filter { !$0.isCanceled && !$0.isDeclined }
        let isDayLong = { (e: CalendarEvent) in e.isAllDay || e.end.timeIntervalSince(e.start) > Self.longEventThreshold }
        timed = eligible.filter { !isDayLong($0) }
        dayLong = eligible.filter(isDayLong)
        self.window = window
    }

    public func match(at t: Date) -> EventMatch? {
        let during = timed.filter { $0.start <= t && t < $0.end }
        if let best = during.min(by: Self.moreSpecificDuring) {
            return Self.match(best, .during)
        }
        let after = timed.filter { $0.end <= t && t.timeIntervalSince($0.end) <= window }
        if let best = after.min(by: Self.moreRecentAfter) {
            return Self.match(best, .after)
        }
        return nil
    }

    /// Titles of all-day (and over-long) events covering `t`, sorted and de-duplicated.
    public func dayEvents(at t: Date) -> [String] {
        Array(Set(dayLong.filter { $0.start <= t && t <= $0.end }.map(\.title))).sorted()
    }

    /// Latest start first; then the one ending sooner (shorter, so more specific); then by title so
    /// the result doesn't depend on fetch order.
    private static func moreSpecificDuring(_ a: CalendarEvent, _ b: CalendarEvent) -> Bool {
        if a.start != b.start { return a.start > b.start }
        if a.end != b.end { return a.end < b.end }
        return a.title < b.title
    }

    private static func moreRecentAfter(_ a: CalendarEvent, _ b: CalendarEvent) -> Bool {
        if a.end != b.end { return a.end > b.end }
        if a.start != b.start { return a.start > b.start }
        return a.title < b.title
    }

    private static func match(_ e: CalendarEvent, _ kind: EventMatch.Kind) -> EventMatch {
        EventMatch(title: e.title, start: e.start, end: e.end, location: e.location,
                   calendarTitle: e.calendarTitle, kind: kind)
    }
}
