"""A scan marks an item done only on positive evidence that it left (spec §5-6).

What a scan can't observe, it leaves as it was: an inbox it can't list, or a calendar it can't
read, never turns into "everything left" or "no event". And the app never touches the user's
files: it reads metadata and writes only its own database.
"""

import json
import subprocess
from pathlib import Path


from harness import Report, Sandbox


def snapshot(*folders: Path) -> dict[str, dict]:
    """Everything a scan could change about the user's files, keyed by path: contents (None for a
    directory), inode, modification time and extended attributes such as the download source."""
    return {
        str(path): {
            "bytes": None if path.is_dir() else path.read_bytes(),
            "inode": path.stat().st_ino,
            "mtime_ns": path.stat().st_mtime_ns,
            "xattrs": subprocess.run(["xattr", "-l", str(path)], capture_output=True).stdout,
        }
        for folder in folders
        for path in sorted(folder.rglob("*"))
    }


def scan_watching_only(sandbox: Sandbox, inbox: Path) -> Report:
    """A scan whose settings list a single inbox folder, as after the user removes the other one
    in Settings. The harness's own scan always passes both Downloads and Desktop."""
    out = sandbox._run("--scan-print", "--db", str(sandbox.db), "--inbox", str(inbox),
                       "--trash", str(sandbox.trash), "--no-calendar", "--json")
    data = json.loads(out.splitlines()[0])
    return Report(added=data["added"], retracked=data["retracked"], done=data["done"],
                  folder_errors=data["folderErrors"], calendar_skipped=data.get("calendarSkipped"),
                  duration=data["durationSeconds"])


# ---- Inbox folders the scan can't list ----------------------------------------------------------


def test_unreadable_inbox_is_reported_and_its_items_are_left_alone(sandbox: Sandbox):
    # Step 1: two files arrive in Downloads and the first scan tracks them.
    sandbox.download("lec05.pdf", url="https://canvas.example.edu/files/lec05.pdf")
    sandbox.airdrop("IMG_4471.HEIC")
    sandbox.scan()
    before = sandbox.rows()

    # Step 2: the app loses read access to Downloads, as when its Files & Folders permission is
    # revoked in System Settings. The files are still there; the app just can't see them.
    sandbox.downloads.chmod(0o000)

    # Step 3: the listing fails. An empty listing would mean "both files left"; a failed one
    # means "unknown", so the scan reports the folder and changes nothing in it.
    report = sandbox.scan()

    assert list(report.folder_errors) == [str(sandbox.downloads)]
    assert report.done == {}, "a folder that can't be listed is no evidence that its files left"
    assert (report.added, report.retracked) == (0, 0)
    assert sandbox.rows() == before


def test_scan_is_normal_again_once_the_inbox_is_readable(sandbox: Sandbox):
    # Step 1: one file is tracked, then a second one lands just before access is lost.
    sandbox.download("lec05.pdf", url="https://canvas.example.edu/files/lec05.pdf")
    sandbox.scan()
    tracked_before = sandbox.row("lec05.pdf")
    sandbox.add("syllabus.pdf")

    # Step 2: while Downloads is unreadable the newcomer can't be seen, so it isn't added.
    sandbox.downloads.chmod(0o000)
    failed = sandbox.scan()
    assert list(failed.folder_errors) == [str(sandbox.downloads)]
    assert failed.added == 0

    # Step 3: with access back, the scan lists Downloads again: no error, the newcomer is added
    # and the item tracked all along comes through untouched.
    sandbox.downloads.chmod(0o755)
    report = sandbox.scan()

    assert report.folder_errors == {}
    assert (report.added, report.done) == (1, {})
    assert sandbox.row("syllabus.pdf")["status"] == "tracked"
    assert sandbox.row("lec05.pdf") == tracked_before


