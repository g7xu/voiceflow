"""Drives the real ContextInbox binary against a throwaway set of folders.

A test arranges files the way a browser or AirDrop would leave them, runs a scan with the actual
app, then reads the app's own SQLite database. Pause anywhere with ``breakpoint()`` and call
``sandbox.show()`` to see the database as a table. Set ``E2E_VERBOSE=1`` to print every command the
harness runs and the table after every scan.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import plistlib
import sqlite3
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

VERBOSE = os.environ.get("E2E_VERBOSE") == "1"


@dataclass
class Report:
    """What one scan did, as printed by ``--scan-print --json``."""

    added: int
    retracked: int
    done: dict[str, int]  # done reason -> count, e.g. {"moved": 1}
    folder_errors: dict[str, str]  # inbox path -> why it couldn't be listed
    calendar_skipped: str | None  # why event matching was skipped, if it was
    duration: float


class Sandbox:
    """One temp directory standing in for the user's Mac.

    ``Downloads/`` and ``Desktop/`` are the inbox folders, ``Trash/`` replaces ``~/.Trash`` and
    ``Documents/`` is where "organized" files go. The app's database is ``items.sqlite``.
    """

    def __init__(self, root: Path, binary: Path):
        self.root = root
        self.binary = binary
        self.downloads = root / "Downloads"
        self.desktop = root / "Desktop"
        self.trash = root / "Trash"
        self.documents = root / "Documents"
        for folder in (self.downloads, self.desktop, self.trash, self.documents):
            folder.mkdir()
        self.db = root / "items.sqlite"
        self.events: list[dict] = []
        # False runs scans with --no-calendar: no calendar at all (calendar turned off).
        self.calendar_available = True
        # False keeps the events but reports access as denied (revoked in System Settings).
        self.calendar_access = True

    # ---- Arranging files ------------------------------------------------------------------------

    def add(self, name: str, folder: Path | None = None, text: str = "test file\n") -> Path:
        """A plain local file, like a screenshot: no download metadata."""
        path = (folder or self.downloads) / name
        path.write_text(text)
        return path

    def add_folder(self, name: str, folder: Path | None = None) -> Path:
        path = (folder or self.downloads) / name
        (path / "inside").mkdir(parents=True)
        (path / "inside" / "file.txt").write_text("nested\n")
        return path

    def download(self, name: str, url: str, referrer: str | None = None, app: str = "Chrome",
                 folder: Path | None = None) -> Path:
        """A file as a browser saves it: kMDItemWhereFroms holds [download URL, referring page]
        and com.apple.quarantine names the app."""
        path = self.add(name, folder)
        where_froms = [url] + ([referrer] if referrer else [])
        self._xattr("-wx", "com.apple.metadata:kMDItemWhereFroms",
                    plistlib.dumps(where_froms, fmt=plistlib.FMT_BINARY).hex(), path)
        self._set_quarantine(path, app)
        return path

    def airdrop(self, name: str, folder: Path | None = None) -> Path:
        """AirDrop marks received files with the quarantine agent ``sharingd`` and no URL."""
        path = self.add(name, folder)
        self._set_quarantine(path, "sharingd")
        return path

    def move(self, path: Path, folder: Path, new_name: str | None = None) -> Path:
        target = folder / (new_name or path.name)
        target.parent.mkdir(parents=True, exist_ok=True)
        path.rename(target)
        return target

    def rename(self, path: Path, new_name: str) -> Path:
        return self.move(path, path.parent, new_name)

    # ---- Calendar -------------------------------------------------------------------------------

    def event(self, title: str, starts_in_min: float, ends_in_min: float, *, all_day: bool = False,
              location: str | None = None, calendar: str = "School", canceled: bool = False,
              declined: bool = False) -> None:
        """A calendar event relative to now: ``event("Lecture", -30, 30)`` is happening right now,
        which is also when files created in the test were added."""
        now = dt.datetime.now(dt.timezone.utc)
        self.events.append({
            "title": title,
            "start": (now + dt.timedelta(minutes=starts_in_min)).isoformat(timespec="seconds"),
            "end": (now + dt.timedelta(minutes=ends_in_min)).isoformat(timespec="seconds"),
            "allDay": all_day, "location": location, "calendar": calendar,
            "canceled": canceled, "declined": declined,
        })

    # ---- Running the app ------------------------------------------------------------------------

    def scan(self, days: int = 90) -> Report:
        """One scan by the real app, the same code the Scan button runs."""
        out = self._run("--scan-print", *self._scan_args(), "--days", str(days), "--json")
        data = json.loads(out.splitlines()[0])
        report = Report(added=data["added"], retracked=data["retracked"], done=data["done"],
                        folder_errors=data["folderErrors"], calendar_skipped=data.get("calendarSkipped"),
                        duration=data["durationSeconds"])
        if VERBOSE:
            print(f"  -> {report}")
            self.show()
        return report

    def prompt(self, destination: Path | None = None) -> str:
        """A scan followed by the Markdown prompt the Copy Prompt button produces."""
        extra = ["--destination", str(destination)] if destination else []
        return self._run("--prompt", *self._scan_args(), *extra)

    def mark_done(self, *names: str) -> None:
        """What the Mark Done button does for the tracked items with these names."""
        ids = [str(row["id"]) for row in self.rows() if row["name"] in names and row["status"] == "tracked"]
        assert len(ids) == len(names), f"expected tracked items {names}, found ids {ids}"
        self._run("--mark-done", "--db", str(self.db), *ids)

    # ---- Reading the app's database -------------------------------------------------------------

    def rows(self) -> list[dict]:
        """Every row of the app's ``item`` table, oldest first, plus a computed ``name``."""
        if not self.db.exists():
            return []
        with sqlite3.connect(self.db) as conn:
            conn.row_factory = sqlite3.Row
            rows = [dict(r) for r in conn.execute("SELECT * FROM item ORDER BY id")]
        for row in rows:
            row["name"] = Path(row["inbox_path"]).name
            row["day_events"] = json.loads(row["day_events"])
        return rows

    def row(self, name: str) -> dict:
        """The single row whose file was last seen in an inbox as ``name``."""
        matches = [r for r in self.rows() if r["name"] == name]
        assert len(matches) == 1, f"expected one row named {name!r}, found {len(matches)}"
        return matches[0]

    def show(self) -> str:
        """The item table in a readable form; prints it too, for use at a breakpoint."""
        columns = ["id", "status", "done_reason", "name", "saved_by", "source_url", "event_title",
                   "event_match", "current_path"]
        rows = [[self._cell(r.get(c)) for c in columns] for r in self.rows()]
        widths = [max(len(c), *(len(r[i]) for r in rows)) if rows else len(c) for i, c in enumerate(columns)]
        lines = ["  ".join(c.ljust(w) for c, w in zip(columns, widths))]
        lines += ["  ".join(v.ljust(w) for v, w in zip(r, widths)) for r in rows]
        text = "\n".join(lines) if rows else "(no items)"
        print(text)
        return text

    # ---- Internals ------------------------------------------------------------------------------

    def _scan_args(self) -> list[str]:
        args = ["--db", str(self.db), "--inbox", str(self.downloads), "--inbox", str(self.desktop),
                "--trash", str(self.trash)]
        if not self.calendar_available:
            return args + ["--no-calendar"]
        # Always a file, possibly empty, so a test never reads the real calendar on this Mac.
        events_file = self.root / "events.json"
        events_file.write_text(json.dumps(self.events))
        args += ["--events", str(events_file)]
        return args if self.calendar_access else args + ["--calendar-denied"]

    def _run(self, *args: str) -> str:
        command = [str(self.binary), *args]
        if VERBOSE:
            print("$ " + " ".join(command).replace(str(self.root), "<sandbox>"))
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        if result.returncode != 0:
            raise RuntimeError(f"{args[0]} failed ({result.returncode}): {result.stderr.strip()}")
        return result.stdout

    def _set_quarantine(self, path: Path, app: str) -> None:
        self._xattr("-w", "com.apple.quarantine", f"0081;{int(time.time()):x};{app};", path)

    @staticmethod
    def _xattr(mode: str, name: str, value: str, path: Path) -> None:
        # Python's os module has no setxattr on macOS, so this goes through /usr/bin/xattr.
        subprocess.run(["xattr", mode, name, value, str(path)], check=True)

    def _cell(self, value) -> str:
        if value is None:
            return "-"
        return str(value).replace(str(self.root), "<sandbox>")
