"""Learning statistics for one learner and profile (F9). Pure functions.

Mirrors web/src/lib/learning/stats.ts; both must pass vectors/stats.json, so the
child's statistics on the device and the parent's view from the server agree.

- Directions: those the learner has practised in this profile (only src_to_tr if none),
  so a learner who never practises one direction does not see half the cards as new.
- A card is "secure" from box 3 on (two right answers in a row), as for test planning.
- Days are local calendar days (utc_offset_minutes); "recent" means the last 30 days
  including today, the history covers the last 14 days.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from capsa.leitner import (
    AnswerEvent,
    Config,
    card_key,
    compute_states,
    day_number,
    effective_time,
    is_mistake,
)

SECURE_BOX = 3
HISTORY_DAYS = 14
RECENT_DAYS = 30
HARDEST = 10
DAY_MS = 24 * 60 * 60 * 1000


def iso_day(day: int) -> str:
    return datetime.fromtimestamp(day * DAY_MS / 1000, tz=UTC).strftime("%Y-%m-%d")


def learning_stats(
    doc: dict[str, Any], events: list[AnswerEvent], now: int, config: Config
) -> dict[str, Any]:
    profile = doc["profile"]
    lang = profile["required_translation_lang"]
    active = [
        (unit, entry)
        for unit in doc["units"]
        for entry in unit["entries"]
        if not entry.get("deprecated")
    ]
    order = {entry["id"]: i for i, (_, entry) in enumerate(active)}
    unit_of = {entry["id"]: unit["id"] for unit, entry in active}

    unique: dict[str, AnswerEvent] = {}
    for e in events:
        if e.profile_id == profile["id"] and e.entry_id in order:
            unique.setdefault(e.id, e)
    mine = sorted(unique.values(), key=lambda e: (effective_time(e), e.id))

    directions = sorted({e.direction for e in mine}) or ["src_to_tr"]
    states = compute_states(mine, config)
    today = day_number(now, config.utc_offset_minutes)

    def day_of(e: AnswerEvent) -> int:
        return day_number(effective_time(e), config.utc_offset_minutes)

    boxes_n = len(config.intervals_days)
    units = []
    for unit in doc["units"]:
        entries = [e for e in unit["entries"] if not e.get("deprecated")]
        row = {
            "unit_id": unit["id"],
            "number": unit["number"],
            "title": unit["title"],
            "cards": len(entries) * len(directions),
            "fresh": 0,
            "secure": 0,
            "mistakes": 0,
            "boxes": [0] * boxes_n,
            "answers_recent": 0,
            "correct_recent": 0,
        }
        for entry in entries:
            for direction in directions:
                state = states.get(card_key(profile["id"], entry["id"], direction))
                if state is None:
                    row["fresh"] += 1
                    continue
                row["boxes"][state.box - 1] += 1
                row["secure"] += state.box >= SECURE_BOX
                row["mistakes"] += is_mistake(state)
        units.append(row)
    by_unit = {u["unit_id"]: u for u in units}
    for e in mine:
        if today - day_of(e) < RECENT_DAYS:
            u = by_unit[unit_of[e.entry_id]]
            u["answers_recent"] += 1
            u["correct_recent"] += e.correct

    days = [
        {"date": iso_day(d), "correct": 0, "wrong": 0}
        for d in range(today - HISTORY_DAYS + 1, today + 1)
    ]
    for e in mine:
        i = day_of(e) - (today - HISTORY_DAYS + 1)
        if 0 <= i < HISTORY_DAYS:
            days[i]["correct" if e.correct else "wrong"] += 1

    per_entry: dict[str, dict[str, Any]] = {}
    for e in mine:  # chronological, so the last one wins for last_correct
        s = per_entry.setdefault(e.entry_id, {"wrong": 0, "correct": 0})
        s["correct" if e.correct else "wrong"] += 1
        s["last_correct"] = e.correct

    def harder(item: tuple[str, dict[str, Any]]) -> tuple:
        entry_id, s = item
        total = s["wrong"] + s["correct"]
        return (-s["wrong"], RatioKey(s["wrong"], total), order[entry_id])

    entries_by_id = {entry["id"]: entry for _, entry in active}
    hardest = []
    for entry_id, s in sorted(((k, v) for k, v in per_entry.items() if v["wrong"] > 0), key=harder)[
        :HARDEST
    ]:
        entry = entries_by_id[entry_id]
        hardest.append(
            {
                "entry_id": entry_id,
                "lemma": entry["lemma"],
                "meaning": (entry["tr"].get(lang) or [""])[0],
                "wrong": s["wrong"],
                "correct": s["correct"],
                "last_correct": s["last_correct"],
            }
        )

    return {
        "profile_id": profile["id"],
        "directions": directions,
        "total_answers": len(mine),
        "last_answer_at": effective_time(mine[-1]) if mine else None,
        "days": days,
        "units": units,
        "hardest": hardest,
    }


class RatioKey:
    """Sort key: higher error rate first, compared exactly (wrong_a * total_b ...)."""

    def __init__(self, wrong: int, total: int):
        self.wrong, self.total = wrong, total

    def __lt__(self, other: RatioKey) -> bool:
        return self.wrong * other.total > other.wrong * self.total

    def __eq__(self, other: object) -> bool:
        return isinstance(other, RatioKey) and self.wrong * other.total == other.wrong * self.total
