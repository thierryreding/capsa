"""Per-account settings, last write wins by `updated_at` (SPEC 6).

Settings are free-form JSON, except for a few keys the server understands and
validates. They are written by the account's devices (with their own clock) and by
admins (with the server's clock); the newest write wins, ties keep the stored value.
"""

from __future__ import annotations

import json
import unicodedata
from typing import Any

from sqlalchemy import Connection, insert, select, update

from capsa.db import user_settings

DISPLAY_NAME = "display_name"
DISPLAY_NAME_MAX = 64


class SettingError(ValueError):
    pass


def normalize_display_name(name: Any) -> str | None:
    """Free text shown in greetings: trimmed, 1-64 characters, no control characters.
    Empty or None clears it (the username is shown instead)."""
    if name is None:
        return None
    if not isinstance(name, str):
        raise SettingError("display name: must be text")
    name = name.strip()
    if not name:
        return None
    if len(name) > DISPLAY_NAME_MAX:
        raise SettingError(f"display name: at most {DISPLAY_NAME_MAX} characters")
    if any(unicodedata.category(c) == "Cc" for c in name):
        raise SettingError("display name: no control characters")
    return name


# Keys with a meaning on the server: value -> normalized value, or SettingError.
VALIDATORS = {DISPLAY_NAME: normalize_display_name}


def validate(key: str, value: Any) -> Any:
    check = VALIDATORS.get(key)
    return check(value) if check else value


def get(conn: Connection, user_id: str, key: str):
    """The stored row (key, value as JSON text, updated_at), or None."""
    return conn.execute(
        select(user_settings).where(user_settings.c.user_id == user_id, user_settings.c.key == key)
    ).first()


def list_for(conn: Connection, user_id: str):
    return conn.execute(
        select(user_settings)
        .where(user_settings.c.user_id == user_id)
        .order_by(user_settings.c.key)
    ).all()


def write(conn: Connection, user_id: str, key: str, value: Any, updated_at: int):
    """Validate and store `value` if it is newer than the stored one; return the winner."""
    value = validate(key, value)
    text = json.dumps(value, ensure_ascii=False)
    row = get(conn, user_id, key)
    if row is None:
        conn.execute(
            insert(user_settings).values(
                user_id=user_id, key=key, value=text, updated_at=updated_at
            )
        )
    elif updated_at > row.updated_at:
        conn.execute(
            update(user_settings)
            .where(user_settings.c.user_id == user_id, user_settings.c.key == key)
            .values(value=text, updated_at=updated_at)
        )
    return get(conn, user_id, key)


def display_name(conn: Connection, user_id: str) -> str | None:
    row = get(conn, user_id, DISPLAY_NAME)
    return json.loads(row.value) if row else None
