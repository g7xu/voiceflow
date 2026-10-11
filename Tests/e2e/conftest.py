import subprocess
from pathlib import Path

import pytest

from harness import Sandbox

REPO = Path(__file__).resolve().parents[2]


@pytest.fixture(scope="session")
def binary() -> Path:
    """The debug build of the app, built once per test session from this checkout."""
    subprocess.run(["swift", "build", "--product", "ContextInbox"], cwd=REPO, check=True, capture_output=True)
    bin_dir = subprocess.run(["swift", "build", "--show-bin-path"], cwd=REPO, check=True, capture_output=True,
                             text=True).stdout.strip()
    return Path(bin_dir) / "ContextInbox"


@pytest.fixture
def sandbox(binary: Path, tmp_path: Path) -> Sandbox:
    box = Sandbox(tmp_path, binary)
    yield box
    # A test may have made an inbox unreadable; restore it so pytest can clean up.
    for folder in (box.downloads, box.desktop):
        if folder.exists():
            folder.chmod(0o755)
