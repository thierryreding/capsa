"""Usage figures for monitoring growth (see SPEC 13: event snapshots)."""

from __future__ import annotations

import os
from dataclasses import asdict, dataclass

from sqlalchemy import Connection, func, select

from capsa.db import events, sessions, user_settings, users

DAY_MS = 24 * 60 * 60 * 1000
# Above this many events per account, snapshots of the learning state are worth it
# (shorter first sync on new devices, faster replay); see SPEC 13.
SNAPSHOT_THRESHOLD = 100_000


@dataclass(frozen=True)
class AccountUsage:
    username: str
    role: str
    events: int
    events_30d: int
    devices: int
    last_event_at: int | None


@dataclass(frozen=True)
class Usage:
    accounts: list[AccountUsage]
    total_events: int
    settings: int
    sessions: int
    database_bytes: int | None

    @property
    def over_threshold(self) -> list[str]:
        return [a.username for a in self.accounts if a.events >= SNAPSHOT_THRESHOLD]

    def as_dict(self) -> dict:
        return {**asdict(self), "over_threshold": self.over_threshold}


def sqlite_size(database: str | None) -> int | None:
    """Size of a SQLite database including its WAL file; None for other databases."""
    if not database or database == ":memory:" or not os.path.exists(database):
        return None
    return sum(os.path.getsize(p) for p in (database, database + "-wal") if os.path.exists(p))


def usage(conn: Connection, now: int, database_bytes: int | None = None) -> Usage:
    since = now - 30 * DAY_MS
    per_user = (
        select(
            events.c.user_id,
            func.count().label("events"),
            func.count().filter(events.c.ts >= since).label("events_30d"),
            func.count(events.c.device_id.distinct()).label("devices"),
            func.max(events.c.ts).label("last_event_at"),
        )
        .group_by(events.c.user_id)
        .subquery()
    )
    rows = conn.execute(
        select(users.c.username, users.c.role, per_user)
        .select_from(users.outerjoin(per_user, per_user.c.user_id == users.c.id))
        .order_by(per_user.c.events.desc().nulls_last(), users.c.username_key)
    ).all()
    accounts = [
        AccountUsage(
            username=r.username,
            role=r.role,
            events=r.events or 0,
            events_30d=r.events_30d or 0,
            devices=r.devices or 0,
            last_event_at=r.last_event_at,
        )
        for r in rows
    ]
    count = lambda table: conn.execute(select(func.count()).select_from(table)).scalar_one()  # noqa: E731
    return Usage(
        accounts=accounts,
        total_events=sum(a.events for a in accounts),
        settings=count(user_settings),
        sessions=count(sessions),
        database_bytes=database_bytes,
    )
