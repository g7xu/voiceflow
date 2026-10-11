"""Which calendar event each file is attributed to (spec §5), and when that attribution may change.

Every file in these tests lands "now", so each event is placed relative to that moment: an event at
(-30, 30) is in progress when the file arrives, one at (-90, -30) ended half an hour before it.
"""

import datetime as dt

from harness import Sandbox


def as_db_time(iso: str) -> str:
    """An event time from ``sandbox.events`` as the app stores it: UTC text with milliseconds.
    The harness writes whole seconds, so the milliseconds are always ``.000``."""
    return dt.datetime.fromisoformat(iso).astimezone(dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S.000")


# ---- Rule 1: "during" ---------------------------------------------------------------------------


def test_file_added_during_an_event_is_matched_as_during(sandbox: Sandbox):
    # Step 1: a lecture is half over when the slides are saved to Downloads.
    sandbox.event("CSE 120 Lecture", -30, 30, location="Center Hall 105", calendar="School")
    lecture = sandbox.events[0]
    sandbox.add("lec05.pdf")

    # Step 2: the scan compares the file's date added with every event on the calendar.
    report = sandbox.scan()

    # Step 3: start <= added < end, so the lecture is the event. Its details are copied into the
    # row rather than referenced, so the row can be read without calendar access.
    assert report.calendar_skipped is None
    row = sandbox.row("lec05.pdf")
    assert row["event_title"] == "CSE 120 Lecture"
    assert row["event_match"] == "during"
    assert row["event_location"] == "Center Hall 105"
    assert row["event_calendar"] == "School"
    assert row["event_start"] == as_db_time(lecture["start"])
    assert row["event_end"] == as_db_time(lecture["end"])
    assert row["day_events"] == []


def test_overlapping_events_the_one_that_started_latest_wins(sandbox: Sandbox):
    # Step 1: a long study block is running, and office hours began inside it 20 minutes ago.
    # Office hours also ends later, so "shortest" or "ends first" would pick the study block.
    sandbox.event("Library study block", -90, 30)
    sandbox.event("TA office hours", -20, 60)
    sandbox.add("pset3-feedback.pdf")

    # Step 2: the scan finds two events in progress at the file's date added and must pick one.
    sandbox.scan()

    # Step 3: the one joined most recently says the most about the file.
    row = sandbox.row("pset3-feedback.pdf")
    assert row["event_title"] == "TA office hours", "latest start wins, regardless of end"
    assert row["event_match"] == "during"


def test_overlapping_events_with_the_same_start_the_one_ending_first_wins(sandbox: Sandbox):
    # Step 1: a lab section and a short quiz at its start both began 30 minutes ago.
    sandbox.event("Lab section", -30, 90)
    sandbox.event("Lab quiz", -30, 10)
    sandbox.add("quiz-answers.pdf")

    # Step 2: the scan finds two events in progress whose starts tie to the second.
    sandbox.scan()

    # Step 3: the shorter, more specific event breaks the tie (then the title would, so the result
    # never depends on the order the calendar returns events in).
    assert sandbox.row("quiz-answers.pdf")["event_title"] == "Lab quiz"


# ---- Rule 2: "after", within the 2-hour window -------------------------------------------------


def test_event_that_ended_30_minutes_before_the_file_matches_as_after(sandbox: Sandbox):
    # Step 1: the lecture ended half an hour ago; the slides are downloaded afterwards.
    sandbox.event("CSE 120 Lecture", -110, -30)
    sandbox.add("lec05.pdf")

    # Step 2: the scan finds no event in progress at the file's date added, so it looks back 2 hours
    # for the event that ended most recently.
    sandbox.scan()

    # Step 3: 30 minutes is inside that window.
    row = sandbox.row("lec05.pdf")
    assert row["event_title"] == "CSE 120 Lecture"
    assert row["event_match"] == "after"


def test_event_that_ended_3_hours_before_the_file_is_not_matched(sandbox: Sandbox):
    # Step 1: the lecture ended three hours before the file arrived.
    sandbox.event("CSE 120 Lecture", -260, -180)
    sandbox.add("lec05.pdf")

    # Step 2: the scan finds no event in progress and looks back 2 hours.
    sandbox.scan()

    # Step 3: the lecture ended outside that window, so the file has no event at all.
    row = sandbox.row("lec05.pdf")
    assert row["event_title"] is None
    assert row["event_match"] is None


def test_of_two_finished_events_the_one_that_ended_last_wins(sandbox: Sandbox):
    # Step 1: a lecture ended 90 minutes ago and a discussion section ended 30 minutes ago.
    sandbox.event("CSE 120 Lecture", -170, -90)
    sandbox.event("CSE 120 Discussion", -80, -30)
    sandbox.add("worksheet.pdf")

    # Step 2: the scan finds no event in progress, and both ended within the 2-hour window.
    sandbox.scan()

    # Step 3: the most recent thing you were doing is the better guess.
    row = sandbox.row("worksheet.pdf")
    assert row["event_title"] == "CSE 120 Discussion"
    assert row["event_match"] == "after"


def test_event_in_progress_beats_one_that_just_ended(sandbox: Sandbox):
    # Step 1: the lecture ended 25 minutes ago, and office hours started 20 minutes ago.
    sandbox.event("CSE 120 Lecture", -85, -25)
    sandbox.event("TA office hours", -20, 40)
    sandbox.add("pset3.pdf")

    # Step 2: the scan finds one event in progress and one that would qualify as "after".
    sandbox.scan()

    # Step 3: "after" is only a fallback for when no event is in progress.
    row = sandbox.row("pset3.pdf")
    assert row["event_title"] == "TA office hours"
    assert row["event_match"] == "during"


# ---- Events that never match ------------------------------------------------------------------


def test_canceled_event_is_never_matched(sandbox: Sandbox):
    # Step 1: the lecture is on the calendar for right now, but it was canceled.
    sandbox.event("CSE 120 Lecture", -30, 30, canceled=True)
    sandbox.add("lec05.pdf")

    # Step 2: the scan sets canceled events aside before it looks for a match.
    sandbox.scan()

    # Step 3: you weren't at a canceled event, so it says nothing about where the file came from.
    row = sandbox.row("lec05.pdf")
    assert row["event_title"] is None
    assert row["event_match"] is None


def test_declined_event_is_never_matched(sandbox: Sandbox):
    # Step 1: a meeting is happening now, but you declined the invite.
    sandbox.event("Team sync", -30, 30, calendar="Work", declined=True)
    sandbox.add("Q3-plan.xlsx")

    # Step 2: the scan sets declined events aside before it looks for a match.
    sandbox.scan()

    # Step 3: a declined meeting isn't what you were doing either.
    row = sandbox.row("Q3-plan.xlsx")
    assert row["event_title"] is None
    assert row["event_match"] is None


# ---- All-day and over-long events: "that day" context only ------------------------------------


def test_all_day_event_is_listed_in_day_events_but_not_matched(sandbox: Sandbox):
    # Step 1: today is the career fair, an all-day event. Calendar stores it midnight to midnight;
    # centering it on now keeps the test independent of the time of day.
    sandbox.event("Career Fair", -12 * 60, 12 * 60, all_day=True)
    sandbox.airdrop("IMG_4471.HEIC")

    # Step 2: the scan splits all-day events off from timed ones; only timed ones can be matched.
    sandbox.scan()

    # Step 3: an all-day event covers every file of the day, so it can't be "the" event. Its title
    # is kept as background instead (the prompt shows it as "that day: Career Fair").
    row = sandbox.row("IMG_4471.HEIC")
    assert row["event_title"] is None
    assert row["event_match"] is None
    assert row["day_events"] == ["Career Fair"]


def test_timed_event_longer_than_12_hours_is_treated_like_all_day(sandbox: Sandbox):
    # Step 1: a 20-hour conference block, entered as a timed event, is in progress.
    sandbox.event("Design conference", -10 * 60, 10 * 60)
    sandbox.add("badge.pdf")

    # Step 2: the scan sorts events over 12 hours into the all-day pile, whatever their flag says.
    sandbox.scan()

    # Step 3: left as a timed event, it would claim every file added during it.
    row = sandbox.row("badge.pdf")
    assert row["event_title"] is None
    assert row["day_events"] == ["Design conference"]


def test_short_event_inside_a_long_event_is_the_match(sandbox: Sandbox):
    # Step 1: during the 20-hour conference, the keynote ended 30 minutes before the file arrived.
    sandbox.event("Design conference", -10 * 60, 10 * 60)
    sandbox.event("Keynote", -90, -30)
    sandbox.add("keynote-slides.pdf")

    # Step 2: the scan demotes the conference to "that day" context, leaving only the keynote.
    sandbox.scan()

    # Step 3: if the conference counted as a timed event it would win as "during", because an
    # event in progress beats one that ended. Demoted, it leaves the keynote as the match.
    row = sandbox.row("keynote-slides.pdf")
    assert row["event_title"] == "Keynote", "the over-12 h conference must not take the match"
    assert row["event_match"] == "after"
    assert row["day_events"] == ["Design conference"]


def test_timed_event_of_exactly_12_hours_is_still_matched(sandbox: Sandbox):
    # Step 1: a 12-hour on-call shift, half over.
    sandbox.event("On-call shift", -6 * 60, 6 * 60)
    sandbox.add("incident-log.txt")

    # Step 2: the scan demotes only events strictly longer than 12 hours.
    sandbox.scan()

    # Step 3: exactly 12 is an ordinary timed event, and it is in progress.
    row = sandbox.row("incident-log.txt")
    assert row["event_title"] == "On-call shift"
    assert row["event_match"] == "during"
    assert row["day_events"] == []


# ---- When the match is recomputed, and when it is kept -----------------------------------------


def test_event_that_syncs_late_is_matched_on_the_next_scan(sandbox: Sandbox):
    # Step 1: the School calendar exists (it has yesterday's office hours), but today's lecture
    # hasn't synced to this Mac yet. A file arrives during the lecture.
    sandbox.event("Office hours", -24 * 60, -23 * 60)
    sandbox.add("lec05.pdf")

    # Step 2: the first scan runs matching and finds nothing near the file.
    report = sandbox.scan()
    assert report.calendar_skipped is None, "the calendar exists, so matching really ran"
    assert sandbox.row("lec05.pdf")["event_title"] is None

    # Step 3: the lecture syncs down from the server.
    sandbox.event("CSE 120 Lecture", -30, 30)

    # Step 4: every scan re-matches tracked items against the calendar as it is at that moment.
    report = sandbox.scan()

    # Step 5: the same row (nothing new was added) now carries the lecture.
    assert report.added == 0
    row = sandbox.row("lec05.pdf")
    assert row["event_title"] == "CSE 120 Lecture"
    assert row["event_match"] == "during"


def test_tracked_item_picks_up_edits_to_its_event(sandbox: Sandbox):
    # Step 1: the lecture is in Center Hall; the slides arrive during it and get matched.
    sandbox.event("CSE 120 Lecture", -30, 30, location="Center Hall 105")
    lecture = sandbox.events[0]
    sandbox.add("lec05.pdf")
    sandbox.scan()
    assert sandbox.row("lec05.pdf")["event_location"] == "Center Hall 105"

    # Step 2: the instructor moves the lecture online.
    lecture["location"] = "Zoom"

    # Step 3: the file is still tracked, so this scan matches it again and copies the event afresh.
    sandbox.scan()

    # Step 4: the row follows the calendar.
    assert sandbox.row("lec05.pdf")["event_location"] == "Zoom"


def test_event_deleted_from_a_calendar_is_cleared_from_tracked_items(sandbox: Sandbox):
    # Step 1: the School calendar has yesterday's office hours and today's lecture; the file arrives
    # during the lecture and is matched to it.
    sandbox.event("Office hours", -24 * 60, -23 * 60)
    sandbox.event("CSE 120 Lecture", -30, 30)
    lecture = sandbox.events[1]
    sandbox.add("lec05.pdf")
    sandbox.scan()
    assert sandbox.row("lec05.pdf")["event_title"] == "CSE 120 Lecture"

    # Step 2: the lecture is deleted. The calendar itself is still there.
    sandbox.events.remove(lecture)

    # Step 3: the scan can read the calendar, so it re-matches the tracked file against it.
    report = sandbox.scan()

    # Step 4: nothing matches any more, so the event is cleared. Contrast
    # test_event_fields_are_kept_when_no_calendars_are_left, where no calendar can be read.
    assert report.calendar_skipped is None
    row = sandbox.row("lec05.pdf")
    assert row["event_title"] is None
    assert row["event_match"] is None


def test_done_item_keeps_its_event_fields_when_the_calendar_changes(sandbox: Sandbox):
    # Step 1: two files arrive while the School calendar has nothing near them.
    sandbox.event("Office hours", -24 * 60, -23 * 60)
    sandbox.add("kept.pdf")
    sandbox.add("filed.pdf")
    sandbox.scan()

    # Step 2: one file is organized into Documents; the next scan marks it done.
    sandbox.move(sandbox.downloads / "filed.pdf", sandbox.documents / "School")
    report = sandbox.scan()
    assert report.done == {"moved": 1}
    filed_before = sandbox.row("filed.pdf")

    # Step 3: a lecture that covers both arrivals syncs late.
    sandbox.event("CSE 120 Lecture", -30, 30)

    # Step 4: the scan re-matches only the items it still finds in an inbox.
    sandbox.scan()

    # Step 5: the tracked file gets the lecture, which proves it would have matched. The done file's
    # row is the record of the file as it left, and stays exactly as it was.
    assert sandbox.row("kept.pdf")["event_title"] == "CSE 120 Lecture"
    filed = sandbox.row("filed.pdf")
    assert filed["status"] == "done"
    assert filed["event_title"] is None, "done items are never re-matched"
    assert filed == filed_before


def test_event_fields_are_kept_when_calendar_access_is_missing(sandbox: Sandbox):
    # Step 1: the file arrives during the lecture and the first scan matches it.
    sandbox.event("CSE 120 Lecture", -30, 30, location="Center Hall 105")
    sandbox.add("lec05.pdf")
    sandbox.scan()
    matched = sandbox.row("lec05.pdf")
    assert matched["event_title"] == "CSE 120 Lecture"

    # Step 2: calendar access goes away (the harness runs the app with --no-calendar).
    sandbox.calendar_available = False

    # Step 3: the scan has no calendar to match against.
    report = sandbox.scan()

    # Step 4: matching blind would clear the event, destroying context that may not be rebuildable
    # later. So the scan skips matching, says why, and leaves the row untouched.
    assert report.calendar_skipped == "calendar disabled"
    assert sandbox.row("lec05.pdf") == matched


def test_event_fields_are_kept_when_no_calendars_are_left(sandbox: Sandbox):
    # Step 1: the file arrives during the lecture and the first scan matches it.
    sandbox.event("CSE 120 Lecture", -30, 30)
    sandbox.add("lec05.pdf")
    sandbox.scan()
    matched = sandbox.row("lec05.pdf")
    assert matched["event_title"] == "CSE 120 Lecture"

    # Step 2: every calendar disappears, as when the account is removed from Internet Accounts.
    # The test calendar source only knows calendars that have events, so emptying it removes them.
    sandbox.events.clear()

    # Step 3: the scan finds none of the selected calendars.
    report = sandbox.scan()

    # Step 4: same rule as missing access: nothing readable to match against, so the match is kept.
    assert report.calendar_skipped == "none of the selected calendars exist"
    assert sandbox.row("lec05.pdf") == matched
