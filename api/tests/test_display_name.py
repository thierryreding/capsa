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


SETTING = "/api/v1/settings/display_name"


def put_name(client, value, at: str):
    return client.put(SETTING, json={"value": value, "updated_at": at})


def test_user_sets_own_display_name_as_setting(api):
    api.add_user("lena")
    c = api.login("lena")
    r = put_name(c, "  Lena  ", "2027-01-15T16:00:00Z")
    assert r.status_code == 200 and r.json()["value"] == "Lena"  # stored normalized
    assert c.get(ME).json()["display_name"] == "Lena"
    # also returned by the login, so the app has it right away
    login = api.client().post(
        "/api/v1/auth/login", json={"username": "lena", "password": "geheim123"}
    )
    assert login.json()["display_name"] == "Lena"
    assert put_name(c, "", "2027-01-15T16:01:00Z").json()["value"] is None
    assert c.get(ME).json()["display_name"] is None


def test_invalid_own_display_name(api):
    api.add_user("lena")
    c = api.login("lena")
    r = put_name(c, "x" * 65, "2027-01-15T16:00:00Z")
    assert r.status_code == 400 and "at most 64" in r.json()["detail"]
    assert put_name(c, 42, "2027-01-15T16:00:00Z").status_code == 400
    assert put_name(c, "Le\nna", "2027-01-15T16:00:00Z").status_code == 400
    # other keys stay free-form
    assert c.put("/api/v1/settings/other", json={"value": 42,
                 "updated_at": "2027-01-15T16:00:00Z"}).status_code == 200  # fmt: skip


def test_newest_change_wins_between_device_and_admin(api):
    api.add_user("papa", role="admin")
    lena = api.add_user("lena")
    device = api.login("lena")
    papa = api.login("papa")
    url = f"{ADMIN}/{lena.id}"

    # The admin renames now (server time); an older change from an offline device loses.
    papa.patch(url, json={"display_name": "Lena (Papa)"})
    stale = put_name(device, "Lena (alt)", "2020-01-01T00:00:00Z")
    assert stale.json()["value"] == "Lena (Papa)"
    # A newer change from the device wins over the admin's.
    future = put_name(device, "Lena (neu)", "2099-01-01T00:00:00Z")
    assert future.json()["value"] == "Lena (neu)"
    assert papa.get(ADMIN).json()[0]["display_name"] == "Lena (neu)"


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


def test_migration_moves_existing_names_into_settings(tmp_path):
    import json

    from sqlalchemy import text

    from capsa.db import make_engine
    from capsa.migrate import upgrade

    url = f"sqlite:///{tmp_path / 'db.sqlite'}"
    upgrade(url, "0002")
    engine = make_engine(url)
    with engine.begin() as conn:
        conn.execute(text(
            "INSERT INTO users (id, username, username_key, role, password_hash, disabled,"
            " created_at, updated_at, display_name) VALUES"
            " ('u1', 'lena', 'lena', 'learner', 'x', 0, 1, 5, 'Lena'),"
            " ('u2', 'max', 'max', 'learner', 'x', 0, 1, 1, NULL)"
        ))  # fmt: skip
    upgrade(url)
    with engine.begin() as conn:
        rows = conn.execute(text("SELECT user_id, key, value, updated_at FROM user_settings")).all()
        assert [tuple(r) for r in rows] == [("u1", "display_name", json.dumps("Lena"), 5)]
        assert accounts.get_user(conn, "u1").display_name == "Lena"
        assert accounts.get_user(conn, "u2").display_name is None
    engine.dispose()


def test_migration_downgrade_restores_the_column(tmp_path):
    from alembic import command
    from sqlalchemy import text

    from capsa.db import make_engine
    from capsa.migrate import alembic_config, upgrade
    from capsa.passwords import Passwords

    url = f"sqlite:///{tmp_path / 'db.sqlite'}"
    upgrade(url)
    engine = make_engine(url)
    with engine.begin() as conn:
        user = accounts.create_user(conn, Passwords.cheap(), "lena", "geheim123", "learner", 1)
        accounts.set_display_name(conn, user.id, "Lena", 2)
    command.downgrade(alembic_config(url), "0002")
    with engine.begin() as conn:
        assert conn.execute(text("SELECT display_name FROM users")).scalar() == "Lena"
        assert conn.execute(text("SELECT count(*) FROM user_settings")).scalar() == 0
    engine.dispose()


def test_admin_change_wins_over_a_device_clock_that_runs_ahead(api):
    api.add_user("papa", role="admin")
    lena = api.add_user("lena")
    put_name(api.login("lena"), "Lena (Zukunft)", "2099-01-01T00:00:00Z")
    r = api.login("papa").patch(f"{ADMIN}/{lena.id}", json={"display_name": "Lena"})
    assert r.json()["display_name"] == "Lena"


def test_migration_keeps_all_data_that_references_users(tmp_path):
    """Regression: rebuilding the users table must not cascade into other tables."""
    from sqlalchemy import text

    from capsa.db import make_engine
    from capsa.migrate import upgrade

    url = f"sqlite:///{tmp_path / 'db.sqlite'}"
    upgrade(url, "0002")
    engine = make_engine(url)
    with engine.begin() as conn:
        conn.execute(
            text(
                "INSERT INTO users (id, username, username_key, role, password_hash, disabled,"
                " created_at, updated_at, display_name) VALUES"
                " ('u1', 'lena', 'lena', 'learner', 'x', 0, 1, 5, 'Lena')"
            )
        )
        conn.execute(text("INSERT INTO sessions VALUES ('t', 'u1', 1, 1, 9)"))
        conn.execute(text("INSERT INTO profile_grants VALUES ('u1', 'demo-latin', 1)"))
        conn.execute(text("INSERT INTO user_settings VALUES ('u1', 'units', '[1]', 1)"))
        conn.execute(text(
            "INSERT INTO events (id, user_id, device_id, profile_id, entry_id, direction,"
            " mode, correct, ts, received_at) VALUES"
            " ('e1', 'u1', 'd', 'demo-latin', 'u1-nauta', 'src_to_tr', 'typed', 1, 1, 1)"
        ))  # fmt: skip
    upgrade(url)
    with engine.begin() as conn:
        count = lambda table: conn.execute(text(f"SELECT count(*) FROM {table}")).scalar()  # noqa: E731
        assert [count(t) for t in ("users", "sessions", "profile_grants", "events")] == [1, 1, 1, 1]
        assert count("user_settings") == 2  # units + the moved display name
        assert conn.exec_driver_sql("PRAGMA foreign_keys").scalar() == 1  # on again
    engine.dispose()
