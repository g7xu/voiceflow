# How to run and step through the end-to-end tests

The tests in `Tests/e2e/` drive the real ContextInbox binary from Python. Each test arranges files
the way a browser or AirDrop would leave them, runs a scan with the app, and reads the app's own
SQLite database. Stepping through one is the quickest way to see what the scanner does.

Requires the Xcode Command Line Tools and [uv](https://docs.astral.sh/uv/). All commands run from
`Tests/e2e/`; the first run builds the app (about a minute).

## Run them

```bash
uv run pytest
```

One file, or one test:

```bash
uv run pytest test_lifecycle.py
```

```bash
uv run pytest "test_tracking.py::test_first_scan_records_where_each_file_came_from"
```

## Watch every step

`E2E_VERBOSE=1` prints each app command the harness runs and the database table after every scan.
`-s` lets the output through:

```bash
E2E_VERBOSE=1 uv run pytest -s test_tracking.py
```

## Step through with pdb

`--trace` stops at the first line of each test:

```bash
uv run pytest --trace "test_lifecycle.py::test_moved_out_and_back_is_retracked_as_the_same_item"
```

Useful commands at the `(Pdb)` prompt:

| Command | What it does |
|---|---|
| `n` | Run the next line (a whole scan is one line) |
| `s` | Step into a harness call, e.g. to see the exact app command |
| `sandbox.show()` | Print the app's database as a table |
| `pp sandbox.row("lec05.pdf")` | Every column of one item |
| `p report` | What the last scan did: added, re-tracked, done |
| `!import os; os.listdir(sandbox.downloads)` | What's actually in the inbox right now |
| `c` | Continue to the end of the test |

To stop somewhere specific instead, put `breakpoint()` on a line in the test. To land in the
debugger only when a test fails, use `--pdb`.

## Step through in VS Code or PyCharm

Point the editor at the test environment's interpreter: `Tests/e2e/.venv/bin/python` (created by
the first `uv run`). Then, in VS Code, add this to `.vscode/launch.json` and set breakpoints in any
test file:

```json
{
  "name": "e2e tests",
  "type": "debugpy",
  "request": "launch",
  "module": "pytest",
  "args": ["-s", "test_lifecycle.py"],
  "cwd": "${workspaceFolder}/Tests/e2e",
  "python": "${workspaceFolder}/Tests/e2e/.venv/bin/python"
}
```

In PyCharm, set the project interpreter to the same path, then right-click a test and choose Debug.

## Look at the database yourself

While paused, `p sandbox.db` prints the database path. Open it from another terminal:

```bash
sqlite3 -readonly -header -column /path/from/pdb/items.sqlite "SELECT id, status, done_reason, inbox_path FROM item"
```

pytest keeps the temp folders of the last few runs, so the path stays readable after the test ends.

## Step into the Swift code

The harness only runs the binary; to step through the app itself, run the same command under
lldb. Copy a command from the `E2E_VERBOSE=1` output (replace `<sandbox>` with the temp path from
`p sandbox.root`) and prefix it:

```bash
lldb -- .build/debug/ContextInbox --scan-print --db /tmp/…/items.sqlite --inbox /tmp/…/Downloads --json
```

Run that from the repository root, then `breakpoint set --name scan` and `run`.
