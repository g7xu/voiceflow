import Foundation
import InboxCore

/// Calendar events read from a JSON file instead of EventKit, so the e2e tests get deterministic
/// calendars. Each event: {"title", "start", "end", "allDay"?, "location"?, "calendar"?,
/// "canceled"?, "declined"?} with ISO-8601 dates. Calendars are named by their "calendar" title.
struct FileCalendarSource: CalendarSource {
    private let all: [CalendarEvent]
    /// False simulates the user revoking calendar access in System Settings.
    let hasFullAccess: Bool

    init(contentsOf url: URL, accessGranted: Bool) throws {
        hasFullAccess = accessGranted
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = options
                if let date = formatter.date(from: text) { return date }
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not ISO-8601: \(text)"))
        }
        all = try decoder.decode([Entry].self, from: Data(contentsOf: url)).map(\.event)
    }

    func requestAccess() async throws -> Bool { hasFullAccess }

    func calendars() -> [CalendarInfo] {
        Set(all.map(\.calendarTitle)).sorted().map {
            CalendarInfo(id: $0, title: $0, sourceTitle: "File", isBackground: false)
        }
    }

    func events(from start: Date, to end: Date, calendarIDs: Set<String>) -> [CalendarEvent] {
        all.filter { calendarIDs.contains($0.calendarTitle) && $0.end >= start && $0.start <= end }
    }

    private struct Entry: Decodable {
        var title: String
        var start: Date
        var end: Date
        var allDay: Bool?
        var location: String?
        var calendar: String?
        var canceled: Bool?
        var declined: Bool?

        var event: CalendarEvent {
            CalendarEvent(title: title, start: start, end: end, isAllDay: allDay ?? false, location: location,
                          calendarTitle: calendar ?? "Test", isCanceled: canceled ?? false, isDeclined: declined ?? false)
        }
    }
}
