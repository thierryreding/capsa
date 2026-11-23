"""Learning statistics of an account, for parents (F9)."""

from __future__ import annotations

import json
from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import select

from capsa import accounts
from capsa.db import events
from capsa.deps import Admin, Conn, State
from capsa.leitner import AnswerEvent, Config
from capsa.progress import learning_stats

router = APIRouter(tags=["admin"])


class DayCount(BaseModel):
    date: str = Field(description="local calendar date, YYYY-MM-DD")
    correct: int
    wrong: int


class UnitProgress(BaseModel):
    unit_id: str
    number: int
    title: str
    cards: int
    fresh: int
    secure: int = Field(description="cards in box 3 or higher")
    mistakes: int
    boxes: list[int] = Field(description="cards per box, index 0 = box 1")
    answers_recent: int = Field(description="answers in the last 30 days")
    correct_recent: int


class HardEntry(BaseModel):
    entry_id: str
    lemma: str
    meaning: str
    wrong: int
    correct: int
    last_correct: bool


class LearningStats(BaseModel):
    profile_id: str
    directions: list[Literal["src_to_tr", "tr_to_src"]]
    total_answers: int
    last_answer_at: int | None = Field(description="ms since the epoch")
    days: list[DayCount] = Field(description="the last 14 days, oldest first")
    units: list[UnitProgress]
    hardest: list[HardEntry] = Field(description="up to 10 entries most often answered wrong")


@router.get(
    "/admin/users/{user_id}/progress/{profile_id}",
    responses={404: {"description": "No such user or profile"}},
)
def user_progress(
    user_id: str,
    profile_id: str,
    admin: Admin,
    conn: Conn,
    state: State,
    utc_offset: Annotated[
        int, Query(ge=-14 * 60, le=14 * 60, description="local time offset in minutes")
    ] = 0,
) -> LearningStats:
    user = accounts.get_user(conn, user_id)
    profile = state.profiles.get(profile_id)
    if user is None or profile is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "no such user or profile")
    rows = conn.execute(
        select(events).where(events.c.user_id == user.id, events.c.profile_id == profile_id)
    )
    answers = [
        AnswerEvent(
            id=r.id,
            profile_id=r.profile_id,
            entry_id=r.entry_id,
            direction=r.direction,
            correct=r.correct,
            ts=r.ts,
            received_at=r.received_at,
        )
        for r in rows
    ]
    config = Config(utc_offset_minutes=utc_offset)
    return LearningStats(**learning_stats(json.loads(profile.body), answers, state.clock(), config))
