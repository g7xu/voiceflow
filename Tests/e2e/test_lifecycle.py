"""What happens to a tracked file as it leaves the inbox and comes back (spec §6).

Every test starts the same way: a file lands in an inbox and a first scan starts tracking it. Then
the user does something to the file in Finder, and the next scan decides what that means.
"""

import ctypes
import datetime as dt
import os
import struct
from pathlib import Path

from harness import Sandbox

# ---- macOS "date added", read straight from the filesystem -----------------------------------------

_libc = ctypes.CDLL(None, use_errno=True)
_ATTR_BIT_MAP_COUNT = 5
_ATTR_CMN_ADDEDTIME = 0x10000000


class _AttrList(ctypes.Structure):
    _fields_ = [("bitmapcount", ctypes.c_ushort), ("reserved", ctypes.c_uint16),
                ("commonattr", ctypes.c_uint32), ("volattr", ctypes.c_uint32), ("dirattr", ctypes.c_uint32),
                ("fileattr", ctypes.c_uint32), ("forkattr", ctypes.c_uint32)]


def date_added(path: Path) -> str:
    """The filesystem's current date added for ``path``, as UTC text in the same format as the
    app's ``added_at`` column, so the two compare directly."""
    request = _AttrList(_ATTR_BIT_MAP_COUNT, 0, _ATTR_CMN_ADDEDTIME, 0, 0, 0, 0)
    buffer = ctypes.create_string_buffer(64)
    if _libc.getattrlist(os.fsencode(path), ctypes.byref(request), buffer, len(buffer), 0) != 0:
        errno = ctypes.get_errno()
        raise OSError(errno, os.strerror(errno), str(path))
    _length, seconds, nanoseconds = struct.unpack_from("=Iqq", buffer.raw)
    added = dt.datetime.fromtimestamp(seconds, dt.timezone.utc)
    return f"{added:%Y-%m-%d %H:%M:%S}.{nanoseconds // 1_000_000:03d}"


# ---- Leaving the inbox ------------------------------------------------------------------------------


def test_moved_into_a_subfolder_counts_as_organized(sandbox: Sandbox):
    # Step 1: a lecture PDF lands in Downloads and the first scan starts tracking it.
    pdf = sandbox.download("lec05.pdf", url="https://cdn.example.edu/f/lec05.pdf")
    sandbox.scan()

    # Step 2: the user files it into Downloads/School. The inbox is only the top level of Downloads
    # (scans never recurse), so from the app's point of view the PDF has left.
    filed = sandbox.move(pdf, sandbox.downloads / "School")

    # Step 3: on the next scan, the bookmark taken at first sight follows the file, and the file it
    # leads to has the row's (volume, inode): a move, with the new location recorded.
    report = sandbox.scan()
    assert report.done == {"moved": 1}
    pdf_row = sandbox.row("lec05.pdf")
    assert pdf_row["status"] == "done"
    assert pdf_row["done_reason"] == "moved"
    assert pdf_row["current_path"] == str(filed)
    assert pdf_row["inbox_path"] == str(pdf), "inbox_path keeps where it was last seen in an inbox"

    # Step 4: the new School folder is itself a top-level entry of Downloads, so the same scan
    # started tracking it as an item of its own.
    assert report.added == 1
    assert sandbox.row("School")["status"] == "tracked"
    assert sandbox.row("School")["is_dir"] == 1


def test_moved_to_another_folder_and_renamed_is_followed(sandbox: Sandbox):
    # Step 1: a screenshot lands on the Desktop and is tracked.
    shot = sandbox.add("Screenshot 2026-10-11 at 10.14.03.png", folder=sandbox.desktop)
    sandbox.scan()

    # Step 2: it's filed into Documents/CSE120 under a meaningful name, in one move.
    filed = sandbox.move(shot, sandbox.documents / "CSE120", new_name="whiteboard-scheduling.png")

    # Step 3: a rename doesn't change the inode, so on the next scan the bookmark still leads to the
    # same file. The row keeps the name the file had in the inbox and points at the new one.
    report = sandbox.scan()
    assert report.done == {"moved": 1}
    row = sandbox.row("Screenshot 2026-10-11 at 10.14.03.png")
    assert row["done_reason"] == "moved"
    assert row["current_path"] == str(filed)


