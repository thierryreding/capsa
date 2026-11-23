from __future__ import annotations

import json

from conftest import DEMO_PROFILE, REPO

from capsa.leitner import AnswerEvent, Config
from capsa.profile_io import load_profile
from capsa.progress import learning_stats

VECTORS = json.loads((REPO / "vectors" / "stats.json").read_text(encoding="utf-8"))


def test_shared_vector():
    doc = load_profile(REPO / VECTORS["profile"])
    config = Config(
        intervals_days=VECTORS["config"]["intervalsDays"],
        utc_offset_minutes=VECTORS["config"]["utcOffsetMinutes"],
    )
    events = [AnswerEvent(**e) for e in VECTORS["events"]]
    assert learning_stats(doc, events, VECTORS["now"], config) == VECTORS["expected"]


def test_no_events():
    doc = load_profile(DEMO_PROFILE)
    stats = learning_stats(doc, [], 1_800_000_000_000, Config())
    assert stats["total_answers"] == 0 and stats["last_answer_at"] is None
    assert stats["directions"] == ["src_to_tr"]
    assert [u["fresh"] for u in stats["units"]] == [10, 9]
    assert stats["hardest"] == [] and len(stats["days"]) == 14


def test_both_directions_practised():
    doc = load_profile(DEMO_PROFILE)
    events = [
        AnswerEvent("a", "demo-latin", "u1-nauta", "src_to_tr", True, 1_800_000_000_000),
        AnswerEvent("b", "demo-latin", "u1-nauta", "tr_to_src", True, 1_800_000_000_000),
    ]
    stats = learning_stats(doc, events, 1_800_000_000_000, Config())
    assert stats["directions"] == ["src_to_tr", "tr_to_src"]
    assert stats["units"][0]["cards"] == 20 and stats["units"][0]["fresh"] == 18


def test_deprecated_entries_do_not_count():
    doc = load_profile(DEMO_PROFILE)
    doc["units"][0]["entries"][0]["deprecated"] = True  # u1-nauta
    events = [AnswerEvent("a", "demo-latin", "u1-nauta", "src_to_tr", False, 1)]
    stats = learning_stats(doc, events, 1_800_000_000_000, Config())
    assert stats["units"][0]["cards"] == 9 and stats["total_answers"] == 0


def test_admin_endpoint(api):
    from datetime import UTC, datetime

    api.add_user("papa", role="admin")
    lena = api.add_user("lena", profiles=["demo-latin"])
    kid = api.login("lena")
    ts = datetime.fromtimestamp(api.clock() / 1000, tz=UTC).isoformat()
    for i, (entry, correct) in enumerate([("u1-nauta", False), ("u1-nauta", True)]):
        kid.post("/api/v1/sync/events", json={"events": [{
            "id": f"0189abcd-ef01-7{i:03x}-8000-000000000000", "device_id": "d",
            "profile_id": "demo-latin", "entry_id": entry, "direction": "src_to_tr",
            "mode": "typed", "correct": correct, "ts": ts,
        }]})  # fmt: skip
    papa = api.login("papa")
    url = f"/api/v1/admin/users/{lena.id}/progress/demo-latin"
    stats = papa.get(url, params={"utc_offset": 60}).json()
    assert stats["total_answers"] == 2
    assert stats["units"][0]["boxes"][:2] == [0, 1]
    assert stats["hardest"][0]["entry_id"] == "u1-nauta"
    assert stats["days"][-1]["correct"] == 1 and stats["days"][-1]["wrong"] == 1

    assert papa.get(f"/api/v1/admin/users/{lena.id}/progress/nope").status_code == 404
    assert papa.get("/api/v1/admin/users/nope/progress/demo-latin").status_code == 404
    assert papa.get(url, params={"utc_offset": 9999}).status_code == 422
    assert kid.get(url).status_code == 403
