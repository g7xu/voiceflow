@preconcurrency import EventKit
import Foundation

public final class EventKitCalendarSource: CalendarSource, @unchecked Sendable {
    // Every use of `store` goes through `lock`, which is what makes the unchecked Sendable sound.
    private let store = EKEventStore()
    private let lock = NSLock()

    public init() {}

    public var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    public func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    public func calendars() -> [CalendarInfo] {
        lock.withLock {
            store.calendars(for: .event).map {
                CalendarInfo(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source.title,
                             isBackground: $0.type == .birthday || $0.type == .subscription)
            }
        }
    }

    /// EventKit silently truncates a predicate spanning more than four years, so long ranges are
    /// fetched in yearly chunks; events crossing a chunk boundary are de-duplicated.
    public func events(from start: Date, to end: Date, calendarIDs: Set<String>) -> [CalendarEvent] {
        lock.withLock {
            let calendars = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
            guard !calendars.isEmpty, start < end else { return [] }
            var seen = Set<String>()
            var out: [CalendarEvent] = []
            var chunkStart = start
            while chunkStart < end {
                let chunkEnd = min(chunkStart.addingTimeInterval(365 * 86_400), end)
                let predicate = store.predicateForEvents(withStart: chunkStart, end: chunkEnd, calendars: calendars)
                for event in store.events(matching: predicate) {
                    let key = "\(event.eventIdentifier ?? "")|\(event.startDate.timeIntervalSince1970)"
                    guard seen.insert(key).inserted else { continue }
                    out.append(Self.convert(event))
                }
                chunkStart = chunkEnd
            }
            return out
        }
    }

    private static func convert(_ event: EKEvent) -> CalendarEvent {
        let declined = event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CalendarEvent(
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            location: location?.isEmpty == false ? location : nil,
            calendarTitle: event.calendar.title,
            isCanceled: event.status == .canceled,
            isDeclined: declined
        )
    }
}