def test_moved_to_the_trash_is_done_as_trashed(sandbox: Sandbox):
    # Step 1: a junk download is tracked.
    junk = sandbox.add("document (3).pdf")
    sandbox.scan()

    # Step 2: the user drags it to the Trash (the sandbox's stand-in for ~/.Trash).
    in_trash = sandbox.move(junk, sandbox.trash)

    # Step 3: the next scan follows it as for any move, but a new home inside a trash root gets its
    # own reason.
    report = sandbox.scan()
    assert report.done == {"trashed": 1}
    row = sandbox.row("document (3).pdf")
    assert row["status"] == "done"
    assert row["done_reason"] == "trashed"
    assert row["current_path"] == str(in_trash), "still recoverable from the Trash, so the path is kept"


def test_deleted_file_is_done_as_gone(sandbox: Sandbox):
    # Step 1: an installer lands in Downloads and is tracked.
    installer = sandbox.add("Zoom.pkg")
    sandbox.scan()

    # Step 2: it's deleted outright (rm, or emptying the Trash).
    installer.unlink()

    # Step 3: on the next scan the bookmark has nothing to resolve to: the app knows the file left
    # but not where to.
    report = sandbox.scan()
    assert report.done == {"gone": 1}
    row = sandbox.row("Zoom.pkg")
    assert row["status"] == "done"
    assert row["done_reason"] == "gone"
    assert row["current_path"] is None


# ---- Changes that keep the file in the inbox -------------------------------------------------------


def test_renamed_in_place_is_still_the_same_tracked_item(sandbox: Sandbox):
    # Step 1: a download with a meaningless name is tracked; remember its row.
    doc = sandbox.download("document (3).pdf", url="https://canvas.example.edu/files/9/download")
    sandbox.scan()
    before = sandbox.row("document (3).pdf")

    # Step 2: the user renames it without leaving Downloads.
    renamed = sandbox.rename(doc, "CSE120-HW2.pdf")

    # Step 3: identity is the inode, not the name, so the next scan sees a known file at a new path:
    # nothing added, nothing done, and the existing row is updated in place.
    report = sandbox.scan()
    assert (report.added, report.retracked, report.done) == (0, 0, {})
    after = sandbox.row("CSE120-HW2.pdf")
    assert after["id"] == before["id"]
    assert after["status"] == "tracked"
    assert after["inbox_path"] == str(renamed)
    assert after["added_at"] == before["added_at"]
    assert after["source_url"] == before["source_url"]
    assert [r["name"] for r in sandbox.rows()] == ["CSE120-HW2.pdf"], "no row left under the old name"


def test_moved_to_another_inbox_stays_tracked(sandbox: Sandbox):
    # Step 1: a flyer lands in Downloads and is tracked.
    flyer = sandbox.add("career-fair-flyer.pdf")
    sandbox.scan()
    before = sandbox.row("career-fair-flyer.pdf")

    # Step 2: it's dragged to the Desktop, which is also an inbox. Changing folders makes macOS
    # stamp a new date added.
    on_desktop = sandbox.move(flyer, sandbox.desktop)
    assert date_added(on_desktop) > before["added_at"]

    # Step 3: it's still at the top level of an inbox, so it hasn't been organized. The next scan
    # keeps the same row, updates inbox_path, and keeps the date added from first sight.
    report = sandbox.scan()
    assert (report.added, report.retracked, report.done) == (0, 0, {})
    after = sandbox.row("career-fair-flyer.pdf")
    assert after["id"] == before["id"]
    assert after["status"] == "tracked"
    assert after["inbox_path"] == str(on_desktop)
    assert after["added_at"] == before["added_at"]


