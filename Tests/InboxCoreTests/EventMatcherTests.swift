import Foundation
import Testing
@testable import InboxCore

/// Times are UTC on 2026-10-07 so the tests don't depend on the machine's time zone.
private func at(_ hhmm: String, day: Int = 7) -> Date {
    try! Date("2026-10-\(String(format: "%02d", day))T\(hhmm):00Z", strategy: .iso8601)
}

private func event(_ title: String, _ start: String, _ end: String, allDay: Bool = false,
                   canceled: Bool = false, declined: Bool = false) -> CalendarEvent {
    CalendarEvent(title: title, start: at(start), end: at(end), isAllDay: allDay, calendarTitle: "Test",
                  isCanceled: canceled, isDeclined: declined)
}

private let twoHours: TimeInterval = 7200

@Suite struct EventMatcherTests {
    let lecture = event("Lecture", "10:00", "11:00")

    @Test(arguments: [
        ("10:00", EventMatch.Kind?.some(.during)),
        ("10:30", .during),
        ("11:00", .after),   // end is exclusive for "during" and inclusive for "after"
        ("11:30", .after),
        ("13:00", .after),   // window bound is inclusive
        ("13:30", nil),
        ("09:59", nil),
    ])
    func singleEvent(time: String, expected: EventMatch.Kind?) {
        let matcher = EventMatcher(events: [lecture], window: twoHours)
        #expect(matcher.match(at: at(time))?.kind == expected)
    }

    @Test func overlapPicksLaterStart() {
        let matcher = EventMatcher(events: [event("Block", "10:00", "12:00"), event("Talk", "10:30", "11:00")],
                                   window: twoHours)
        #expect(matcher.match(at: at("10:45"))?.title == "Talk")
        #expect(matcher.match(at: at("11:30"))?.title == "Block")
    }

    @Test func sameStartPicksShorterEvent() {
        let matcher = EventMatcher(events: [event("Long", "10:00", "12:00"), event("Short", "10:00", "11:00")],
                                   window: twoHours)
        #expect(matcher.match(at: at("10:30"))?.title == "Short")
    }

    @Test func tieBreakIgnoresFetchOrder() {
        let a = event("A", "10:00", "11:00"), b = event("B", "10:00", "11:00")
        #expect(EventMatcher(events: [a, b], window: twoHours).match(at: at("10:30"))?.title == "A")
        #expect(EventMatcher(events: [b, a], window: twoHours).match(at: at("10:30"))?.title == "A")
    }

    @Test func afterPicksMostRecentlyEnded() {
        let matcher = EventMatcher(events: [event("Earlier", "08:00", "09:00"), event("Later", "09:00", "10:00")],
                                   window: twoHours)
        #expect(matcher.match(at: at("10:30"))?.title == "Later")
    }

    @Test func duringBeatsAfter() {
        let matcher = EventMatcher(events: [event("Ended", "09:00", "10:00"), event("Now", "10:15", "11:00")],
                                   window: twoHours)
        let match = matcher.match(at: at("10:30"))
        #expect(match?.title == "Now")
        #expect(match?.kind == .during)
    }

    @Test func canceledAndDeclinedNeverMatch() {
        let matcher = EventMatcher(events: [event("Canceled", "10:00", "11:00", canceled: true),
                                            event("Declined", "10:00", "11:00", declined: true)],
                                   window: twoHours)
        #expect(matcher.match(at: at("10:30")) == nil)
        #expect(matcher.dayEvents(at: at("10:30")).isEmpty)
    }

    @Test func matchCopiesEventDetails() {
        var withPlace = lecture
        withPlace.location = "Center Hall 105"
        let match = EventMatcher(events: [withPlace], window: twoHours).match(at: at("10:30"))
        #expect(match == EventMatch(title: "Lecture", start: at("10:00"), end: at("11:00"),
                                    location: "Center Hall 105", calendarTitle: "Test", kind: .during))
    }

    @Test func allDayEventsAreDayContextOnly() {
        let fair = CalendarEvent(title: "Career Fair", start: at("00:00"), end: at("23:59"), isAllDay: true,
                                 calendarTitle: "Test")
        let matcher = EventMatcher(events: [fair], window: twoHours)
        #expect(matcher.match(at: at("10:30")) == nil)
        #expect(matcher.dayEvents(at: at("10:30")) == ["Career Fair"])
    }

    @Test func multiDayAllDayEventCoversMiddleDay() {
        let trip = CalendarEvent(title: "Conference", start: at("00:00", day: 6), end: at("23:59", day: 8),
                                 isAllDay: true, calendarTitle: "Test")
        #expect(EventMatcher(events: [trip], window: twoHours).dayEvents(at: at("15:00")) == ["Conference"])
    }

    @Test func overLongTimedEventIsTreatedAsAllDay() {
        let onCall = CalendarEvent(title: "On call", start: at("06:00"), end: at("22:00", day: 7), calendarTitle: "Test")
        let matcher = EventMatcher(events: [onCall, lecture], window: twoHours)
        #expect(matcher.match(at: at("10:30"))?.title == "Lecture")
        #expect(matcher.match(at: at("16:00")) == nil)
        #expect(matcher.dayEvents(at: at("16:00")) == ["On call"])
    }

    @Test func dayEventsAreSortedAndUnique() {
        let a = CalendarEvent(title: "Zeta", start: at("00:00"), end: at("23:59"), isAllDay: true, calendarTitle: "A")
        let b = CalendarEvent(title: "Alpha", start: at("00:00"), end: at("23:59"), isAllDay: true, calendarTitle: "A")
        let dup = CalendarEvent(title: "Zeta", start: at("00:00"), end: at("23:59"), isAllDay: true, calendarTitle: "B")
        #expect(EventMatcher(events: [a, b, dup], window: twoHours).dayEvents(at: at("12:00")) == ["Alpha", "Zeta"])
    }
}
