"""Sign in and out, own account (SPEC 5: /auth/login, /auth/logout, /me)."""

from __future__ import annotations

import math

from fastapi import APIRouter, HTTPException, Request, Response, status
from pydantic import BaseModel, Field

from capsa import accounts, sessions
from capsa.accounts import AccountError, Role, User
from capsa.deps import (
    SESSION_COOKIE,
    Conn,
    CurrentUser,
    State,
    clear_session_cookie,
    set_session_cookie,
)
from capsa.passwords import MAX_LENGTH, PasswordPolicyError

router = APIRouter(tags=["auth"])


class Me(BaseModel):
    id: str
    username: str
    role: Role
    display_name: str | None = Field(default=None, description="shown in greetings")

    @classmethod
    def of(cls, user: User) -> Me:
        return cls(
            id=user.id, username=user.username, role=user.role, display_name=user.display_name
        )


class MeUpdate(BaseModel):
    display_name: str | None = Field(
        max_length=256, description="1-64 characters after trimming; null or empty clears it"
    )


class LoginRequest(BaseModel):
    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=1, max_length=MAX_LENGTH)


class PasswordChange(BaseModel):
    current_password: str = Field(max_length=MAX_LENGTH)
    new_password: str = Field(max_length=MAX_LENGTH)


def _client(request: Request) -> str:
    return request.client.host if request.client else "unknown"


@router.post(
    "/auth/login",
    responses={401: {"description": "Invalid credentials"}, 429: {"description": "Too many"}},
)
def login(body: LoginRequest, request: Request, response: Response, conn: Conn, state: State) -> Me:
    now = state.clock()
    client, key = _client(request), accounts.username_key(body.username)
    wait = state.limiter.retry_after_ms(client, key, now)
    if wait > 0:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "too many failed attempts, try again later",
            headers={"Retry-After": str(math.ceil(wait / 1000))},
        )
    user = accounts.authenticate(conn, state.passwords, body.username, body.password, now)
    if user is None:
        state.limiter.failed(client, key, now)
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid username or password")
    state.limiter.succeeded(client, key)
    sessions.purge_expired(conn, now)
    token = sessions.create(conn, user.id, now, state.settings.session_days)
    set_session_cookie(response, token, state)
    return Me.of(user)


@router.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(request: Request, response: Response, conn: Conn, state: State) -> None:
    token = request.cookies.get(SESSION_COOKIE)
    if token:
        sessions.revoke(conn, token)
    clear_session_cookie(response, state)


@router.get("/me")
def me(user: CurrentUser) -> Me:
    return Me.of(user)


@router.patch("/me", responses={400: {"description": "Invalid display name"}})
def update_me(body: MeUpdate, user: CurrentUser, conn: Conn, state: State) -> Me:
    """Change the own display name."""
    try:
        accounts.set_display_name(conn, user.id, body.display_name, state.clock())
    except AccountError as exc:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(exc)) from None
    return Me.of(accounts.get_user(conn, user.id) or user)


@router.put(
    "/me/password",
    status_code=status.HTTP_204_NO_CONTENT,
    responses={400: {"description": "Policy"}, 403: {"description": "Wrong current password"}},
)
def change_password(
    body: PasswordChange, request: Request, user: CurrentUser, conn: Conn, state: State
) -> None:
    stored = accounts.password_hash(conn, user.id) or ""
    if not state.passwords.verify(stored, body.current_password):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "current password is wrong")
    try:
        accounts.set_password(conn, state.passwords, user.id, body.new_password, state.clock())
    except PasswordPolicyError as exc:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(exc)) from None
    # Sign out everywhere else, e.g. a lost device.
    sessions.revoke_others(conn, user.id, keep_token=request.state.session_token)