def test_unreadable_downloads_does_not_stop_desktop_from_being_scanned(sandbox: Sandbox):
    # Step 1: one file in each inbox, both tracked.
    sandbox.download("lec05.pdf", url="https://canvas.example.edu/files/lec05.pdf")
    old_shot = sandbox.add("Screenshot 2026-10-11 at 09.00.00.png", folder=sandbox.desktop)
    sandbox.scan()
    lecture_before = sandbox.row("lec05.pdf")

    # Step 2: on Desktop, the user files the old screenshot away and takes a new one. Then
    # Downloads becomes unreadable.
    sandbox.move(old_shot, sandbox.documents / "Screenshots")
    sandbox.add("Screenshot 2026-10-11 at 10.14.03.png", folder=sandbox.desktop)
    sandbox.downloads.chmod(0o000)

    # Step 3: each inbox is judged on its own listing. Desktop listed fine, so its departure and
    # its arrival both count; Downloads didn't, so its item stays exactly as it was.
    report = sandbox.scan()

    assert list(report.folder_errors) == [str(sandbox.downloads)]
    assert report.added == 1
    assert report.done == {"moved": 1}

    filed = sandbox.row("Screenshot 2026-10-11 at 09.00.00.png")
    assert (filed["status"], filed["done_reason"]) == ("done", "moved")
    assert filed["current_path"] == str(sandbox.documents / "Screenshots" / "Screenshot 2026-10-11 at 09.00.00.png")
    assert sandbox.row("Screenshot 2026-10-11 at 10.14.03.png")["status"] == "tracked"
    assert sandbox.row("lec05.pdf") == lecture_before


def test_file_moved_out_of_an_unreadable_inbox_is_marked_moved_only_once_it_is_readable(sandbox: Sandbox):
    # Step 1: a lecture download is tracked.
    lecture = sandbox.download("lec05.pdf", url="https://canvas.example.edu/files/lec05.pdf")
    sandbox.scan()

    # Step 2: the user really does file it away, and then Downloads becomes unreadable.
    sandbox.move(lecture, sandbox.documents / "CSE120")
    sandbox.downloads.chmod(0o000)

    # Step 3: the departure happened, but this scan can't see it: without a listing of Downloads
    # there is nothing showing the file is missing from it.
    blind = sandbox.scan()
    assert blind.done == {}
    assert sandbox.row("lec05.pdf")["status"] == "tracked"

    # Step 4: once Downloads lists again, the file is absent from it and its bookmark leads to the
    # new folder, so it is marked moved with where it went.
    sandbox.downloads.chmod(0o755)
    report = sandbox.scan()

    assert report.done == {"moved": 1}
    row = sandbox.row("lec05.pdf")
    assert (row["status"], row["done_reason"]) == ("done", "moved")
    assert row["current_path"] == str(sandbox.documents / "CSE120" / "lec05.pdf")


def test_file_deleted_from_an_unreadable_inbox_is_marked_gone_only_once_it_is_readable(sandbox: Sandbox):
    # Step 1: a file is tracked.
    junk = sandbox.add("document (3).pdf")
    sandbox.scan()

    # Step 2: the user deletes it for good, and then Downloads becomes unreadable.
    junk.unlink()
    sandbox.downloads.chmod(0o000)

    # Step 3: the blind scan leaves it tracked.
    blind = sandbox.scan()
    assert blind.done == {}
    assert sandbox.row("document (3).pdf")["status"] == "tracked"

    # Step 4: a readable listing shows it missing and its bookmark leads nowhere: gone, with no
    # current path.
    sandbox.downloads.chmod(0o755)
    report = sandbox.scan()

    assert report.done == {"gone": 1}
    row = sandbox.row("document (3).pdf")
    assert (row["status"], row["done_reason"], row["current_path"]) == ("done", "gone", None)


def test_missing_inbox_folder_is_an_error_not_an_empty_folder(sandbox: Sandbox):
    # Step 1: a file is tracked in Downloads.
    sandbox.download("lec05.pdf", url="https://canvas.example.edu/files/lec05.pdf")
    sandbox.scan()
    before = sandbox.rows()

    # Step 2: the whole Downloads folder disappears from its path, as an inbox on an external
    # drive does when the drive is unplugged. The file inside still exists.
    sandbox.downloads.rename(sandbox.root / "Downloads-unplugged")

    # Step 3: a folder that isn't there can't be listed, which is not the same as listing empty.
    report = sandbox.scan()

    assert list(report.folder_errors) == [str(sandbox.downloads)]
    assert report.done == {}
    assert sandbox.rows() == before

    # Step 4: plugged back in, the folder lists again and nothing changed.
    (sandbox.root / "Downloads-unplugged").rename(sandbox.downloads)
    report = sandbox.scan()

    assert (report.folder_errors, report.done) == ({}, {})
    assert sandbox.rows() == before


