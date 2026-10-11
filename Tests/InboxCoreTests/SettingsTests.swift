import Foundation
import Testing
@testable import InboxCore

@Suite struct SettingsTests {
    let school = CalendarInfo(id: "id-school", title: "School", sourceTitle: "student@example.edu", isBackground: false)
    let work = CalendarInfo(id: "id-work", title: "Work", sourceTitle: "Google", isBackground: false)
    let holidays = CalendarInfo(id: "id-hol", title: "US Holidays", sourceTitle: "Subscribed", isBackground: true)

    @Test func defaultsAreAllButBackground() {
        #expect(InboxSettings().calendarIDs(available: [school, work, holidays]) == ["id-school", "id-work"])
    }

    @Test func calendarAddedAfterChoosingIsOn() {
        var settings = InboxSettings()
        settings.setEnabled(false, school, available: [school])
        #expect(settings.calendarIDs(available: [school, work]) == ["id-work"])
    }

    @Test func backgroundCalendarOnlyWhenSwitchedOn() {
        var settings = InboxSettings()
        settings.setEnabled(true, holidays, available: [work, holidays])
        #expect(settings.calendarIDs(available: [work, holidays]) == ["id-work", "id-hol"])
        settings.setEnabled(false, holidays, available: [work, holidays])
        #expect(settings.calendarIDs(available: [work, holidays]) == ["id-work"])
    }

    @Test func togglingBackAndForthLeavesNoResidue() {
        var settings = InboxSettings()
        settings.setEnabled(false, work, available: [work])
        settings.setEnabled(true, work, available: [work])
        #expect(settings == InboxSettings())
    }

    @Test func exclusionSurvivesResyncByTitleAndSource() {
        var settings = InboxSettings()
        settings.setEnabled(false, school, available: [school])
        var resynced = school
        resynced.id = "id-school-new"
        #expect(settings.calendarIDs(available: [resynced, work]) == ["id-work"])
    }

    @Test func sameNamedCalendarsStayIndependent() {
        let dips1 = CalendarInfo(id: "a", title: "RISE Energy Dips", sourceTitle: "iCloud", isBackground: false)
        let dips2 = CalendarInfo(id: "b", title: "RISE Energy Dips", sourceTitle: "iCloud", isBackground: false)
        var settings = InboxSettings()
        settings.setEnabled(false, dips1, available: [dips1, dips2])
        #expect(settings.calendarIDs(available: [dips1, dips2]) == ["b"])
    }

    @Test func emptyFileDecodesToDefaults() throws {
        #expect(try JSONDecoder().decode(InboxSettings.self, from: Data("{}".utf8)) == InboxSettings())
    }

    /// An earlier build stored an include list under "calendars"; it's ignored, so every calendar counts.
    @Test func legacyIncludeListIsIgnored() throws {
        let legacy = Data(#"{"calendars": [], "firstRunDone": true}"#.utf8)
        let decoded = try JSONDecoder().decode(InboxSettings.self, from: legacy)
        #expect(decoded.calendarIDs(available: [school, work]) == ["id-school", "id-work"])
        #expect(decoded.firstRunDone)
    }

    @Test func roundTripsThroughTheStore() throws {
        let tmp = try TempDir()
        let store = SettingsStore(paths: AppPaths(root: tmp.url.appendingPathComponent("ContextInbox")))
        #expect(try store.load() == InboxSettings())
        var settings = InboxSettings(inboxPaths: ["/Users/you/Downloads"], backfillDays: 30,
                                     destinationRoot: "/Users/you/Documents", firstRunDone: true)
        settings.setEnabled(false, work, available: [work, holidays])
        settings.setEnabled(true, holidays, available: [work, holidays])
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