def test_unlisted_file_still_at_the_top_level_stays_tracked(sandbox: Sandbox):
    # Step 1: a PDF is tracked.
    pdf = sandbox.add("lec05.pdf")
    sandbox.scan()

    # Step 2: renaming it to a dotfile keeps it at the top level of Downloads, but listings skip
    # hidden files. That's how a scan sees a file it raced: missing from the listing, yet still in
    # the inbox when the bookmark is resolved.
    sandbox.rename(pdf, ".lec05.pdf")

    # Step 3: on the next scan the bookmark resolves to the top level of an inbox. That isn't
    # evidence the file left, so the row is left as it was.
    report = sandbox.scan()
    assert report.done == {}
    assert report.added == 0, "hidden files are never new items"
    assert sandbox.row("lec05.pdf")["status"] == "tracked"


# ---- Identity: (volume, inode), not the path -------------------------------------------------------


def test_new_file_saved_under_an_old_name_is_a_new_item(sandbox: Sandbox):
    # Step 1: notes.txt arrives and is tracked.
    original = sandbox.add("notes.txt", text="first version\n")
    sandbox.scan()

    # Step 2: before the next scan, it's deleted and a different notes.txt is saved at the same
    # path. The newcomer gets its own inode.
    original.unlink()
    sandbox.add("notes.txt", text="second version\n")

    # Step 3: an app keyed on paths would see "notes.txt, still there" and change nothing. Keyed on
    # (volume, inode), the next scan sees an unknown file arrive and a known one go. The old
    # bookmark resolves to the newcomer at the old path; the identity check rejects it: "gone".
    report = sandbox.scan()
    assert report.added == 1
    assert report.done == {"gone": 1}
    old, new = sandbox.rows()  # ordered by id: the old row was inserted first
    assert old["name"] == new["name"] == "notes.txt"
    assert old["inode"] != new["inode"]
    assert (old["status"], old["done_reason"], old["current_path"]) == ("done", "gone", None)
    assert new["status"] == "tracked"


def test_moved_away_then_name_reused_is_reported_gone(sandbox: Sandbox):
    # Step 1: a syllabus download is tracked.
    original = sandbox.download("syllabus.pdf", url="https://canvas.example.edu/files/1/download")
    sandbox.scan()

    # Step 2: before the next scan, the user files it into Documents, then downloads the syllabus
    # again, so a new file takes the old name in Downloads.
    sandbox.move(original, sandbox.documents)
    sandbox.download("syllabus.pdf", url="https://canvas.example.edu/files/1/download")

    # Step 3: on the next scan the bookmark tries the original path first and finds the newcomer
    # there. Its inode differs, so the app won't claim it as the original's new location, and it
    # has no other way to learn where the original went: "gone", not "moved".
    report = sandbox.scan()
    assert report.added == 1
    assert report.done == {"gone": 1}
    old, new = sandbox.rows()
    assert (old["status"], old["done_reason"], old["current_path"]) == ("done", "gone", None)
    assert new["status"] == "tracked"


# ---- Coming back ----------------------------------------------------------------------------------


def test_moved_out_and_back_is_retracked_as_the_same_item(sandbox: Sandbox):
    # Step 1: a lecture PDF is tracked; remember its row.
    pdf = sandbox.download("lec05.pdf", url="https://cdn.example.edu/f/lec05.pdf")
    sandbox.scan()
    first = sandbox.row("lec05.pdf")

    # Step 2: it's filed into Documents, and a scan marks it done.
    outside = sandbox.move(pdf, sandbox.documents)
    assert sandbox.scan().done == {"moved": 1}

    # Step 3: the user changes their mind and drags it back. macOS stamps a fresh date added on
    # arrival, so the file no longer says when it first landed.
    back = sandbox.move(outside, sandbox.downloads)
    assert date_added(back) > first["added_at"]

    # Step 4: the next scan finds the done row's inode at the top level, so that row comes back to
    # life instead of a new one being added. The original added_at survives: calendar matching runs
    # on it, and the file can no longer supply it.
    report = sandbox.scan()
    assert (report.added, report.retracked) == (0, 1)
    row = sandbox.row("lec05.pdf")
    assert row["id"] == first["id"]
    assert row["status"] == "tracked"
    assert row["done_reason"] is None
    assert row["current_path"] is None
    assert row["added_at"] == first["added_at"], "added_at is recorded once and never overwritten"