def test_inbox_dropped_from_settings_leaves_its_items_tracked(sandbox: Sandbox):
    # Step 1: one file in each inbox, both tracked, with both inboxes watched.
    sandbox.add("syllabus.pdf")
    sandbox.add("Screenshot 2026-10-11 at 10.14.03.png", folder=sandbox.desktop)
    sandbox.scan()
    before = sandbox.rows()

    # Step 2: the user stops watching Desktop, so the next scan lists Downloads only. The
    # screenshot never appears in any listing.
    report = scan_watching_only(sandbox, sandbox.downloads)

    # Step 3: not being listed isn't evidence of leaving; only a listing of the item's own folder
    # that lacks it would be. The screenshot stays tracked.
    assert report.folder_errors == {}
    assert report.done == {}
    assert sandbox.rows() == before


def test_file_moved_into_an_unreadable_inbox_stays_tracked(sandbox: Sandbox):
    # Step 1: a screenshot on Desktop is tracked.
    shot = sandbox.add("Screenshot 2026-10-11 at 10.14.03.png", folder=sandbox.desktop)
    sandbox.scan()

    # Step 2: the user drags it into Downloads (still an inbox), and then Downloads becomes
    # unreadable, as when the app's Downloads permission is revoked.
    sandbox.move(shot, sandbox.downloads)
    sandbox.downloads.chmod(0o000)

    # Step 3: Desktop lists without the screenshot, but the one place it could now be is the folder
    # the scan couldn't read. Spec §6 defines done as "no longer at the top level of an inbox" and
    # §12 says revoking Downloads access then scanning marks nothing done.
    report = sandbox.scan()

    assert list(report.folder_errors) == [str(sandbox.downloads)]
    assert report.done == {}, "the file is at the top level of Downloads, which this scan couldn't see"
    assert sandbox.row("Screenshot 2026-10-11 at 10.14.03.png")["status"] == "tracked"


# ---- A calendar the scan can't read -------------------------------------------------------------


def test_calendar_unavailable_keeps_the_event_already_matched(sandbox: Sandbox):
    # Step 1: a file lands during a lecture on a career-fair day; the first scan matches both.
    sandbox.event("CSE 120 Lecture", -30, 30, location="Center Hall 105")
    sandbox.event("Career Fair", -600, 600, all_day=True)
    sandbox.download("lec05.pdf", url="https://canvas.example.edu/files/lec05.pdf")
    sandbox.scan()
    before = sandbox.row("lec05.pdf")
    assert (before["event_title"], before["event_match"]) == ("CSE 120 Lecture", "during")
    assert before["day_events"] == ["Career Fair"]

    # Step 2: calendar access goes away (the app is then run with --no-calendar).
    sandbox.calendar_available = False

    # Step 3: matching against no events would clear the lecture, and the date added it was
    # matched on resets as soon as the file moves, so the match could never be rebuilt. The scan
    # skips matching, says so, and keeps the event fields.
    report = sandbox.scan()

    assert report.calendar_skipped == "calendar disabled"
    row = sandbox.row("lec05.pdf")
    assert row["event_title"] == "CSE 120 Lecture"
    assert row["event_location"] == "Center Hall 105"
    assert row["day_events"] == ["Career Fair"]
    assert row == before, "nothing about the item changed, so the scan shouldn't have rewritten it"


def test_calendar_that_no_longer_exists_keeps_the_event_already_matched(sandbox: Sandbox):
    # Step 1: a file lands during a lecture from the "School" calendar and is matched.
    sandbox.event("CSE 120 Lecture", -30, 30, calendar="School")
    sandbox.add("lec05.pdf")
    sandbox.scan()
    before = sandbox.row("lec05.pdf")

    # Step 2: the School calendar disappears, as when its account is signed out of macOS. With
    # access granted but no selected calendar left, there is nothing to match against.
    sandbox.events.clear()

    # Step 3: same rule as missing access: skip matching and keep what was matched.
    report = sandbox.scan()

    assert report.calendar_skipped == "none of the selected calendars exist"
    assert sandbox.row("lec05.pdf")["event_title"] == "CSE 120 Lecture"
    assert sandbox.row("lec05.pdf") == before


