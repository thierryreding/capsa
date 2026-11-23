"""Accounts and profile grants: storage operations on a database connection."""

from __future__ import annotations

import json
import re
import uuid
from dataclasses import dataclass
from typing import Literal

from sqlalchemy import Connection, Select, and_, delete, insert, select, update
from sqlalchemy.exc import IntegrityError

from capsa import user_settings as settings
from capsa.db import profile_grants, user_settings, users
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


def _users() -> Select:
    """Users with their display name, which is a synced setting (see user_settings)."""
    name = user_settings.c.value.label("display_name_json")
    return select(users, name).select_from(
        users.outerjoin(
            user_settings,
            and_(
                user_settings.c.user_id == users.c.id,
                user_settings.c.key == settings.DISPLAY_NAME,
            ),
        )
    )


def _user(row) -> User:
    name = json.loads(row.display_name_json) if row.display_name_json else None
    return User(row.id, row.username, row.role, row.disabled, row.created_at, name)


def normalize_display_name(name: str | None) -> str | None:
    """See user_settings.normalize_display_name; raises AccountError."""
    try:
        return settings.normalize_display_name(name)
    except settings.SettingError as exc:
        raise AccountError(str(exc)) from None


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
                    disabled=False,
                    created_at=now,
                    updated_at=now,
                )
            )
    except IntegrityError:
        raise AccountError(f"username {username!r} is taken") from None
    if display_name is not None:
        settings.write(conn, user_id, settings.DISPLAY_NAME, display_name, now)
    return User(user_id, username, role, False, now, display_name)


def set_display_name(conn: Connection, user_id: str, name: str | None, now: int) -> str | None:
    """Set (or clear, with None/empty) the display name on behalf of an admin; returns it.

    An admin's change always wins over the stored value: it is written at the server
    time, or just after the stored change if a device clock was ahead. Later changes
    from devices win again, as for every setting.
    """
    name = normalize_display_name(name)
    current = settings.get(conn, user_id, settings.DISPLAY_NAME)
    at = max(now, current.updated_at + 1) if current else now
    winner = settings.write(conn, user_id, settings.DISPLAY_NAME, name, at)
    return json.loads(winner.value)


def get_user(conn: Connection, user_id: str) -> User | None:
    row = conn.execute(_users().where(users.c.id == user_id)).first()
    return _user(row) if row else None


def find_user(conn: Connection, username: str) -> User | None:
    row = conn.execute(_users().where(users.c.username_key == username_key(username))).first()
    return _user(row) if row else None


def require_user(conn: Connection, username: str) -> User:
    user = find_user(conn, username)
    if user is None:
        raise AccountError(f"no user {username!r}")
    return user


def list_users(conn: Connection) -> list[User]:
    rows = conn.execute(_users().order_by(users.c.username_key))
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
