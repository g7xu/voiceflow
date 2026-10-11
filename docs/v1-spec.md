# ContextInbox — v1 Spec

> ContextInbox is a working name; the repo is `voiceflow`, but the voice angle no longer applies.
> Bundle ID `com.local.contextinbox`. Draft 2026-10-10.

## 1. Problem

Files arrive with context that the file itself doesn't hold: the page it came from, the lecture or
meeting you were in, the app that saved it. Within a day that context is gone, and
`Screenshot 2026-10-07 at 10.14.03.png` or `document (3).pdf` means nothing.

Claude can already organize files well. It can open a file and read its contents. What it can't
know is *where the file came from or what you were doing when it arrived*. This app supplies that
context and nothing else.

**One-line pitch:** Claude can organize your files but doesn't know where they came from. This
remembers.

**Lineage from voiceflow:** the same insight (information is lost when something is captured, not
when you look for it later) and the same loop (yellow → green becomes tracked → done). The AI
layer is dropped. Voiceflow had to fake it, and Claude now does that job better.

## 2. Principles

- **A pointer database, not a file manager.** The app never moves, renames, deletes, or writes to
  user files. It reads metadata and writes only its own database.
- **No AI in the app.** All organizing is handed off to Claude through a copyable prompt.
- **Only context the file doesn't hold.** No content extraction or previews in the prompt. Claude
  can open the files itself.
- **Scan on demand, no background watcher.** macOS keeps the date added and the download source on
  disk, and your calendar keeps its history. So context can be rebuilt after the fact, including
  for the pile that already exists on day one. Only location and "which app was in front" are lost
  if not captured live, and both are v2.

## 3. User flow

1. **First run.** Pick inbox folders (defaults `~/Downloads`, `~/Desktop`), grant calendar access,
   choose which calendars count, and set a backfill window (default 90 days). Optionally set a
   destination root (e.g. `~/Documents`).
2. **Scan.** Every top-level item in each inbox folder becomes a tracked row with its context.
3. **Review.** The list is grouped by calendar event, newest group first.
4. **Copy prompt.** Copies Markdown for the selected rows, or for all tracked rows if nothing is
   selected. Paste it into Claude Code or Cowork.
