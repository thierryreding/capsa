from __future__ import annotations

from pathlib import Path

import pytest

from capsa.config import Settings


def test_defaults():
    s = Settings.from_env({})
    assert s.database_url == "sqlite:///capsa.sqlite"
    assert s.cookie_secure is True
    assert s.session_days == 90


def test_from_env():
    s = Settings.from_env(
        {
            "CAPSA_DATABASE_URL": "sqlite:////data/x.sqlite",
            "CAPSA_PROFILE_DIR": "/profiles",
            "CAPSA_COOKIE_SECURE": "false",
            "CAPSA_SESSION_DAYS": "30",
        }
    )
    assert s.database_url == "sqlite:////data/x.sqlite"
    assert s.profile_dir == Path("/profiles")
    assert s.cookie_secure is False
    assert s.session_days == 30


def test_bad_boolean():
    with pytest.raises(ValueError, match="not a boolean"):
        Settings.from_env({"CAPSA_COOKIE_SECURE": "maybe"})
