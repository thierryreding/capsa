"""Account management for admins (parents) (SPEC 5: /admin/users)."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import Connection

from capsa import accounts, sessions
from capsa.accounts import AccountError, Role, User
from capsa.deps import Admin, Conn, State
from capsa.passwords import MAX_LENGTH, PasswordPolicyError

router = APIRouter(prefix="/admin", tags=["admin"])


class UserInfo(BaseModel):
    id: str
    username: str
    role: Role
    disabled: bool
    display_name: str | None = None
    profiles: list[str] = Field(description="profiles released to the account")


class UserCreate(BaseModel):
    username: str = Field(max_length=64)
    password: str = Field(max_length=MAX_LENGTH)
    role: Role = "learner"
    display_name: str | None = Field(default=None, max_length=256)
    profiles: list[str] = []


class UserUpdate(BaseModel):
    disabled: bool | None = None
    password: str | None = Field(default=None, max_length=MAX_LENGTH, description="reset")
    profiles: list[str] | None = None
    display_name: str | None = Field(
        default=None, max_length=256, description="absent: unchanged; null or empty: cleared"
    )


def _info(conn: Connection, user: User) -> UserInfo:
    return UserInfo(
        id=user.id,
        username=user.username,
        role=user.role,
        disabled=user.disabled,
        display_name=user.display_name,
        profiles=sorted(accounts.grants(conn, user.id)),
    )


def _check_profiles(state: State, profile_ids: list[str]) -> set[str]:
    unknown = sorted(set(profile_ids) - {p.id for p in state.profiles.all()})
    if unknown:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, f"unknown profiles: {', '.join(unknown)}")
    return set(profile_ids)


@router.get("/users")
def list_users(admin: Admin, conn: Conn) -> list[UserInfo]:
    return [_info(conn, u) for u in accounts.list_users(conn)]


@router.post(
    "/users",
    status_code=status.HTTP_201_CREATED,
    responses={400: {"description": "Invalid username/password/profiles"}},
)
def create_user(body: UserCreate, admin: Admin, conn: Conn, state: State) -> UserInfo:
    profiles = _check_profiles(state, body.profiles)
    now = state.clock()
    try:
        user = accounts.create_user(
            conn,
            state.passwords,
            body.username,
            body.password,
            body.role,
            now,
            display_name=body.display_name,
        )
    except (AccountError, PasswordPolicyError) as exc:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(exc)) from None
    accounts.set_grants(conn, user.id, profiles, now)
    return _info(conn, user)


@router.patch(
    "/users/{user_id}",
    responses={400: {"description": "Invalid change"}, 404: {"description": "No such user"}},
)
def update_user(user_id: str, body: UserUpdate, admin: Admin, conn: Conn, state: State) -> UserInfo:
    user = accounts.get_user(conn, user_id)
    if user is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "no such user")
    now = state.clock()
    if "display_name" in body.model_fields_set:
        try:
            accounts.set_display_name(conn, user.id, body.display_name, now)
        except AccountError as exc:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, str(exc)) from None
    if body.profiles is not None:
        accounts.set_grants(conn, user.id, _check_profiles(state, body.profiles), now)
    if body.password is not None:
        try:
            accounts.set_password(conn, state.passwords, user.id, body.password, now)
        except PasswordPolicyError as exc:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, str(exc)) from None
        sessions.revoke_others(conn, user.id, keep_token=None)
    if body.disabled is not None:
        if body.disabled and user.id == admin.id:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "cannot disable your own account")
        accounts.set_disabled(conn, user.id, body.disabled, now)
        if body.disabled:
            sessions.revoke_others(conn, user.id, keep_token=None)
    return _info(conn, accounts.get_user(conn, user.id))