5. **Claude organizes.** It proposes a plan, you approve, and it moves the files.
6. **Rescan.** Files that left the top level of an inbox are marked done automatically. You can also
   mark files done by hand (things you're keeping where they are).

## 4. Context captured per item

| Field | Source | Can be backfilled? | Example |
|---|---|---|---|
| Path, name, kind | directory listing | yes | `~/Downloads/lec05.pdf` |
| Date added | `URLResourceValues.addedToDirectoryDate` | yes, until the file moves | Oct 7 10:02 |
| Source URL + referrer page | `com.apple.metadata:kMDItemWhereFroms` xattr (binary plist array) | yes | `canvas.example.edu/courses/123/files` |
| App that saved it | `com.apple.quarantine` xattr, agent field | yes | Chrome; `sharingd` → AirDrop |
| Calendar event | EventKit, matched on date added (§5) | yes, as far back as Calendar has synced | "CSE 120 Lecture" |
| Event location | the matched event's location field | yes | Center Hall 105 |
| All-day events that day | EventKit | yes | "Career Fair" |

Measured on this Mac (Downloads, last 60 days, 56 items): 30 had a source URL and 53 had a saving
app.

**URLs are stored without user info, query strings or fragments.** Signed download links carry
access tokens, and the prompt gets pasted elsewhere. Only http(s) entries are kept: Mail writes the
sender and subject into the same attribute, and `data:`/`blob:` URLs are useless or huge. For
display, the referring page shows as host + path, and the download URL as host only, because
download paths can embed tokens too.

**Not captured in v1:** event notes/descriptions (long, and often contain meeting passcodes),
attendees, location, the app in front.

## 5. Calendar matching

For an item added at time `t`, considering timed events in the enabled calendars:

1. **During:** an event with `start ≤ t < end`. If several overlap, pick the one that started
   latest (the most specific).
2. **After:** otherwise, the event with the latest `end` where `t − 2h ≤ end ≤ t`. The bound is
   inclusive so a file added exactly as an event ends still matches it. The window is a setting.
3. **None:** otherwise, no event.

Canceled events and events you declined never match. All-day events never match as the event;
their titles are attached as "that day" context. Timed events longer than 12 hours ("Trip to
NYC", "On call") are treated the same way, since they would otherwise claim every file added
during them. Birthday and subscribed calendars (holidays, sports) are off by default.

Ties: among overlapping events the latest start wins, then the earliest end, then the title, so
the result never depends on fetch order.

Each scan fetches events once, from the oldest tracked item's date added (or the backfill start,
whichever is earlier) to now, and matches in memory. Tracked items are re-matched on each scan,
since events can sync late. Done items are frozen.

**If calendar access is missing, or none of the enabled calendars still exist, the scan skips
re-matching and keeps existing event fields.** Clearing them would destroy context that can't be
rebuilt once the date added resets. The UI shows a warning instead.

### Calendar sources

All three go through EventKit. No OAuth and no per-provider API code.

| Source | v1 path | Limits |
|---|---|---|
| Google Calendar | add the account in System Settings → Internet Accounts | — |
| Outlook / Microsoft 365 | same, as an Exchange account | Some orgs block this. Fallback: subscribe to the calendar's published ICS link in Calendar.app |
| Notion Calendar | nothing to add: it displays calendars from your connected accounts, which EventKit already sees | Notion database dates that appear only in Notion Calendar are invisible. No public API |

Links that open an event in Outlook, Google, or Notion Calendar are out of scope for v1.

## 6. Identity and done detection

- **Inbox = the top level of a watched folder.** Scans don't recurse. Top-level directories
  (unzipped folders, bundles) count as single items. Skip hidden files and in-progress downloads
  (`.crdownload`, `.download`, `.part`).
- **Identity = (volume UUID, inode).** It stays the same through renames and moves on the same
  volume. A file edited by a safe-save app gets a new inode and shows up as a new item. That's
  acceptable.
- **Inbox folders must be on a volume with persistent IDs** (APFS, HFS+). Others, such as exFAT
  drives, are refused, since their inode numbers aren't stable.
- **Done = no longer at the top level of an inbox.** This needs no bookmark, so it still works when
  files move to Google Drive or another volume.
  - The bookmark resolves, and the resolved file has the same (volume UUID, inode) → `moved`, and
    `current_path` is recorded. Inside the Trash → `trashed`.
  - The bookmark doesn't resolve, or resolves to a different file (a new file saved under the old
    name) → `gone`.
  - It resolves to the top level of an inbox → left tracked; the scan caught it mid-move.
- **`added_at` is recorded once and never overwritten**, including when an item re-tracks. macOS
  resets the date added when a file moves to another folder (and moving back resets it again).
- **A bookmark is created when an item is first seen**, because it can't be created after the file
  leaves. In v1 it only answers "where did it go"; v2's CLI/MCP relies on it.
- **A folder that fails to list aborts the scan for that folder.** It never marks items done. Only a
  successful listing that lacks the item does that.
- **Items marked done by hand never re-track.** Items done because they moved re-track if they
  reappear at the top level.

## 7. Data model

SQLite at `~/Library/Application Support/ContextInbox/items.sqlite`, through GRDB (pinned to an
exact version) in WAL mode, with schema changes as GRDB migrations. Settings go in `config.json`
beside it. Dates are stored as UTC text.

```sql
CREATE TABLE item (
  id             INTEGER PRIMARY KEY,
  volume_uuid    TEXT    NOT NULL,
  inode          INTEGER NOT NULL,
  is_dir         INTEGER NOT NULL,
  bookmark       BLOB,
  inbox_path     TEXT    NOT NULL,  -- absolute path when last seen in an inbox
  current_path   TEXT,              -- after leaving; NULL when the bookmark won't resolve
  added_at       TEXT    NOT NULL,
  source_url     TEXT,
  referrer_url   TEXT,
  saved_by       TEXT,
  event_title    TEXT,
  event_start    TEXT,
  event_end      TEXT,
  event_location TEXT,
  event_calendar TEXT,
  event_match    TEXT CHECK (event_match IN ('during', 'after')),
  day_events     TEXT,              -- JSON array of all-day titles
  status         TEXT NOT NULL DEFAULT 'tracked' CHECK (status IN ('tracked', 'done')),
  done_reason    TEXT CHECK (done_reason IN ('moved', 'trashed', 'gone', 'manual')),
  first_seen_at  TEXT NOT NULL,
  status_at      TEXT NOT NULL,
  UNIQUE (volume_uuid, inode)
);
```

