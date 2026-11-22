"""Profiles released to the signed-in user (SPEC 5: /profiles)."""

from __future__ import annotations

from fastapi import APIRouter, Request, Response, status
from pydantic import BaseModel

from capsa.access import readable_profiles, require_profile
from capsa.deps import Conn, CurrentUser, State

router = APIRouter(tags=["profiles"])


class ProfileSummary(BaseModel):
    id: str
    title: str
    source_lang: str
    required_translation_lang: str
    translation_langs: list[str]
    revision: int
    etag: str


@router.get("/profiles")
def list_profiles(user: CurrentUser, conn: Conn, state: State) -> list[ProfileSummary]:
    return [
        ProfileSummary(
            id=p.id,
            title=p.title,
            source_lang=p.source_lang,
            required_translation_lang=p.required_translation_lang,
            translation_langs=list(p.translation_langs),
            revision=p.revision,
            etag=p.etag,
        )
        for p in readable_profiles(conn, user, state.profiles)
    ]


def _etag_matches(header: str | None, etag: str) -> bool:
    if not header:
        return False
    tags = {t.strip().removeprefix("W/") for t in header.split(",")}
    return "*" in tags or etag in tags


@router.get(
    "/profiles/{profile_id}",
    response_class=Response,
    responses={
        200: {
            "description": "The profile document (see schemas/profile.schema.json).",
            "content": {"application/json": {"schema": {"type": "object"}}},
        },
        304: {"description": "Not modified (If-None-Match matched the ETag)."},
        404: {"description": "No such profile, or not released to this account."},
    },
)
def get_profile(
    profile_id: str, request: Request, user: CurrentUser, conn: Conn, state: State
) -> Response:
    profile = require_profile(conn, user, state.profiles, profile_id)
    headers = {"ETag": profile.etag, "Cache-Control": "private, no-cache"}
    if _etag_matches(request.headers.get("if-none-match"), profile.etag):
        return Response(status_code=status.HTTP_304_NOT_MODIFIED, headers=headers)
    return Response(profile.body, media_type="application/json", headers=headers)
