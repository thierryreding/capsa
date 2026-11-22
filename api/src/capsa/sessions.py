"""Server-side login sessions (SPEC 8): random token in an httpOnly cookie, SHA-256 in the DB."""

from __future__ import annotations

import hashlib
import secrets

from sqlalchemy import Connection, delete, insert, select, update

from capsa.accounts import User, get_user
from capsa.db import sessions

DAY_MS = 24 * 60 * 60 * 1000
# Sliding expiry is renewed at most this often, so not every request writes.
RENEW_AFTER_MS = 60 * 60 * 1000


def _digest(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def create(conn: Connection, user_id: str, now: int, days: int) -> str:
    token = secrets.token_urlsafe(32)
    conn.execute(
        insert(sessions).values(
            token_hash=_digest(token),
            user_id=user_id,
            created_at=now,
            last_seen_at=now,
            expires_at=now + days * DAY_MS,
        )
    )
    return token


def lookup(conn: Connection, token: str, now: int, days: int) -> tuple[User, bool] | None:
    """Return (user, renewed) for a valid session, renewing its sliding expiry if due."""
    digest = _digest(token)
    row = conn.execute(select(sessions).where(sessions.c.token_hash == digest)).first()
    if row is None:
        return None
    if row.expires_at <= now:
        conn.execute(delete(sessions).where(sessions.c.token_hash == digest))
        return None
    user = get_user(conn, row.user_id)
    if user is None or user.disabled:
        return None
    renewed = now - row.last_seen_at >= RENEW_AFTER_MS
    if renewed:
        conn.execute(
            update(sessions)
            .where(sessions.c.token_hash == digest)
            .values(last_seen_at=now, expires_at=now + days * DAY_MS)
        )
    return user, renewed


def revoke(conn: Connection, token: str) -> None:
    conn.execute(delete(sessions).where(sessions.c.token_hash == _digest(token)))


def revoke_others(conn: Connection, user_id: str, keep_token: str | None) -> None:
    stmt = delete(sessions).where(sessions.c.user_id == user_id)
    if keep_token is not None:
        stmt = stmt.where(sessions.c.token_hash != _digest(keep_token))
    conn.execute(stmt)


def purge_expired(conn: Connection, now: int) -> int:
    return conn.execute(delete(sessions).where(sessions.c.expires_at <= now)).rowcount
