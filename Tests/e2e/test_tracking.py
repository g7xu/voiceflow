"""What the first scan records about new files, and that scanning again changes nothing."""

from harness import Sandbox


def test_first_scan_records_where_each_file_came_from(sandbox: Sandbox):
    # Step 1: arrange an inbox the way a real week leaves it.
    sandbox.download("lec05.pdf", url="https://cdn.example.edu/f/lec05.pdf?token=SECRET",
                     referrer="https://canvas.example.edu/courses/120/files")
    sandbox.airdrop("IMG_4471.HEIC")
    sandbox.add("Screenshot 2026-10-11 at 10.14.03.png", folder=sandbox.desktop)
    sandbox.add_folder("hackathon-starter")
    sandbox.add(".DS_Store")                       # hidden: never an inbox item
    sandbox.add("big-video.mp4.crdownload")        # Chrome still downloading: skipped
    sandbox.add_folder("installer.dmg.download")   # Safari's in-progress download is a folder
    sandbox.add("dataset.zip.part")                # Firefox still downloading

    # Step 2: run the app's scan.
    report = sandbox.scan()

    # Step 3: four items, with what the app could learn about each.
    assert report.added == 4
    assert sorted(r["name"] for r in sandbox.rows()) == [
        "IMG_4471.HEIC", "Screenshot 2026-10-11 at 10.14.03.png", "hackathon-starter", "lec05.pdf"]

    lecture = sandbox.row("lec05.pdf")
    assert lecture["source_url"] == "https://cdn.example.edu/f/lec05.pdf"   # ?token=SECRET stripped
    assert lecture["referrer_url"] == "https://canvas.example.edu/courses/120/files"
    assert lecture["saved_by"] == "Chrome"

    assert sandbox.row("IMG_4471.HEIC")["saved_by"] == "sharingd"           # shown as "AirDrop"
    assert sandbox.row("Screenshot 2026-10-11 at 10.14.03.png")["saved_by"] is None
    assert sandbox.row("hackathon-starter")["is_dir"] == 1

    # Every item gets a bookmark at first sight: it can't be created once the file has left.
    assert all(r["bookmark"] for r in sandbox.rows())
    assert all(r["status"] == "tracked" for r in sandbox.rows())


def test_second_scan_changes_nothing(sandbox: Sandbox):
    sandbox.download("lec05.pdf", url="https://cdn.example.edu/f/lec05.pdf")
    sandbox.scan()
    before = sandbox.rows()

    report = sandbox.scan()

    assert (report.added, report.retracked, report.done) == (0, 0, {})
    assert sandbox.rows() == before


def test_files_older_than_the_backfill_window_are_ignored(sandbox: Sandbox):
    sandbox.add("old-report.pdf")

    # A zero-day window starts at the moment of the scan, after the file was added.
    report = sandbox.scan(days=0)

    assert report.added == 0
    assert sandbox.rows() == []
