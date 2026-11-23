from __future__ import annotations

import io

import pytest

from capsa import accounts
from capsa.accounts import AccountError, normalize_display_name
from capsa.cli import main

ME = "/api/v1/me"
ADMIN = "/api/v1/admin/users"


@pytest.mark.parametrize(
    ("raw", "stored"),
    [
        ("Lena", "Lena"),
        ("  Lena Müller  ", "Lena Müller"),
        ("", None),
        ("   ", None),
        (None, None),
        ("x" * 64, "x" * 64),
        ("Léa 🦉", "Léa 🦉"),
    ],
)
def test_normalize(raw, stored):
    assert normalize_display_name(raw) == stored


@pytest.mark.parametrize(("raw", "message"), [("x" * 65, "at most 64"), ("Le\nna", "control"),
                                              ("a\x00b", "control")])  # fmt: skip
def test_normalize_rejects(raw, message):
    with pytest.raises(AccountError, match=message):
        normalize_display_name(raw)


def test_me_has_no_display_name_by_default(api):
    api.add_user("lena")
    assert api.login("lena").get(ME).json()["display_name"] is None


def test_user_sets_own_display_name(api):
    api.add_user("lena")
    c = api.login("lena")
    r = c.patch(ME, json={"display_name": "  Lena  "})
    assert r.status_code == 200 and r.json()["display_name"] == "Lena"
    assert c.get(ME).json()["display_name"] == "Lena"
    # also returned by the login, so the app has it right away
    login = api.client().post(
        "/api/v1/auth/login", json={"username": "lena", "password": "geheim123"}
    )
    assert login.json()["display_name"] == "Lena"
    assert c.patch(ME, json={"display_name": ""}).json()["display_name"] is None
    assert c.patch(ME, json={"display_name": "Lena"}).status_code == 200
    assert c.patch(ME, json={"display_name": None}).json()["display_name"] is None


def test_invalid_own_display_name(api):
    api.add_user("lena")
    c = api.login("lena")
    r = c.patch(ME, json={"display_name": "x" * 65})
    assert r.status_code == 400 and "at most 64" in r.json()["detail"]
    assert c.patch(ME, json={"display_name": "x" * 300}).status_code == 422
    assert c.patch(ME, json={}).status_code == 422  # the field is required
    assert api.client().patch(ME, json={"display_name": "x"}).status_code == 401


def test_admin_sets_display_names(api):
    api.add_user("papa", role="admin")
    papa = api.login("papa")
    created = papa.post(ADMIN, json={"username": "lena", "password": "geheim123",
                                     "display_name": " Lena "}).json()  # fmt: skip
    assert created["display_name"] == "Lena"
    url = f"{ADMIN}/{created['id']}"
    # absent: unchanged
    assert papa.patch(url, json={"disabled": False}).json()["display_name"] == "Lena"
    assert papa.patch(url, json={"display_name": "Lenchen"}).json()["display_name"] == "Lenchen"
    assert papa.patch(url, json={"display_name": None}).json()["display_name"] is None
    bad = papa.patch(url, json={"display_name": "a\tb"})
    assert bad.status_code == 400 and "control" in bad.json()["detail"]
    assert [u["display_name"] for u in papa.get(ADMIN).json()] == [None, None]
    bad_create = papa.post(ADMIN, json={"username": "max", "password": "geheim123",
                                        "display_name": "x" * 65})  # fmt: skip
    assert bad_create.status_code == 400


def test_cli(tmp_path, monkeypatch, capsys):
    from capsa.migrate import upgrade

    url = f"sqlite:///{tmp_path / 'db.sqlite'}"
    upgrade(url)
    monkeypatch.setattr("sys.stdin", io.StringIO("geheim123\n"))
    assert main(["user", "add", "lena", "--display-name", "Lena", "--password-stdin",
                 "--database-url", url]) == 0  # fmt: skip
    capsys.readouterr()
    assert main(["user", "list", "--database-url", url]) == 0
    assert capsys.readouterr().out.split() == ["lena", "learner", "profiles:", "-", "name:", "Lena"]
    assert main(["user", "set-name", "lena", "Lenchen", "--database-url", url]) == 0
    assert "'Lenchen'" in capsys.readouterr().out
    assert main(["user", "set-name", "lena", "--database-url", url]) == 0
    assert "no display name" in capsys.readouterr().out
    assert main(["user", "set-name", "lena", "x" * 65, "--database-url", url]) == 1
    assert "at most 64" in capsys.readouterr().err
    assert main(["user", "add", "max", "--display-name", "a\nb", "--password-stdin",
                 "--database-url", url]) == 1  # fmt: skip
    assert "control" in capsys.readouterr().err


def test_display_name_survives_set_by_accounts_api(api):
    user = api.add_user("lena")
    with api.engine.begin() as conn:
        accounts.set_display_name(conn, user.id, "Lena", api.clock())
        assert accounts.get_user(conn, user.id).display_name == "Lena"
