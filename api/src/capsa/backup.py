"""Database backups (SPEC 9): consistent online copies of the SQLite database."""

from __future__ import annotations

import sqlite3
from datetime import UTC, datetime
from pathlib import Path

from sqlalchemy.engine import make_url

PREFIX = "capsa-"
SUFFIX = ".sqlite"


class BackupError(RuntimeError):
    pass


def sqlite_path(database_url: str) -> Path:
    url = make_url(database_url)
    if url.get_backend_name() != "sqlite" or not url.database or url.database == ":memory:":
        raise BackupError(
            "backups are built in for SQLite files only; use the database's own tools "
            "(e.g. pg_dump) otherwise"
        )
    return Path(url.database)


def backup(database_url: str, directory: Path, keep: int, now: datetime | None = None) -> Path:
    """Copy the database into `directory` and keep only the newest `keep` copies.

    Uses SQLite's online backup API, which gives a consistent copy while the server
    keeps writing (also in WAL mode).
    """
    source = sqlite_path(database_url)
    if not source.exists():
        raise BackupError(f"database file {source} does not exist")
    directory.mkdir(parents=True, exist_ok=True)
    stamp = (now or datetime.now(UTC)).strftime("%Y%m%d-%H%M%S")
    target = directory / f"{PREFIX}{stamp}{SUFFIX}"
    partial = target.with_suffix(".partial")
    with sqlite3.connect(source) as src, sqlite3.connect(partial) as dst:
        src.backup(dst)
    partial.replace(target)  # only complete copies carry the final name
    prune(directory, keep)
    return target


def prune(directory: Path, keep: int) -> list[Path]:
    copies = sorted(directory.glob(f"{PREFIX}*{SUFFIX}"))
    old = copies[:-keep] if keep > 0 else copies
    for path in old:
        path.unlink()
    return old
