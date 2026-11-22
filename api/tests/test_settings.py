from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

T0 = datetime(2027, 1, 15, 16, 0, tzinfo=UTC)
URL = "/api/v1/settings"


@pytest.fixture
def lena(api):
    api.add_user("lena")
    return api.login("lena")


def put(client, key, value, at):
    return client.put(f"{URL}/{key}", json={"value": value, "updated_at": at.isoformat()})


def test_settings_need_login(api):
    assert api.client().get(URL).status_code == 401


def test_put_get_list(lena):
    r = put(lena, "test-date", "2027-02-01", T0)
    assert r.status_code == 200 and r.json()["value"] == "2027-02-01"
    put(lena, "units", {"demo-latin": ["u1", "u2"]}, T0)
    assert lena.get(f"{URL}/units").json()["value"] == {"demo-latin": ["u1", "u2"]}
    assert [s["key"] for s in lena.get(URL).json()] == ["test-date", "units"]
    assert lena.get(f"{URL}/missing").status_code == 404


def test_last_write_wins_by_client_time(lena):
    put(lena, "test-date", "2027-02-01", T0)
    newer = put(lena, "test-date", "2027-03-01", T0 + timedelta(minutes=5))
    assert newer.json()["value"] == "2027-03-01"
    # A device that was offline sends an older change later: the newer value stays.
    older = put(lena, "test-date", "2027-01-20", T0 + timedelta(minutes=1))
    assert older.json()["value"] == "2027-03-01"
    assert datetime.fromisoformat(older.json()["updated_at"]) == T0 + timedelta(minutes=5)
    # Equal timestamps keep the stored value, so all devices agree.
    tie = put(lena, "test-date", "other", T0 + timedelta(minutes=5))
    assert tie.json()["value"] == "2027-03-01"


def test_settings_are_private(lena, api):
    put(lena, "test-date", "2027-02-01", T0)
    api.add_user("max")
    assert api.login("max").get(URL).json() == []


@pytest.mark.parametrize("key", ["Upper", "with space", "x" * 65])
def test_invalid_keys(lena, key):
    assert put(lena, key, 1, T0).status_code == 422


def test_value_size_limit(lena):
    assert put(lena, "big", "x" * 17_000, T0).status_code == 422


def test_naive_timestamp_refused(lena):
    r = lena.put(f"{URL}/k", json={"value": 1, "updated_at": "2027-01-15T16:00:00"})
    assert r.status_code == 422
