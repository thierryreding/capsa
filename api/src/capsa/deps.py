"""Shared request dependencies: application state, DB transaction, current user."""

from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass
from typing import Annotated

from fastapi import Depends, HTTPException, Request, Response, status
from sqlalchemy import Connection, Engine

from capsa import sessions
from capsa.accounts import User
from capsa.clock import Clock
from capsa.config import Settings
from capsa.passwords import Passwords
from capsa.profiles import ProfileStore
from capsa.ratelimit import LoginLimiter

SESSION_COOKIE = "capsa_session"
CSRF_HEADER = "X-Capsa-CSRF"


@dataclass
class AppState:
    settings: Settings
    engine: Engine
    passwords: Passwords
    clock: Clock
    limiter: LoginLimiter
    profiles: ProfileStore


def get_state(request: Request) -> AppState:
    return request.app.state.capsa


State = Annotated[AppState, Depends(get_state)]


def get_conn(state: State) -> Iterator[Connection]:
    """One transaction per request, committed before the response is sent."""
    with state.engine.begin() as conn:
        yield conn


# scope="function": the transaction ends (commits) before the response goes out.
Conn = Annotated[Connection, Depends(get_conn, scope="function")]


def set_session_cookie(response: Response, token: str, state: AppState) -> None:
    response.set_cookie(
        SESSION_COOKIE,
        token,
        max_age=state.settings.session_days * 24 * 60 * 60,
        path="/api",
        httponly=True,
        secure=state.settings.cookie_secure,
        samesite="strict",
    )


def clear_session_cookie(response: Response, state: AppState) -> None:
    response.delete_cookie(
        SESSION_COOKIE,
        path="/api",
        httponly=True,
        secure=state.settings.cookie_secure,
        samesite="strict",
    )


def _unauthorized() -> HTTPException:
    return HTTPException(status.HTTP_401_UNAUTHORIZED, "not signed in")


def get_current_user(request: Request, response: Response, conn: Conn, state: State) -> User:
    token = request.cookies.get(SESSION_COOKIE)
    if not token:
        raise _unauthorized()
    found = sessions.lookup(conn, token, state.clock(), state.settings.session_days)
    if found is None:
        raise _unauthorized()
    user, renewed = found
    if renewed:
        set_session_cookie(response, token, state)
    request.state.session_token = token
    return user


CurrentUser = Annotated[User, Depends(get_current_user, scope="function")]


def get_admin(user: CurrentUser) -> User:
    if not user.is_admin:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "admin only")
    return user


Admin = Annotated[User, Depends(get_admin, scope="function")]