Event fields are copied rather than referenced by EventKit ID. Events get edited and deleted, and
the v2 CLI has to read this file without calendar access.

## 8. The prompt

Grouped by event, the same way as the list. Absolute paths. Times in local time.

```markdown
# Files to organize

These files landed in my inbox folders (~/Downloads, ~/Desktop). For each one I've noted where it
came from and what was on my calendar when it arrived; you can't get that from the files themselves.
Open any file if you need its contents.

Destination: organize into subfolders of ~/Documents.

1. Propose a folder structure and a destination for every file. Show me the plan before moving anything.
2. Once I approve, move them with `mv` using the absolute paths below. Rename only files whose names
   carry no meaning (screenshots, "document (3).pdf", IMG_1234).
3. Don't delete anything. List likely junk under "Suggest deleting" and leave it in place.

## During "CSE 120 Lecture" — Wed Oct 7, 10:00–11:20 · Center Hall 105 · calendar: School
- `/Users/you/Downloads/lec05-scheduling.pdf` — added 10:02 · from canvas.example.edu/courses/123/files (Chrome)
- `/Users/you/Desktop/Screenshot 2026-10-07 at 10.14.03.png` — added 10:14

## After "1:1 with Sam" — Thu Oct 8, ended 14:30 · calendar: Work
- `/Users/you/Downloads/Q3-plan-v2.xlsx` — added 14:41 · from outlook.office.com (Chrome)

## No calendar event
- `/Users/you/Downloads/IMG_4471.HEIC` — added Fri Oct 9 21:03 · AirDrop · that day: Career Fair
```

The "Destination" line appears only when a destination root is set. A path that contains a
backtick is wrapped in a longer backtick run so the code span doesn't break.

## 9. UI

One SwiftUI window. No menu bar item in v1.

- **Toolbar:** Scan · Copy prompt · Mark done · filter `Tracked (n) | Done`.
- **List:** event-group headers, then rows showing name, time added, source domain or app, and a
  checkbox.
- **Row actions:** Quick Look (space), Reveal in Finder, Copy path, Mark done.
- **Done view:** shows the reason and `current_path` ("moved to ~/Documents/School/CSE120/").
- **Scan triggers:** launch, window focus, and the Scan button.
- **Settings:** inbox folders, calendars, match window, backfill window, destination root.

## 10. Platform

- macOS 14+ (`requestFullAccessToEvents`). Swift 6 + SwiftUI as a SwiftPM package; no Xcode
  project, and only the Command Line Tools are required.
- `scripts/build-app.sh` assembles `build/ContextInbox.app` from the release product and signs it.
- Tests are an executable target, run with `swift run inbox-tests`. With only the Command Line
  Tools, plain `swift test` finds no swift-testing tests (on this Mac it hangs).
- Headless roles (`--spike`, later `--scan-print`, `--prompt`) live in the same binary and run via
  `scripts/headless.sh`, which launches through LaunchServices. Running the binary directly would
  borrow the terminal's privacy grants and hide permission problems.
- Not sandboxed, not on the App Store.
- Info.plist usage strings: `NSCalendarsFullAccessUsageDescription`,
  `NSDownloadsFolderUsageDescription`, `NSDesktopFolderUsageDescription`.
- Signed with a self-signed "ContextInbox Dev" code-signing cert, not ad-hoc. macOS ties privacy
  grants to the code signature, and an ad-hoc signature changes on every build.
- Code layout: `Sources/InboxCore` (scan, metadata, matching, store, prompt) has no UI imports, so
  v2's CLI can reuse it. `Sources/ContextInbox` holds the SwiftUI layer and the headless roles.

## 11. Non-goals (v1)

- Watching folders in the background or capturing context live (location, the app in front): v2.
- Any AI, or reading file contents.
- Moving or renaming files. Claude does that.
- MCP server / CLI: v2.
- Links that open events in Outlook, Google, or Notion Calendar.
- Recursing into subfolders, or tracking non-inbox folders.
- Syncing between Macs.

## 12. Acceptance criteria

- [ ] After first-run setup, a scan lists every top-level item in `~/Downloads` and `~/Desktop`
      added within the backfill window, each with its date added.
