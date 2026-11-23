"""Accounts and profile grants: storage operations on a database connection."""

from __future__ import annotations

import re
import unicodedata
import uuid
from dataclasses import dataclass
from typing import Literal

from sqlalchemy import Connection, delete, insert, select, update
from sqlalchemy.exc import IntegrityError

from capsa.db import profile_grants, users
from capsa.passwords import Passwords

Role = Literal["admin", "learner"]
ROLES: tuple[Role, ...] = ("admin", "learner")

_USERNAME = re.compile(r"^[\w.-]{1,64}$")


class AccountError(ValueError):
    pass


@dataclass(frozen=True)
class User:
    id: str
    username: str
    role: Role
    disabled: bool
    created_at: int
    display_name: str | None = None

    @property
    def is_admin(self) -> bool:
        return self.role == "admin"


def _user(row) -> User:
    return User(row.id, row.username, row.role, row.disabled, row.created_at, row.display_name)


DISPLAY_NAME_MAX = 64


def normalize_display_name(name: str | None) -> str | None:
    """A display name is free text shown in greetings: trimmed, 1-64 characters, no
    control characters. Empty or None clears it (the username is shown instead)."""
    if name is None:
        return None
    name = name.strip()
    if not name:
        return None
    if len(name) > DISPLAY_NAME_MAX:
        raise AccountError(f"display name: at most {DISPLAY_NAME_MAX} characters")
    if any(unicodedata.category(c) == "Cc" for c in name):
        raise AccountError("display name: no control characters")
    return name


def username_key(username: str) -> str:
    return username.casefold()


def check_username(username: str) -> None:
    if not _USERNAME.match(username):
        raise AccountError("username: 1-64 letters, digits, '.', '_' or '-'")


def create_user(
    conn: Connection,
    passwords: Passwords,
    username: str,
    password: str,
    role: Role,
    now: int,
    display_name: str | None = None,
) -> User:
    check_username(username)
    display_name = normalize_display_name(display_name)
    if role not in ROLES:
        raise AccountError(f"unknown role {role!r}")
    password_hash = passwords.hash(password)
    user_id = str(uuid.uuid4())
    try:
        with conn.begin_nested():
            conn.execute(
                insert(users).values(
                    id=user_id,
                    username=username,
                    username_key=username_key(username),
                    role=role,
                    password_hash=password_hash,
                    display_name=display_name,
                    disabled=False,
                    created_at=now,
                    updated_at=now,
                )
            )
    except IntegrityError:
        raise AccountError(f"username {username!r} is taken") from None
    return User(user_id, username, role, False, now, display_name)


def set_display_name(conn: Connection, user_id: str, name: str | None, now: int) -> str | None:
    """Set (or clear, with None/empty) the display name; returns the stored value."""
    name = normalize_display_name(name)
    conn.execute(
        update(users).where(users.c.id == user_id).values(display_name=name, updated_at=now)
    )
    return name


def get_user(conn: Connection, user_id: str) -> User | None:
    row = conn.execute(select(users).where(users.c.id == user_id)).first()
    return _user(row) if row else None


def find_user(conn: Connection, username: str) -> User | None:
    row = conn.execute(select(users).where(users.c.username_key == username_key(username))).first()
    return _user(row) if row else None


def require_user(conn: Connection, username: str) -> User:
    user = find_user(conn, username)
    if user is None:
        raise AccountError(f"no user {username!r}")
    return user


def list_users(conn: Connection) -> list[User]:
    rows = conn.execute(select(users).order_by(users.c.username_key))
    return [_user(r) for r in rows]


def password_hash(conn: Connection, user_id: str) -> str | None:
    return conn.execute(select(users.c.password_hash).where(users.c.id == user_id)).scalar()


def set_password(
    conn: Connection, passwords: Passwords, user_id: str, password: str, now: int
) -> None:
    _set_hash(conn, user_id, passwords.hash(password), now)


def _set_hash(conn: Connection, user_id: str, password_hash: str, now: int) -> None:
    conn.execute(
        update(users)
        .where(users.c.id == user_id)
        .values(password_hash=password_hash, updated_at=now)
    )


def authenticate(
    conn: Connection, passwords: Passwords, username: str, password: str, now: int
) -> User | None:
    """Return the user if the credentials are valid and the account is enabled.

    Takes about the same time whether or not the user exists. Upgrades the stored
    hash when the hashing parameters have changed.
    """
    user = find_user(conn, username) if _USERNAME.match(username) else None
    if user is None:
        passwords.burn(password)
        return None
    stored = password_hash(conn, user.id) or ""
    if not passwords.verify(stored, password) or user.disabled:
        return None
    if passwords.needs_rehash(stored):
        _set_hash(conn, user.id, passwords.hasher.hash(password), now)
    return user


def set_disabled(conn: Connection, user_id: str, disabled: bool, now: int) -> None:
    conn.execute(
        update(users).where(users.c.id == user_id).values(disabled=disabled, updated_at=now)
    )


def grants(conn: Connection, user_id: str) -> set[str]:
    rows = conn.execute(
        select(profile_grants.c.profile_id).where(profile_grants.c.user_id == user_id)
    )
    return set(rows.scalars())


def set_grants(conn: Connection, user_id: str, profile_ids: set[str], now: int) -> None:
    current = grants(conn, user_id)
    if remove := current - profile_ids:
        conn.execute(
            delete(profile_grants).where(
                profile_grants.c.user_id == user_id, profile_grants.c.profile_id.in_(remove)
            )
        )
    for pid in sorted(profile_ids - current):
        conn.execute(insert(profile_grants).values(user_id=user_id, profile_id=pid, created_at=now))
