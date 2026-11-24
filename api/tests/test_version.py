"""The version comes from VERSION at the repository root (SPEC 9)."""

import re
from importlib.metadata import version
from pathlib import Path

VERSION = Path(__file__).resolve().parents[2] / "VERSION"


def test_version_is_calendar_based():
    # YYYY.MM for the first release of a month, then YYYY.MM.N
    assert re.fullmatch(r"20\d\d\.(1[0-2]|[1-9])(\.[1-9]\d*)?", VERSION.read_text().strip())


def test_installed_package_carries_the_version():
    assert version("capsa") == VERSION.read_text().strip()
