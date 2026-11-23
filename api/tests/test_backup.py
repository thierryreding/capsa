from __future__ import annotations

import sqlite3
from datetime import UTC, datetime, timedelta

import pytest

from capsa import accounts
from capsa.backup import BackupError, backup, sqlite_path
from capsa.cli import main
from capsa.db import make_engine
from capsa.migrate import upgrade
from capsa.passwords import Passwords


@pytest.fixture
def db_url(tmp_path):
    url = f"sqlite:///{tmp_path / 'capsa.sqlite'}"
    upgrade(url)
    engine = make_engine(url)
    with engine.begin() as conn:
        accounts.create_user(conn, Passwords.cheap(), "lena", "geheim123", "learner", now=1)
    engine.dispose()
    return url


def users_in(path) -> list[str]:
    with sqlite3.connect(path) as conn:
        return [r[0] for r in conn.execute("select username from users")]


def test_backup_is_a_complete_copy(db_url, tmp_path):
    target = backup(db_url, tmp_path / "backups", keep=3)
    assert target.name.startswith("capsa-") and target.suffix == ".sqlite"
    assert users_in(target) == ["lena"]


def test_backup_while_a_connection_holds_uncommitted_writes(db_url, tmp_path):
    writer = sqlite3.connect(sqlite_path(db_url))
    writer.execute("begin")
    writer.execute("update users set username = 'changing'")
    target = backup(db_url, tmp_path / "backups", keep=3)
    writer.rollback()
    writer.close()
    assert users_in(target) == ["lena"]  # only committed data


def test_keeps_the_newest_copies(db_url, tmp_path):
    t0 = datetime(2027, 1, 1, 3, 0, tzinfo=UTC)
    targets = [backup(db_url, tmp_path / "b", keep=3, now=t0 + timedelta(days=i)) for i in range(5)]
    remaining = sorted((tmp_path / "b").glob("capsa-*.sqlite"))
    assert remaining == targets[2:]
    assert not list((tmp_path / "b").glob("*.partial"))


def test_only_sqlite(tmp_path):
    with pytest.raises(BackupError, match="pg_dump"):
        backup("postgresql://u@h/capsa", tmp_path, keep=1)
    with pytest.raises(BackupError, match="does not exist"):
        backup(f"sqlite:///{tmp_path / 'missing.sqlite'}", tmp_path, keep=1)


def test_cli(db_url, tmp_path, capsys):
    assert main(["db", "backup", str(tmp_path / "b"), "--database-url", db_url]) == 0
    assert "backup written to" in capsys.readouterr().out
    assert main(["db", "backup", str(tmp_path / "b"), "--database-url", "postgresql://x/y"]) == 1
    assert "pg_dump" in capsys.readouterr().err