- [ ] A file downloaded in Chrome shows its source domain and "Chrome". The URL shown has no query
      string.
- [ ] Against a test calendar event 10:00–11:00: a file added at 10:30 matches as *during*, 11:30 as
      *after*, and 13:30 as no event (2 h window).
- [ ] Two overlapping events: the one that started later wins.
- [ ] Copy prompt produces Markdown matching §8, grouped by event, with absolute paths. Pasted into
      Claude Code, it produces a plan without further explanation.
- [ ] After files are moved out of the inbox or into a subfolder of it, the next scan marks them
      `moved` and shows the new path. Trashed files show `trashed`.
- [ ] A file moved into the Google Drive folder is marked done (`moved` or `gone`), never left
      tracked.
- [ ] A file marked done by hand that stays in Downloads never reappears as tracked.
- [ ] Revoking Downloads access, then scanning, marks nothing done and shows an error.
- [ ] The app's only file writes are inside its Application Support folder.
- [ ] Scanning 1,000 items takes under 2 s.

## 13. Build plan

**0. Spike first: checks the "backfill instead of watching" premise on this Mac.** Run with
`scripts/headless.sh --spike <role>`.

| Check | Pass | If it fails | Result |
|---|---|---|---|
| `swift run inbox-tests` exits 0 on pass, non-zero on failure | both | Plain `expect()` harness | Pass (exit 0 / 1). `swift test` hangs |
| Signature is a cert leaf, not a cdhash; a rebuild doesn't re-prompt | both | Stay ad-hoc and accept prompts | Cert leaf, accepted by `codesign` while untrusted. Re-prompt check pending the next rebuild |
| `metadata`: date added, WhereFroms and quarantine from inside the bundle match `mdls`/`xattr` | values match | Investigate permissions before building anything else | Pass, 10/10 rows |
| `calendar`: events from 90 days ago for your Google and Outlook accounts | events come back | Backfill only goes as far as Calendar has synced. Weekly scans still work | Access works; **no Google account in macOS Calendar yet** (only iCloud, a subscription, Birthdays). Subscribed calendar history goes back over a year. Re-run after adding Google |
| A Microsoft 365 account can be added to macOS Calendar | events appear in Calendar.app | ICS subscription; if blocked too, Outlook moves to v2 (Graph API) | Pending |
| `bookmark-*`: resolves after a move into Google Drive, into the Trash, and when a new file takes the old name | new path / Trash path / identity mismatch | Marked `gone`. Acceptable for v1 | Drive: new path, same inode. Trash: Trash path, same inode. New file under the old name: resolves to the **new** file, so the identity check is required. All three flag the bookmark stale |
| Renaming a file inside Downloads resets its date added | resets (expected) | — | **Does not reset** on macOS 26.5 (date added and inode unchanged). Moving to another folder does reset it |

1. `InboxCore`: scan + metadata, shown by a `--scan-print` role.
2. `InboxCore`: calendar matching, with unit tests for §5's rules.
3. `InboxCore`: GRDB store + done detection (§6).
4. `InboxCore`: prompt generator, snapshot-tested against §8.
5. `ContextInbox`: SwiftUI window, first-run flow, settings.
6. Use it on your real Downloads for a week, then revisit §14.

## 14. Open questions

1. **Name.** ContextInbox is a placeholder. Renaming means a new bundle ID, which resets privacy
   grants and needs a data-folder migration, so decide before anyone else installs it. Rename the
   repo too, or keep `voiceflow` as the umbrella?
2. **Backfill default.** Is 90 days right for the first scan of a large existing pile, or would
   the prompt be too long? Should it be chunked?
3. **Prompt size.** Past roughly 100 items, split the prompt by group or by week?
4. **Done history.** Keep done rows forever (they're what v2's "where did that file go?" answers
   from) or prune after N months?
5. **Write-back.** Should the prompt ask Claude to finish with an old → new path list, which the app
   imports for files whose bookmarks failed?

## 15. v2 preview

- Menu bar watcher (FSEvents) that captures context that disappears at arrival: named places
  (Home, Library) and the app/window in front.
- CLI + MCP server reading `items.sqlite`, so Claude Code and Cowork can query the inbox and
  "where did X go" directly, with no copy-paste.
- Links that open each event in its calendar app.
