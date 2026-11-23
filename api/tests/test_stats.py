from __future__ import annotations

import json

from sqlalchemy import insert

from capsa import accounts
from capsa.cli import main
from capsa.db import events, make_engine
from capsa.migrate import upgrade
from capsa.passwords import Passwords
from capsa.stats import DAY_MS, SNAPSHOT_THRESHOLD, sqlite_size, usage

NOW = 1_800_000_000_000


def add_events(conn, user_id, count, ts, device="d1"):
    conn.execute(
        insert(events),
        [
            dict(id=f"{user_id}-{device}-{ts}-{i}", user_id=user_id, device_id=device,
                 profile_id="p", entry_id="e", direction="src_to_tr", mode="typed",
                 correct=True, ts=ts, received_at=ts)
            for i in range(count)
        ],
    )  # fmt: skip


def setup(tmp_path):
    url = f"sqlite:///{tmp_path / 'db.sqlite'}"
    upgrade(url)
    engine = make_engine(url)
    with engine.begin() as conn:
        pw = Passwords.cheap()
        lena = accounts.create_user(conn, pw, "lena", "geheim123", "learner", 1)
        max_ = accounts.create_user(conn, pw, "max", "geheim123", "learner", 1)
        accounts.create_user(conn, pw, "papa", "geheim123", "admin", 1)
        add_events(conn, lena.id, 3, NOW - 40 * DAY_MS)
        add_events(conn, lena.id, 2, NOW - DAY_MS, device="d2")
        add_events(conn, max_.id, 1, NOW - 2 * DAY_MS)
    return url, engine


def test_usage(tmp_path):
    url, engine = setup(tmp_path)
    with engine.connect() as conn:
        u = usage(conn, NOW, database_bytes=123)
    engine.dispose()
    assert [(a.username, a.events, a.events_30d, a.devices) for a in u.accounts] == [
        ("lena", 5, 2, 2),
        ("max", 1, 1, 1),
        ("papa", 0, 0, 0),
    ]
    assert u.accounts[0].last_event_at == NOW - DAY_MS
    assert u.accounts[2].last_event_at is None
    assert (u.total_events, u.database_bytes, u.over_threshold) == (6, 123, [])


def test_threshold(tmp_path):
    url, engine = setup(tmp_path)
    with engine.begin() as conn:
        lena = accounts.find_user(conn, "lena")
        add_events(conn, lena.id, SNAPSHOT_THRESHOLD - 5, NOW, device="bulk")
        assert usage(conn, NOW).over_threshold == ["lena"]
    engine.dispose()


def test_sqlite_size(tmp_path):
    assert sqlite_size(None) is None
    assert sqlite_size(str(tmp_path / "missing")) is None
    db = tmp_path / "x.sqlite"
    db.write_bytes(b"x" * 10)
    (tmp_path / "x.sqlite-wal").write_bytes(b"y" * 5)
    assert sqlite_size(str(db)) == 15


def test_cli(tmp_path, capsys):
    url, engine = setup(tmp_path)
    engine.dispose()
    assert main(["stats", "--database-url", url]) == 0
    out = capsys.readouterr().out.splitlines()
    assert out[0].startswith("database: ") and "6 events" in out[0]
    assert out[2].split()[:3] == ["lena", "learner", "5"]  # the CLI uses the real clock
    assert main(["stats", "--json", "--database-url", url]) == 0
    data = json.loads(capsys.readouterr().out)
    assert data["total_events"] == 6 and data["database_bytes"] > 0
    assert [a["username"] for a in data["accounts"]] == ["lena", "max", "papa"]
