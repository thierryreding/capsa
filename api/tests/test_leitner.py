"""The Python port must agree with the client on the shared vectors."""

from __future__ import annotations

import json
from dataclasses import asdict

import pytest
from conftest import REPO

from capsa.leitner import AnswerEvent, Config, compute_states, is_due

VECTORS = json.loads((REPO / "vectors" / "leitner.json").read_text(encoding="utf-8"))
CONFIG = Config(
    intervals_days=VECTORS["config"]["intervalsDays"],
    utc_offset_minutes=VECTORS["config"]["utcOffsetMinutes"],
)


def camel(state) -> dict:
    d = asdict(state)
    return {
        "box": d["box"],
        "lastAt": d["last_at"],
        "lastCorrect": d["last_correct"],
        "correctCount": d["correct_count"],
        "wrongCount": d["wrong_count"],
    }


@pytest.mark.parametrize("scenario", VECTORS["scenarios"], ids=lambda s: s["name"])
def test_shared_vectors(scenario):
    events = [AnswerEvent(**e) for e in scenario["events"]]
    states = compute_states(events, CONFIG)
    assert {k: camel(v) for k, v in states.items()} == scenario["states"]
    for check in scenario["checks"]:
        due = sorted(k for k, s in states.items() if is_due(s, check["now"], CONFIG))
        assert due == check["due"], check.get("why")
