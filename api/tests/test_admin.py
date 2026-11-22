from __future__ import annotations

import pytest
from conftest import PASSWORD

URL = "/api/v1/admin/users"


@pytest.fixture
def papa(api):
    api.add_user("papa", role="admin")
    return api.login("papa")


def test_admin_only(api):
    api.add_user("lena")
    learner = api.login("lena")
    assert learner.get(URL).status_code == 403
    assert learner.post(URL, json={"username": "x", "password": PASSWORD}).status_code == 403
    assert api.client().get(URL).status_code == 401


def test_create_and_list(papa, api):
    r = papa.post(URL, json={"username": "Lena", "password": PASSWORD, "profiles": ["demo-latin"]})
    assert r.status_code == 201
    created = r.json()
    assert created | {"id": "-"} == {
        "id": "-", "username": "Lena", "role": "learner", "disabled": False,
        "profiles": ["demo-latin"],
    }  # fmt: skip
    assert [u["username"] for u in papa.get(URL).json()] == ["Lena", "papa"]
    lena = api.login("lena")
    assert [p["id"] for p in lena.get("/api/v1/profiles").json()] == ["demo-latin"]


@pytest.mark.parametrize(
    ("body", "detail"),
    [
        ({"username": "lena", "password": "kurz"}, "at least 8"),
        ({"username": "has space", "password": PASSWORD}, "username"),
        ({"username": "papa", "password": PASSWORD}, "taken"),
        ({"username": "lena", "password": PASSWORD, "profiles": ["nope"]}, "unknown profiles"),
    ],
)
def test_create_errors(papa, body, detail):
    r = papa.post(URL, json=body)
    assert r.status_code == 400 and detail in r.json()["detail"]


def test_update_profiles(papa, api):
    lena = api.add_user("lena")
    r = papa.patch(f"{URL}/{lena.id}", json={"profiles": ["demo-latin"]})
    assert r.json()["profiles"] == ["demo-latin"]
    r = papa.patch(f"{URL}/{lena.id}", json={"profiles": []})
    assert r.json()["profiles"] == []
    assert papa.patch(f"{URL}/{lena.id}", json={"profiles": ["nope"]}).status_code == 400


def test_reset_password_signs_out(papa, api):
    lena = api.add_user("lena")
    session = api.login("lena")
    r = papa.patch(f"{URL}/{lena.id}", json={"password": "neues-passwort"})
    assert r.status_code == 200
    assert session.get("/api/v1/me").status_code == 401
    api.login("lena", "neues-passwort")
    assert papa.patch(f"{URL}/{lena.id}", json={"password": "kurz"}).status_code == 400


def test_disable_and_enable(papa, api):
    lena = api.add_user("lena")
    session = api.login("lena")
    assert papa.patch(f"{URL}/{lena.id}", json={"disabled": True}).json()["disabled"] is True
    assert session.get("/api/v1/me").status_code == 401
    papa.patch(f"{URL}/{lena.id}", json={"disabled": False})
    api.login("lena")


def test_cannot_disable_self(papa):
    me = papa.get("/api/v1/me").json()
    r = papa.patch(f"{URL}/{me['id']}", json={"disabled": True})
    assert r.status_code == 400 and "own account" in r.json()["detail"]


def test_unknown_user(papa):
    assert papa.patch(f"{URL}/nope", json={"disabled": True}).status_code == 404
