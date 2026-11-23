"""Leitner boxes, ported from web/src/lib/learning/leitner.ts (SPEC 7, 14).

Pure functions. The client computes learning state on the device; the server uses this
port for statistics shown to parents. Both must pass vectors/leitner.json.
"""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from dataclasses import dataclass

DEFAULT_INTERVALS_DAYS = (0, 1, 3, 7, 21)
MAX_CLOCK_AHEAD_MS = 24 * 60 * 60 * 1000
DAY_MS = 24 * 60 * 60 * 1000


@dataclass(frozen=True)
class Config:
    intervals_days: Sequence[int] = DEFAULT_INTERVALS_DAYS
    utc_offset_minutes: int = 0


@dataclass(frozen=True)
class AnswerEvent:
    id: str
    profile_id: str
    entry_id: str
    direction: str
    correct: bool
    ts: int
    received_at: int | None = None


@dataclass(frozen=True)
class CardState:
    box: int
    last_at: int
    last_correct: bool
    correct_count: int
    wrong_count: int


def card_key(profile_id: str, entry_id: str, direction: str) -> str:
    return f"{profile_id}|{entry_id}|{direction}"


def effective_time(e: AnswerEvent) -> int:
    if e.received_at is not None and e.ts > e.received_at + MAX_CLOCK_AHEAD_MS:
        return e.received_at
    return e.ts


def apply_answer(state: CardState | None, correct: bool, at: int, config: Config) -> CardState:
    boxes = len(config.intervals_days)
    box = state.box if state else 1
    return CardState(
        box=min(box + 1, boxes) if correct else 1,
        last_at=at,
        last_correct=correct,
        correct_count=(state.correct_count if state else 0) + (1 if correct else 0),
        wrong_count=(state.wrong_count if state else 0) + (0 if correct else 1),
    )


def compute_states(events: Iterable[AnswerEvent], config: Config) -> dict[str, CardState]:
    states: dict[str, CardState] = {}
    seen: set[str] = set()
    for e in sorted(events, key=lambda e: (effective_time(e), e.id)):
        if e.id in seen:
            continue
        seen.add(e.id)
        key = card_key(e.profile_id, e.entry_id, e.direction)
        states[key] = apply_answer(states.get(key), e.correct, effective_time(e), config)
    return states


def day_number(ms: int, utc_offset_minutes: int) -> int:
    return (ms + utc_offset_minutes * 60_000) // DAY_MS


def due_day(state: CardState, config: Config) -> int:
    intervals = config.intervals_days
    interval = intervals[state.box - 1] if state.box - 1 < len(intervals) else 0
    return day_number(state.last_at, config.utc_offset_minutes) + interval


def is_due(state: CardState | None, now: int, config: Config) -> bool:
    if state is None:
        return False
    return day_number(now, config.utc_offset_minutes) >= due_day(state, config)


def is_mistake(state: CardState | None) -> bool:
    return state is not None and not state.last_correct