def test_event_is_kept_when_the_calendar_comes_back(sandbox: Sandbox):
    # Step 1: matched with the calendar available.
    sandbox.event("CSE 120 Lecture", -30, 30, location="Center Hall 105")
    sandbox.add("lec05.pdf")
    sandbox.scan()
    matched = sandbox.row("lec05.pdf")

    # Step 2: one scan without calendar access keeps the match.
    sandbox.calendar_available = False
    assert sandbox.scan().calendar_skipped == "calendar disabled"

    # Step 3: access returns and the lecture is still in the calendar. The item is re-matched,
    # since tracked items are re-matched every scan, and lands on the same event.
    sandbox.calendar_available = True
    report = sandbox.scan()

    assert report.calendar_skipped is None
    row = sandbox.row("lec05.pdf")
    assert (row["event_title"], row["event_match"]) == ("CSE 120 Lecture", "during")
    assert row == matched


def test_item_added_while_the_calendar_was_unavailable_is_matched_once_it_returns(sandbox: Sandbox):
    # Step 1: the file lands during a lecture, but the first scan runs without calendar access,
    # so it has no event yet.
    sandbox.event("CSE 120 Lecture", -30, 30)
    sandbox.add("lec05.pdf")
    sandbox.calendar_available = False
    first = sandbox.scan()
    assert first.calendar_skipped == "calendar disabled"
    assert sandbox.row("lec05.pdf")["event_title"] is None

    # Step 2: access comes back. The file's date added is still the moment it landed, so the
    # re-match finds the lecture after the fact.
    sandbox.calendar_available = True
    report = sandbox.scan()

    assert report.calendar_skipped is None
    row = sandbox.row("lec05.pdf")
    assert (row["event_title"], row["event_match"]) == ("CSE 120 Lecture", "during")


def test_done_detection_runs_while_the_calendar_is_unavailable(sandbox: Sandbox):
    # Step 1: a lecture download is tracked and matched.
    sandbox.event("CSE 120 Lecture", -30, 30)
    lecture = sandbox.download("lec05.pdf", url="https://canvas.example.edu/files/lec05.pdf")
    sandbox.scan()

    # Step 2: the user files it away; the next scan has no calendar access.
    sandbox.move(lecture, sandbox.documents / "CSE120")
    sandbox.calendar_available = False

    # Step 3: the calendar only feeds event fields. The Downloads listing is still evidence the
    # file left, so it is marked moved, and the done row keeps its lecture.
    report = sandbox.scan()

    assert report.calendar_skipped == "calendar disabled"
    assert report.done == {"moved": 1}
    row = sandbox.row("lec05.pdf")
    assert (row["status"], row["done_reason"]) == ("done", "moved")
    assert row["event_title"] == "CSE 120 Lecture"


# ---- The user's files ---------------------------------------------------------------------------


def test_scans_never_change_the_users_files(sandbox: Sandbox):
    # Step 1: a realistic mix in both inboxes, including entries the scan skips.
    sandbox.event("CSE 120 Lecture", -30, 30)
    lecture = sandbox.download("lec05.pdf", url="https://cdn.example.edu/f/lec05.pdf?token=SECRET",
                               referrer="https://canvas.example.edu/courses/120/files")
    sandbox.airdrop("IMG_4471.HEIC")
    sandbox.add_folder("hackathon-starter")
    sandbox.add(".DS_Store")
    sandbox.add("big-video.mp4.crdownload")
    shot = sandbox.add("Screenshot 2026-10-11 at 10.14.03.png", folder=sandbox.desktop)
    user_folders = (sandbox.downloads, sandbox.desktop, sandbox.documents, sandbox.trash)
    arranged = snapshot(*user_folders)

    # Step 2: every entry point that reads the inboxes: a scan, and Copy Prompt (which scans too).
    report = sandbox.scan()
    sandbox.prompt(destination=sandbox.documents)

    assert report.added == 4, "the scan did read the inboxes"
    assert snapshot(*user_folders) == arranged

    # Step 3: the user organizes: one file into Documents, one into the Trash. This is the new
    # state the app must leave alone.
    sandbox.move(lecture, sandbox.documents / "CSE120")
    sandbox.move(shot, sandbox.trash)
    organized = snapshot(*user_folders)

    # Step 4: the scan that notices those departures, then Mark Done, change only the database.
    report = sandbox.scan()
    sandbox.mark_done("IMG_4471.HEIC")

    assert report.done == {"moved": 1, "trashed": 1}
    assert sandbox.row("IMG_4471.HEIC")["done_reason"] == "manual"
    assert snapshot(*user_folders) == organized
