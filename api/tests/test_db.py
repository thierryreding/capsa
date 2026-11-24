from __future__ import annotations

from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from sqlalchemy import inspect

from capsa.cli import main
from capsa.db import make_engine, metadata
from capsa.migrate import upgrade


def test_migrations_match_table_definitions(tmp_path):
    url = f"sqlite:///{tmp_path / 'db.sqlite'}"
    upgrade(url)
    engine = make_engine(url)
    with engine.connect() as conn:
        diff = compare_metadata(MigrationContext.configure(conn), metadata)
    assert diff == []
    assert set(inspect(engine).get_table_names()) >= {
        "users", "sessions", "profile_grants", "events", "user_settings"
    }  # fmt: skip


def test_sqlite_pragmas(tmp_path):
    engine = make_engine(f"sqlite:///{tmp_path / 'db.sqlite'}")
    with engine.connect() as conn:
        assert conn.exec_driver_sql("PRAGMA foreign_keys").scalar() == 1
        assert conn.exec_driver_sql("PRAGMA journal_mode").scalar() == "wal"


def test_cli_db_upgrade_is_idempotent(tmp_path, capsys):
    url = f"sqlite:///{tmp_path / 'db.sqlite'}"
    assert main(["db", "upgrade", "--database-url", url]) == 0
    assert main(["db", "upgrade", "--database-url", url]) == 0
    assert "up to date" in capsys.readouterr().out


def test_table_rebuilds_do_not_cascade(tmp_path):
    """SQLite migrations rebuild tables (copy, DROP, rename); with foreign keys enforced
    the DROP of users would delete sessions, grants, settings and events."""
    from alembic import command
    from sqlalchemy import text

    from capsa.migrate import alembic_config

    url = f"sqlite:///{tmp_path / 'db.sqlite'}"
    upgrade(url, "0002")
    engine = make_engine(url)
    with engine.begin() as conn:
        conn.execute(
            text(
                "INSERT INTO users (id, username, username_key, role, password_hash, disabled,"
                " created_at, updated_at) VALUES ('u1', 'lena', 'lena', 'learner', 'x', 0, 1, 1)"
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
    command.downgrade(alembic_config(url), "0001")  # drops a column: rebuilds users
    with engine.begin() as conn:
        tables = ("users", "sessions", "profile_grants", "user_settings", "events")
        counts = [conn.execute(text(f"SELECT count(*) FROM {t}")).scalar() for t in tables]
        assert counts == [1, 1, 1, 1, 1]
    engine.dispose()


def test_cli_db_upgrade_explains_unwritable_folder(tmp_path, capsys):
    folder = tmp_path / "data"
    folder.mkdir()
    folder.chmod(0o555)  # like a bind-mount folder created by root
    try:
        url = f"sqlite:///{folder / 'capsa.sqlite'}"
        assert main(["db", "upgrade", "--database-url", url]) == 1
        assert f"{folder} is not writable" in capsys.readouterr().err
    finally:
        folder.chmod(0o755)


def test_cli_db_upgrade_explains_missing_folder(tmp_path, capsys):
    url = f"sqlite:///{tmp_path / 'missing' / 'capsa.sqlite'}"
    assert main(["db", "upgrade", "--database-url", url]) == 1
    assert "does not exist" in capsys.readouterr().err
