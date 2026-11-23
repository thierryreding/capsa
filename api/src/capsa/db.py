"""Database schema and engine setup (SQLAlchemy Core).

Kept portable between SQLite and PostgreSQL: IDs are UUID strings, timestamps are
integer milliseconds since the epoch (UTC), no dialect-specific SQL. Schema changes
go through Alembic migrations in capsa/migrations.
"""

from __future__ import annotations

from typing import Any

from sqlalchemy import (
    BigInteger,
    Boolean,
    Column,
    Engine,
    ForeignKey,
    Index,
    Integer,
    MetaData,
    String,
    Table,
    Text,
    create_engine,
    event,
)

metadata = MetaData(
    naming_convention={
        "ix": "ix_%(column_0_label)s",
        "uq": "uq_%(table_name)s_%(column_0_name)s",
        "ck": "ck_%(table_name)s_%(constraint_name)s",
        "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
        "pk": "pk_%(table_name)s",
    }
)

UUID = String(36)

users = Table(
    "users",
    metadata,
    Column("id", UUID, primary_key=True),
    Column("username", String(64), nullable=False),
    # Case-folded username; uniqueness is case-insensitive.
    Column("username_key", String(64), nullable=False, unique=True),
    Column("role", String(16), nullable=False),  # admin | learner
    Column("password_hash", Text, nullable=False),
    # Free text for greetings; null: the username is shown.
    Column("disabled", Boolean, nullable=False, default=False),
    Column("created_at", BigInteger, nullable=False),
    Column("updated_at", BigInteger, nullable=False),
    Column("tenant_id", UUID, nullable=True),  # reserve, SPEC 11
)

sessions = Table(
    "sessions",
    metadata,
    # SHA-256 of the session token; the token itself is only in the cookie.
    Column("token_hash", String(64), primary_key=True),
    Column("user_id", UUID, ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
    Column("created_at", BigInteger, nullable=False),
    Column("last_seen_at", BigInteger, nullable=False),
    Column("expires_at", BigInteger, nullable=False),
    Index("ix_sessions_user_id", "user_id"),
)

profile_grants = Table(
    "profile_grants",
    metadata,
    Column("user_id", UUID, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column("profile_id", String(128), primary_key=True),
    Column("created_at", BigInteger, nullable=False),
)

events = Table(
    "events",
    metadata,
    Column("server_seq", Integer, primary_key=True, autoincrement=True),
    Column("id", UUID, nullable=False, unique=True),  # UUIDv7 from the client
    Column("user_id", UUID, ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
    Column("tenant_id", UUID, nullable=True),  # reserve, SPEC 11
    Column("device_id", String(64), nullable=False),
    Column("profile_id", String(128), nullable=False),
    Column("entry_id", String(128), nullable=False),
    Column("direction", String(16), nullable=False),
    Column("mode", String(16), nullable=False),
    Column("correct", Boolean, nullable=False),
    Column("response_ms", Integer, nullable=True),
    Column("ts", BigInteger, nullable=False),  # client time
    Column("received_at", BigInteger, nullable=False),  # server time
    Index("ix_events_user_seq", "user_id", "server_seq"),
)

user_settings = Table(
    "user_settings",
    metadata,
    Column("user_id", UUID, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column("key", String(64), primary_key=True),
    Column("value", Text, nullable=False),  # JSON
    Column("updated_at", BigInteger, nullable=False),  # client time, last write wins
)


def _sqlite_pragmas(dbapi_conn: Any, _record: Any) -> None:
    cur = dbapi_conn.cursor()
    cur.execute("PRAGMA foreign_keys=ON")
    cur.execute("PRAGMA journal_mode=WAL")
    cur.execute("PRAGMA busy_timeout=5000")
    cur.close()


def make_engine(url: str) -> Engine:
    engine = create_engine(url)
    if engine.dialect.name == "sqlite":
        event.listen(engine, "connect", _sqlite_pragmas)
    return engine