def test_marked_done_by_hand_is_never_retracked(sandbox: Sandbox):
    # Step 1: a tax return lands in Downloads and is tracked.
    sandbox.add("tax-return-2025.pdf")
    sandbox.scan()

    # Step 2: the user decides it lives in Downloads and clicks Mark Done.
    sandbox.mark_done("tax-return-2025.pdf")
    assert sandbox.row("tax-return-2025.pdf")["done_reason"] == "manual"

    # Step 3: two later scans. Each finds the file at the top level of Downloads, the same evidence
    # that brings a "moved" item back, but a manual decision outranks it.
    first = sandbox.scan()
    second = sandbox.scan()
    assert (first.added, first.retracked) == (0, 0)
    assert (second.added, second.retracked) == (0, 0)

    # Step 4: still one row, still done by hand.
    row = sandbox.row("tax-return-2025.pdf")
    assert row["status"] == "done"
    assert row["done_reason"] == "manual"
    assert len(sandbox.rows()) == 1


# ---- What a done row remembers --------------------------------------------------------------------


def test_done_item_keeps_where_it_came_from(sandbox: Sandbox):
    # Step 1: a lecture PDF is downloaded in Safari during a lecture, and the scan records all of it.
    sandbox.event("CSE 120 Lecture", -30, 30, location="Center Hall 105")
    pdf = sandbox.download("lec05.pdf", url="https://cdn.example.edu/f/lec05.pdf?token=SECRET",
                           referrer="https://canvas.example.edu/courses/120/files", app="Safari")
    sandbox.scan()

    # Step 2: it's filed into Documents/CSE120, and the next scan marks it done.
    sandbox.move(pdf, sandbox.documents / "CSE120")
    assert sandbox.scan().done == {"moved": 1}

    # Step 3: the row is now the record of where the file came from. The move reset its date added,
    # so the lecture could not be matched from the file again.
    row = sandbox.row("lec05.pdf")
    assert row["status"] == "done"
    assert row["source_url"] == "https://cdn.example.edu/f/lec05.pdf"
    assert row["referrer_url"] == "https://canvas.example.edu/courses/120/files"
    assert row["saved_by"] == "Safari"
    assert row["event_title"] == "CSE 120 Lecture"
    assert row["event_match"] == "during"
    assert row["event_location"] == "Center Hall 105"


# ---- When the scan can't see ----------------------------------------------------------------------


def test_unreadable_inbox_marks_nothing_done(sandbox: Sandbox):
    # Step 1: an old draft is tracked.
    draft = sandbox.add("old-draft.docx")
    sandbox.scan()

    # Step 2: the draft is deleted, and then Downloads stops being readable, as when the app loses
    # its Downloads permission.
    draft.unlink()
    sandbox.downloads.chmod(0o000)

    # Step 3: a failed listing says nothing about what's absent, so a scan now leaves the row
    # tracked and reports the failure instead.
    report = sandbox.scan()
    assert str(sandbox.downloads) in report.folder_errors
    assert report.done == {}
    assert sandbox.row("old-draft.docx")["status"] == "tracked"

    # Step 4: access comes back. A successful listing without the draft is real evidence.
    sandbox.downloads.chmod(0o755)
    report = sandbox.scan()
    assert report.folder_errors == {}
    assert report.done == {"gone": 1}
    assert sandbox.row("old-draft.docx")["done_reason"] == "gone"
