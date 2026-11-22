from __future__ import annotations

import io

import pytest
from click.testing import CliRunner

from capsa import accounts
from capsa.accounts import AccountError
from capsa.cli import cli, main
from capsa.db import make_engine
from capsa.migrate import upgrade
from capsa.passwords import PasswordPolicyError, Passwords, check_policy

PW = Passwords.cheap()


@pytest.fixture
def db_url(tmp_path):
    url = f"sqlite:///{tmp_path / 'db.sqlite'}"
    upgrade(url)
    return url


@pytest.fixture
def conn(db_url):
    engine = make_engine(db_url)
    with engine.begin() as c:
        yield c
    engine.dispose()


def test_password_policy():
    check_policy("12345678")
    with pytest.raises(PasswordPolicyError, match="at least 8"):
        check_policy("1234567")
    with pytest.raises(PasswordPolicyError, match="at most"):
        check_policy("x" * 1025)


def test_hash_is_argon2id_and_verifies():
    h = Passwords().hash("correct horse")
    assert h.startswith("$argon2id$")
    assert Passwords().verify(h, "correct horse")
    assert not Passwords().verify(h, "wrong horse")
    assert not Passwords().verify("not a hash", "correct horse")


def test_create_and_find_user(conn):
    user = accounts.create_user(conn, PW, "Lena", "geheim123", "learner", now=1000)
    assert accounts.find_user(conn, "lena") == user  # case-insensitive
    assert accounts.get_user(conn, user.id) == user
    assert not user.is_admin


def test_username_unique_case_insensitive(conn):
    accounts.create_user(conn, PW, "Lena", "geheim123", "learner", now=1)
    with pytest.raises(AccountError, match="taken"):
        accounts.create_user(conn, PW, "LENA", "geheim123", "learner", now=2)


@pytest.mark.parametrize("name", ["", "with space", "x" * 65, "a/b"])
def test_invalid_usernames(conn, name):
    with pytest.raises(AccountError, match="username"):
        accounts.create_user(conn, PW, name, "geheim123", "learner", now=1)


def test_unicode_username_and_bad_role(conn):
    accounts.create_user(conn, PW, "Jürgen.K", "geheim123", "admin", now=1)
    with pytest.raises(AccountError, match="role"):
        accounts.create_user(conn, PW, "x", "geheim123", "teacher", now=1)


def test_authenticate(conn):
    user = accounts.create_user(conn, PW, "lena", "geheim123", "learner", now=1)
    assert accounts.authenticate(conn, PW, "Lena", "geheim123", now=2) == user
    assert accounts.authenticate(conn, PW, "lena", "falsch123", now=2) is None
    assert accounts.authenticate(conn, PW, "nobody", "geheim123", now=2) is None
    assert accounts.authenticate(conn, PW, "bad name!", "geheim123", now=2) is None
    accounts.set_disabled(conn, user.id, True, now=3)
    assert accounts.authenticate(conn, PW, "lena", "geheim123", now=4) is None


def test_authenticate_upgrades_weak_hash(conn):
    user = accounts.create_user(conn, PW, "lena", "geheim123", "learner", now=1)
    strong = Passwords()
    assert accounts.authenticate(conn, strong, "lena", "geheim123", now=2) == user
    assert not strong.needs_rehash(accounts.password_hash(conn, user.id))


def test_set_password(conn):
    user = accounts.create_user(conn, PW, "lena", "geheim123", "learner", now=1)
    accounts.set_password(conn, PW, user.id, "neues-passwort", now=2)
    assert accounts.authenticate(conn, PW, "lena", "neues-passwort", now=3) == user
    with pytest.raises(PasswordPolicyError):
        accounts.set_password(conn, PW, user.id, "kurz", now=4)


def test_grants(conn):
    user = accounts.create_user(conn, PW, "lena", "geheim123", "learner", now=1)
    assert accounts.grants(conn, user.id) == set()
    accounts.set_grants(conn, user.id, {"demo-latin", "other"}, now=2)
    assert accounts.grants(conn, user.id) == {"demo-latin", "other"}
    accounts.set_grants(conn, user.id, {"other", "third"}, now=3)
    assert accounts.grants(conn, user.id) == {"other", "third"}


# --- CLI ------------------------------------------------------------------


def run(db_url, *args, stdin=None, monkeypatch=None):
    if stdin is not None:
        monkeypatch.setattr("sys.stdin", io.StringIO(stdin))
    return main(["user", *args, "--database-url", db_url])


def test_cli_user_lifecycle(db_url, monkeypatch, capsys):
    assert run(db_url, "add", "papa", "--admin", "--password-stdin",
               stdin="geheim123\n", monkeypatch=monkeypatch) == 0  # fmt: skip
    assert run(db_url, "add", "lena", "--password-stdin",
               stdin="geheim456\n", monkeypatch=monkeypatch) == 0  # fmt: skip
    assert run(db_url, "grant", "lena", "demo-latin", "other") == 0
    assert run(db_url, "revoke", "lena", "other") == 0
    assert run(db_url, "disable", "lena") == 0
    capsys.readouterr()
    assert run(db_url, "list") == 0
    out = capsys.readouterr().out.splitlines()
    assert out[0].split() == ["lena", "learner", "profiles:", "demo-latin", "(disabled)"]
    assert out[1].split() == ["papa", "admin", "profiles:", "-"]


def test_cli_passwd_and_errors(db_url, monkeypatch, capsys):
    run(db_url, "add", "lena", "--password-stdin", stdin="geheim123\n", monkeypatch=monkeypatch)
    assert run(db_url, "passwd", "lena", "--password-stdin",
               stdin="kurz\n", monkeypatch=monkeypatch) == 1  # fmt: skip
    assert "at least 8" in capsys.readouterr().err
    assert run(db_url, "grant", "nobody", "x") == 1
    assert "no user 'nobody'" in capsys.readouterr().err
    assert run(db_url, "add", "LENA", "--password-stdin",
               stdin="geheim123\n", monkeypatch=monkeypatch) == 1  # fmt: skip
    assert "taken" in capsys.readouterr().err


def test_cli_interactive_password_prompt(db_url):
    """The password is asked twice, hidden; a mismatch asks again."""
    runner = CliRunner()
    result = runner.invoke(
        cli,
        ["user", "add", "lena", "--database-url", db_url],
        input="geheim123\ngeheim124\ngeheim123\ngeheim123\n",
    )
    assert result.exit_code == 0, result.output
    assert "do not match" in result.output
    assert "geheim" not in result.output  # hidden input
    assert "created learner lena" in result.output
