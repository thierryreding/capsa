/**
 * Learning statistics for one profile (F9). Pure functions.
 *
 * Mirrors api/src/capsa/progress.py; both must pass vectors/stats.json, so the child's
 * view (computed here, offline) and the parent's view (from the server) agree.
 * See the Python module for the definitions (directions, secure, recent, history).
 */
import type { ProfileDocument, Schemas } from '../api/client';
import {
  cardKey,
  computeStates,
  dayNumber,
  effectiveTime,
  isMistake,
  type AnswerEvent,
  type LeitnerConfig,
} from './leitner';
import type { Direction } from './match';
import { SECURE_BOX } from './session';

export type LearningStats = Schemas['LearningStats'];

export const HISTORY_DAYS = 14;
export const RECENT_DAYS = 30;
export const HARDEST = 10;
const DAY_MS = 86_400_000;

const isoDay = (day: number) => new Date(day * DAY_MS).toISOString().slice(0, 10);

export function learningStats(
  doc: ProfileDocument,
  events: readonly AnswerEvent[],
  now: number,
  config: LeitnerConfig,
): LearningStats {
  const profile = doc.profile;
  const lang = profile.required_translation_lang;
  const active = doc.units.flatMap((unit) =>
    unit.entries.filter((e) => !e.deprecated).map((entry) => ({ unit, entry })),
  );
  const order = new Map(active.map(({ entry }, i) => [entry.id, i]));
  const unitOf = new Map(active.map(({ unit, entry }) => [entry.id, unit.id]));

  const unique = new Map<string, AnswerEvent>();
  for (const e of events) {
    if (e.profile_id === profile.id && order.has(e.entry_id) && !unique.has(e.id)) {
      unique.set(e.id, e);
    }
  }
  const mine = [...unique.values()].sort(
    (a, b) => effectiveTime(a) - effectiveTime(b) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0),
  );

  const practised = [...new Set(mine.map((e) => e.direction))].sort();
  const directions: Direction[] = practised.length ? practised : ['src_to_tr'];
  const states = computeStates(mine, config);
  const today = dayNumber(now, config.utcOffsetMinutes);
  const dayOf = (e: AnswerEvent) => dayNumber(effectiveTime(e), config.utcOffsetMinutes);

  const units = doc.units.map((unit) => {
    const entries = unit.entries.filter((e) => !e.deprecated);
    const row = {
      unit_id: unit.id,
      number: unit.number,
      title: unit.title,
      cards: entries.length * directions.length,
      fresh: 0,
      secure: 0,
      mistakes: 0,
      boxes: config.intervalsDays.map(() => 0),
      answers_recent: 0,
      correct_recent: 0,
    };
    for (const entry of entries) {
      for (const direction of directions) {
        const state = states.get(cardKey(profile.id, entry.id, direction));
        if (!state) {
          row.fresh++;
          continue;
        }
        row.boxes[state.box - 1]++;
        if (state.box >= SECURE_BOX) row.secure++;
        if (isMistake(state)) row.mistakes++;
      }
    }
    return row;
  });
  const byUnit = new Map(units.map((u) => [u.unit_id, u]));
  for (const e of mine) {
    if (today - dayOf(e) < RECENT_DAYS) {
      const u = byUnit.get(unitOf.get(e.entry_id)!)!;
      u.answers_recent++;
      if (e.correct) u.correct_recent++;
    }
  }

  const first = today - HISTORY_DAYS + 1;
  const days = Array.from({ length: HISTORY_DAYS }, (_, i) => ({
    date: isoDay(first + i),
    correct: 0,
    wrong: 0,
  }));
  for (const e of mine) {
    const i = dayOf(e) - first;
    if (i >= 0 && i < HISTORY_DAYS) days[i][e.correct ? 'correct' : 'wrong']++;
  }

  const perEntry = new Map<string, { wrong: number; correct: number; last: boolean }>();
  for (const e of mine) {
    const s = perEntry.get(e.entry_id) ?? { wrong: 0, correct: 0, last: false };
    if (e.correct) s.correct++;
    else s.wrong++;
    s.last = e.correct;
    perEntry.set(e.entry_id, s);
  }
  const entryById = new Map(active.map(({ entry }) => [entry.id, entry]));
  const hardest = [...perEntry]
    .filter(([, s]) => s.wrong > 0)
    .sort(([ida, a], [idb, b]) => {
      if (a.wrong !== b.wrong) return b.wrong - a.wrong;
      // higher error rate first, compared exactly
      const ratio = b.wrong * (a.wrong + a.correct) - a.wrong * (b.wrong + b.correct);
      if (ratio !== 0) return ratio;
      return order.get(ida)! - order.get(idb)!;
    })
    .slice(0, HARDEST)
    .map(([id, s]) => {
      const entry = entryById.get(id)!;
      return {
        entry_id: id,
        lemma: entry.lemma,
        meaning: entry.tr[lang]?.[0] ?? '',
        wrong: s.wrong,
        correct: s.correct,
        last_correct: s.last,
      };
    });

  return {
    profile_id: profile.id,
    directions,
    total_answers: mine.length,
    last_answer_at: mine.length ? effectiveTime(mine[mine.length - 1]) : null,
    days,
    units,
    hardest,
  };
}
