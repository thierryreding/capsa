"""Per-account settings, last write wins by `updated_at` (SPEC 5, 6).

Examples: the display name, the test date, the selected units. Values are JSON;
keys the server understands (see capsa.user_settings) are validated.
"""

from __future__ import annotations

import json
from typing import Annotated

from fastapi import APIRouter, HTTPException, Path, status
from pydantic import AwareDatetime, BaseModel, Field, JsonValue, field_validator

from capsa import user_settings
from capsa.clock import from_datetime, to_datetime
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


@router.get("/settings")
def list_settings(user: CurrentUser, conn: Conn) -> list[Setting]:
    return [_setting(r) for r in user_settings.list_for(conn, user.id)]


@router.get("/settings/{key}", responses={404: {"description": "Not set"}})
def get_setting(key: Key, user: CurrentUser, conn: Conn) -> Setting:
    row = user_settings.get(conn, user.id, key)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "setting not set")
    return _setting(row)


@router.put("/settings/{key}", responses={400: {"description": "Invalid value for this key"}})
def put_setting(key: Key, body: SettingWrite, user: CurrentUser, conn: Conn) -> Setting:
    """Store the value if it is newer than the stored one; return the winning value."""
    try:
        row = user_settings.write(conn, user.id, key, body.value, from_datetime(body.updated_at))
    except user_settings.SettingError as exc:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(exc)) from None
    return _setting(row)
