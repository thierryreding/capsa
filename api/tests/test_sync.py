from __future__ import annotations

import os
import uuid
from datetime import UTC, datetime, timedelta

import pytest

URL = "/api/v1/sync/events"
T0 = datetime(2027, 1, 15, 16, 0, tzinfo=UTC)


def uuid7(ms: int | None = None) -> str:
    """RFC 9562 UUIDv7 (Python 3.12 has no uuid.uuid7)."""
    ms = int(T0.timestamp() * 1000) if ms is None else ms
    value = (ms & ((1 << 48) - 1)) << 80 | int.from_bytes(os.urandom(10)) & ((1 << 80) - 1)
    value = value & ~(0xF << 76) | (7 << 76)  # version
    value = value & ~(0x3 << 62) | (0x2 << 62)  # variant
    return str(uuid.UUID(int=value))


def event(**overrides):
    e = {
        "id": uuid7(),
        "device_id": "tablet-1",
        "profile_id": "demo-latin",
        "entry_id": "u1-nauta",
        "direction": "src_to_tr",
        "mode": "typed",
        "correct": True,
        "response_ms": 2300,
        "ts": T0.isoformat(),
    }
    return e | overrides


@pytest.fixture
def lena(api):
    api.add_user("lena", profiles=["demo-latin"])
    return api.login("lena")


def test_uuid7_helper():
    assert uuid.UUID(uuid7()).version == 7


def test_sync_needs_login(api):
    assert api.client().post(URL, json={"events": []}).status_code == 401
    assert api.client().get(URL).status_code == 401


def test_upload_and_download(lena, api):
    e1, e2 = event(), event(entry_id="u1-insula", correct=False, response_ms=None)
    r = lena.post(URL, json={"events": [e1, e2]})
    assert r.json() == {"accepted": 2, "duplicates": 0, "rejected": []}

    page = lena.get(URL).json()
    assert page["more"] is False
    assert [e["id"] for e in page["events"]] == [e1["id"], e2["id"]]
    first = page["events"][0]
    assert first["server_seq"] < page["events"][1]["server_seq"] == page["next_since"]
    assert datetime.fromisoformat(first["ts"]) == T0
    assert datetime.fromisoformat(first["received_at"]).timestamp() * 1000 == api.clock()
    assert {k: first[k] for k in e1 if k != "ts"} == {k: v for k, v in e1.items() if k != "ts"}


def test_upload_is_idempotent(lena):
    e = event()
    lena.post(URL, json={"events": [e]})
    r = lena.post(URL, json={"events": [e, e]})
    assert r.json() == {"accepted": 0, "duplicates": 2, "rejected": []}
    assert len(lena.get(URL).json()["events"]) == 1


def test_duplicate_within_one_batch(lena):
    e = event()
    assert lena.post(URL, json={"events": [e, e]}).json()["accepted"] == 1


def test_rejections(lena, api):
    api.add_user("max", profiles=["demo-latin"])
    other = api.login("max")
    taken = event()
    other.post(URL, json={"events": [taken]})

    bad_profile = event(profile_id="not-released")
    bad_entry = event(entry_id="u9-nothing")
    good = event()
    r = lena.post(URL, json={"events": [taken, bad_profile, bad_entry, good]}).json()
    assert r["accepted"] == 1
    assert r["rejected"] == [
        {"id": taken["id"], "reason": "id_conflict"},
        {"id": bad_profile["id"], "reason": "unknown_profile"},
        {"id": bad_entry["id"], "reason": "unknown_entry"},
    ]


def test_events_are_private_per_user(lena, api):
    api.add_user("max", profiles=["demo-latin"])
    lena.post(URL, json={"events": [event()]})
    assert api.login("max").get(URL).json()["events"] == []


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("id", str(uuid.uuid4())),
        ("id", "not-a-uuid"),
        ("direction", "sideways"),
        ("mode", "guessing"),
        ("device_id", "has space"),
        ("response_ms", -1),
        ("ts", "2027-01-15T16:00:00"),  # no timezone
    ],
)
def test_invalid_events_are_refused(lena, field, value):
    r = lena.post(URL, json={"events": [event(**{field: value})]})
    assert r.status_code == 422


def test_batch_size_limit(lena):
    r = lena.post(URL, json={"events": [event() for _ in range(501)]})
    assert r.status_code == 422


def test_paging(lena):
    lena.post(URL, json={"events": [event() for _ in range(5)]})
    p1 = lena.get(URL, params={"limit": 2}).json()
    p2 = lena.get(URL, params={"since": p1["next_since"], "limit": 2}).json()
    p3 = lena.get(URL, params={"since": p2["next_since"], "limit": 2}).json()
    assert (p1["more"], p2["more"], p3["more"]) == (True, True, False)
    assert len(p1["events"]) + len(p2["events"]) + len(p3["events"]) == 5
    empty = lena.get(URL, params={"since": p3["next_since"]}).json()
    assert empty == {"events": [], "next_since": p3["next_since"], "more": False}


def test_two_devices_converge(lena, api):
    """Device A answers offline, syncs; device B fetches what it has not seen (SPEC 6)."""
    device_b = api.login("lena")
    b_seen = device_b.get(URL).json()["next_since"]

    a_events = [
        event(device_id="phone", ts=(T0 + timedelta(minutes=i)).isoformat()) for i in range(3)
    ]
    lena.post(URL, json={"events": a_events})
    b_event = event(device_id="tablet")
    device_b.post(URL, json={"events": [b_event]})

    page = device_b.get(URL, params={"since": b_seen}).json()
    assert {e["id"] for e in page["events"]} == {e["id"] for e in a_events} | {b_event["id"]}
    assert lena.get(URL).json()["events"] == device_b.get(URL).json()["events"]


def test_revoked_profile_blocks_new_events_but_keeps_history(lena, api):
    from capsa import accounts

    lena.post(URL, json={"events": [event()]})
    with api.engine.begin() as conn:
        user = accounts.find_user(conn, "lena")
        accounts.set_grants(conn, user.id, set(), api.clock())
    r = lena.post(URL, json={"events": [event()]}).json()
    assert r["rejected"][0]["reason"] == "unknown_profile"
    assert len(lena.get(URL).json()["events"]) == 1
