"""The one place that decides who may read which profile (SPEC 8, 11).

Every endpoint that touches profile content or profile-related data goes through
these functions; access checks are not scattered across endpoints.
"""

from __future__ import annotations

from fastapi import HTTPException, status
from sqlalchemy import Connection

from capsa import accounts
from capsa.accounts import User
from capsa.profiles import LoadedProfile, ProfileStore


def can_read(user: User, granted: set[str], profile_id: str) -> bool:
    """Admins (parents) read every profile; learners only those released to them."""
    return user.is_admin or profile_id in granted


def readable_profiles(conn: Connection, user: User, store: ProfileStore) -> list[LoadedProfile]:
    granted = set() if user.is_admin else accounts.grants(conn, user.id)
    return [p for p in store.all() if can_read(user, granted, p.id)]


def require_profile(
    conn: Connection, user: User, store: ProfileStore, profile_id: str
) -> LoadedProfile:
    """The profile, or 404 both when it does not exist and when it is not released."""
    profile = store.get(profile_id)
    granted = set() if user.is_admin else accounts.grants(conn, user.id)
    if profile is None or not can_read(user, granted, profile_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "no such profile")
    return profile
