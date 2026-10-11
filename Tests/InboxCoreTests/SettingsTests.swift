import Foundation
import Testing
@testable import InboxCore

@Suite struct SettingsTests {
    let school = CalendarInfo(id: "id-school", title: "School", sourceTitle: "student@example.edu", isBackground: false)
    let work = CalendarInfo(id: "id-work", title: "Work", sourceTitle: "Google", isBackground: false)
    let holidays = CalendarInfo(id: "id-hol", title: "US Holidays", sourceTitle: "Subscribed", isBackground: true)

    @Test func unchosenCalendarsMeanAllButBackground() {
        #expect(InboxSettings().calendarIDs(available: [school, work, holidays]) == ["id-school", "id-work"])
    }

    @Test func chosenCalendarFallsBackToTitleAndSourceAfterResync() {
        var settings = InboxSettings()
        settings.calendars = [CalendarRef(school)]
        var resynced = school
        resynced.id = "id-school-new"
        #expect(settings.calendarIDs(available: [resynced, work]) == ["id-school-new"])
    }

    @Test func vanishedCalendarResolvesToNothing() {
        var settings = InboxSettings()
        settings.calendars = [CalendarRef(school)]
        #expect(settings.calendarIDs(available: [work]).isEmpty)
    }

    @Test func emptyFileDecodesToDefaults() throws {
        let decoded = try JSONDecoder().decode(InboxSettings.self, from: Data("{}".utf8))
        #expect(decoded == InboxSettings())
    }

    @Test func roundTripsThroughTheStore() throws {
        let tmp = try TempDir()
        let store = SettingsStore(paths: AppPaths(root: tmp.url.appendingPathComponent("ContextInbox")))
        #expect(try store.load() == InboxSettings())
        var settings = InboxSettings(inboxPaths: ["/Users/you/Downloads"], backfillDays: 30, destinationRoot: "/Users/you/Documents")
        settings.calendars = [CalendarRef(work)]
        settings.firstRunDone = true
        try store.save(settings)
        #expect(try store.load() == settings)
    }

    @Test func corruptFileThrowsInsteadOfResetting() throws {
        let tmp = try TempDir()
        let paths = AppPaths(root: tmp.url)
        try Data("{ not json".utf8).write(to: paths.config)
        #expect(throws: (any Error).self) { try SettingsStore(paths: paths).load() }
    }

    @Test func inboxFolderCheck() throws {
        let tmp = try TempDir()
        #expect(InboxFolderCheck.problem(with: tmp.url) == nil)
        #expect(InboxFolderCheck.problem(with: try tmp.file("a.txt")) != nil)
    }
}
