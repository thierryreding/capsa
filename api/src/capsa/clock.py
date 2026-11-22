"""Time as integer milliseconds since the epoch (UTC), the unit stored in the database."""

from __future__ import annotations

import time
from collections.abc import Callable
from datetime import UTC, datetime

Clock = Callable[[], int]


def now_ms() -> int:
    return time.time_ns() // 1_000_000


def to_datetime(ms: int) -> datetime:
    return datetime.fromtimestamp(ms / 1000, tz=UTC)


def from_datetime(dt: datetime) -> int:
    if dt.tzinfo is None:
        raise ValueError("datetime must be timezone-aware")
    return int(dt.timestamp() * 1000)
