"""Server configuration from environment variables (CAPSA_*)."""

from __future__ import annotations

import os
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path


def _bool(value: str) -> bool:
    v = value.strip().lower()
    if v in {"1", "true", "yes", "on"}:
        return True
    if v in {"0", "false", "no", "off"}:
        return False
    raise ValueError(f"not a boolean: {value!r}")


@dataclass(frozen=True)
class Settings:
    database_url: str = "sqlite:///capsa.sqlite"
    """SQLAlchemy URL. SQLite now; PostgreSQL later (SPEC 3, 13)."""

    profile_dir: Path = Path("profiles")
    """Folder with profile YAML files; searched recursively."""

    cookie_secure: bool = True
    """Set the Secure flag on the session cookie. Only disable for plain-HTTP tests."""

    session_days: int = 90
    """Sliding session lifetime (SPEC 8)."""

    login_max_failures: int = 5
    login_window_seconds: int = 15 * 60

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> Settings:
        env = os.environ if env is None else env
        d = cls()
        return cls(
            database_url=env.get("CAPSA_DATABASE_URL", d.database_url),
            profile_dir=Path(env.get("CAPSA_PROFILE_DIR", str(d.profile_dir))),
            cookie_secure=_bool(env.get("CAPSA_COOKIE_SECURE", str(d.cookie_secure))),
            session_days=int(env.get("CAPSA_SESSION_DAYS", d.session_days)),
            login_max_failures=int(env.get("CAPSA_LOGIN_MAX_FAILURES", d.login_max_failures)),
            login_window_seconds=int(env.get("CAPSA_LOGIN_WINDOW_SECONDS", d.login_window_seconds)),
        )
