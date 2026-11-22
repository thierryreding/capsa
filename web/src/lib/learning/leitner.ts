/**
 * Leitner boxes (SPEC 7). Pure functions, no I/O.
 *
 * The learning state is derived deterministically from answer events, ordered by
 * (effective time, id), so every device computes the same state from the same events.
 * State is kept per card: (profile, entry, direction).
 *
 * - Five boxes. A card that was never answered is "new" and counts as box 1.
 * - Correct: one box up (at most the last box). Wrong: back to box 1.
 * - A card is due when the number of calendar days in its box's interval has passed
 *   since its last answer (box 1: 0 days, i.e. again in the same session).
 */

import type { Direction } from './match';

export interface LeitnerConfig {
  /** Interval per box in calendar days; index 0 is box 1. */
  intervalsDays: number[];
  /** Offset of local time from UTC in minutes (e.g. 60 for CET), for calendar days. */
  utcOffsetMinutes: number;
}

export const DEFAULT_INTERVALS_DAYS = [0, 1, 3, 7, 21];

/** A client clock more than this far ahead of the server is not trusted (SPEC 6). */
export const MAX_CLOCK_AHEAD_MS = 24 * 60 * 60 * 1000;

const DAY_MS = 24 * 60 * 60 * 1000;

export interface AnswerEvent {
  id: string;
  profile_id: string;
  entry_id: string;
  direction: Direction;
  correct: boolean;
  /** Client time of the answer (ms since epoch). */
  ts: number;
  /** Server receive time (ms since epoch); absent while not yet synced. */
  received_at?: number | null;
}

export interface CardState {
  box: number;
  /** Effective time of the last answer (ms since epoch). */
  lastAt: number;
  lastCorrect: boolean;
  correctCount: number;
  wrongCount: number;
}

export function cardKey(profileId: string, entryId: string, direction: Direction): string {
  return `${profileId}|${entryId}|${direction}`;
}

/** The time an event counts at: `ts`, unless it lies clearly after its arrival. */
export function effectiveTime(e: Pick<AnswerEvent, 'ts' | 'received_at'>): number {
  if (e.received_at != null && e.ts > e.received_at + MAX_CLOCK_AHEAD_MS) return e.received_at;
  return e.ts;
}

export function compareEvents(a: AnswerEvent, b: AnswerEvent): number {
  const d = effectiveTime(a) - effectiveTime(b);
  if (d !== 0) return d;
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
}

export function applyAnswer(
  state: CardState | undefined,
  correct: boolean,
  at: number,
  config: LeitnerConfig,
): CardState {
  const boxes = config.intervalsDays.length;
  const box = state?.box ?? 1;
  return {
    box: correct ? Math.min(box + 1, boxes) : 1,
    lastAt: at,
    lastCorrect: correct,
    correctCount: (state?.correctCount ?? 0) + (correct ? 1 : 0),
    wrongCount: (state?.wrongCount ?? 0) + (correct ? 0 : 1),
  };
}

/** States of all cards that have events, keyed by cardKey(). */
export function computeStates(
  events: readonly AnswerEvent[],
  config: LeitnerConfig,
): Map<string, CardState> {
  const sorted = [...events].sort(compareEvents);
  const seen = new Set<string>();
  const states = new Map<string, CardState>();
  for (const e of sorted) {
    if (seen.has(e.id)) continue; // the same event from two sources counts once
    seen.add(e.id);
    const key = cardKey(e.profile_id, e.entry_id, e.direction);
    states.set(key, applyAnswer(states.get(key), e.correct, effectiveTime(e), config));
  }
  return states;
}

/** Local calendar day number of a timestamp. */
export function dayNumber(ms: number, utcOffsetMinutes: number): number {
  return Math.floor((ms + utcOffsetMinutes * 60_000) / DAY_MS);
}

/** Calendar day on which the card becomes due again. */
export function dueDay(state: CardState, config: LeitnerConfig): number {
  const interval = config.intervalsDays[state.box - 1] ?? 0;
  return dayNumber(state.lastAt, config.utcOffsetMinutes) + interval;
}

/** New cards (no state) are not "due": they are offered separately. */
export function isDue(state: CardState | undefined, now: number, config: LeitnerConfig): boolean {
  if (!state) return false;
  return dayNumber(now, config.utcOffsetMinutes) >= dueDay(state, config);
}

/** A card whose last answer was wrong. */
export function isMistake(state: CardState | undefined): boolean {
  return state !== undefined && !state.lastCorrect;
}
