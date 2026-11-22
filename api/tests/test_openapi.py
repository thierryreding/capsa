from __future__ import annotations

import json

from conftest import REPO

from capsa.app import create_app
from capsa.config import Settings

SNAPSHOT = REPO / "schemas" / "openapi.json"


def test_openapi_snapshot_is_current():
    """The frontend types are generated from schemas/openapi.json; keep it in sync.

    Regenerate with: uv run capsa openapi -o schemas/openapi.json
    (then: cd web && npm run gen)
    """
    current = create_app(Settings()).openapi()
    assert json.loads(SNAPSHOT.read_text(encoding="utf-8")) == current
