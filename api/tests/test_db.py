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
