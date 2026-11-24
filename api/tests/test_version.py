"""API and web app carry the same calendar version (SPEC 9)."""

import json
import re
from importlib.metadata import version
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_api_and_web_versions_match():
    web = json.loads((ROOT / "web" / "package.json").read_text())["version"]
    assert version("capsa") == web


def test_version_is_calendar_based():
    assert re.fullmatch(r"20\d\d\.(1[0-2]|[1-9])\.\d+", version("capsa"))
