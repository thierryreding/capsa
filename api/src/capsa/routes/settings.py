"""Per-account settings, last write wins by client `updated_at` (SPEC 5, 6).

Examples: the test date, the selected units. Values are arbitrary JSON.
"""

from __future__ import annotations

import json
from typing import Annotated

from fastapi import APIRouter, HTTPException, Path, status
from pydantic import AwareDatetime, BaseModel, Field, JsonValue, field_validator
from sqlalchemy import Connection, insert, select, update

from capsa.clock import from_datetime, to_datetime
from capsa.db import user_settings
from capsa.deps import Conn, CurrentUser

router = APIRouter(tags=["settings"])

MAX_VALUE_BYTES = 16 * 1024
Key = Annotated[str, Path(pattern=r"^[a-z0-9_.-]{1,64}$")]


class SettingWrite(BaseModel):
    value: JsonValue
    updated_at: AwareDatetime = Field(description="client time of the change")

    @field_validator("value")
    @classmethod
    def _size(cls, value: JsonValue) -> JsonValue:
        if len(json.dumps(value).encode()) > MAX_VALUE_BYTES:
            raise ValueError(f"value larger than {MAX_VALUE_BYTES} bytes")
        return value


class Setting(BaseModel):
    key: str
    value: JsonValue
    updated_at: AwareDatetime


def _setting(row) -> Setting:
    return Setting(key=row.key, value=json.loads(row.value), updated_at=to_datetime(row.updated_at))


def _find(conn: Connection, user_id: str, key: str):
    return conn.execute(
        select(user_settings).where(user_settings.c.user_id == user_id, user_settings.c.key == key)
    ).first()


@router.get("/settings")
def list_settings(user: CurrentUser, conn: Conn) -> list[Setting]:
    rows = conn.execute(
        select(user_settings)
        .where(user_settings.c.user_id == user.id)
        .order_by(user_settings.c.key)
    )
    return [_setting(r) for r in rows]


@router.get("/settings/{key}", responses={404: {"description": "Not set"}})
def get_setting(key: Key, user: CurrentUser, conn: Conn) -> Setting:
    row = _find(conn, user.id, key)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "setting not set")
    return _setting(row)


@router.put("/settings/{key}")
def put_setting(key: Key, body: SettingWrite, user: CurrentUser, conn: Conn) -> Setting:
    """Store the value if it is newer than the stored one; return the winning value."""
    updated_at = from_datetime(body.updated_at)
    value = json.dumps(body.value, ensure_ascii=False)
    row = _find(conn, user.id, key)
    if row is None:
        conn.execute(
            insert(user_settings).values(
                user_id=user.id, key=key, value=value, updated_at=updated_at
            )
        )
    elif updated_at > row.updated_at:
        conn.execute(
            update(user_settings)
            .where(user_settings.c.user_id == user.id, user_settings.c.key == key)
            .values(value=value, updated_at=updated_at)
        )
    return _setting(_find(conn, user.id, key))
