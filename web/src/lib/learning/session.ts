/**
 * Choosing cards for a learning session and running it (SPEC 7, F7). Pure functions.
 *
 * A card is one entry in one direction. A session has 10 cards by default; the
 * default selection mixes mistakes, due cards and new cards. Within a session a
 * wrongly answered card comes back a few cards later (box 1 = "same session").
 */

import {
  cardKey,
  isDue,
  isMistake,
  type CardState,
  type LeitnerConfig,
} from './leitner';
import type { Direction } from './match';

/** Box from which a card counts as secure for a test (two right answers in a row). */
export const SECURE_BOX = 3;

export interface Card {
  entryId: string;
  direction: Direction;
}

export interface EntryRef {
  id: string;
  unitId: string;
}

/**
 * mixed: mistakes, then due, then new cards.
 * test: cards not yet secure for a test (box < 3): mistakes, then box 2, then new.
 */
export type Selection = 'mixed' | 'due' | 'mistakes' | 'all' | 'test';

export interface SelectOptions {
  profileId: string;
  /** Active (non-deprecated) entries in book order. */
  entries: EntryRef[];
  units: ReadonlySet<string>;
  directions: readonly Direction[];
  selection: Selection;
  size: number;
  now: number;
  config: LeitnerConfig;
  /** Random number in [0, 1); injectable for tests. */
  random?: () => number;
}

export const DEFAULT_SESSION_SIZE = 10;

function shuffle<T>(items: T[], random: () => number): T[] {
  const a = [...items];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

interface Candidate {
  card: Card;
  state: CardState | undefined;
  order: number;
}

type CardScope = Pick<SelectOptions, 'profileId' | 'entries' | 'units' | 'directions'>;

function candidates(states: ReadonlyMap<string, CardState>, o: CardScope): Candidate[] {
  const out: Candidate[] = [];
  let order = 0;
  for (const e of o.entries) {
    if (!o.units.has(e.unitId)) continue;
    for (const direction of o.directions) {
      out.push({
        card: { entryId: e.id, direction },
        state: states.get(cardKey(o.profileId, e.id, direction)),
        order: order++,
      });
    }
  }
  return out;
}

const byOldest = (a: Candidate, b: Candidate) => a.state!.lastAt - b.state!.lastAt;
const byBoxThenOldest = (a: Candidate, b: Candidate) =>
  a.state!.box - b.state!.box || byOldest(a, b);

export function selectCards(states: ReadonlyMap<string, CardState>, o: SelectOptions): Card[] {
  const random = o.random ?? Math.random;
  const all = candidates(states, o);
  const mistakes = all.filter((c) => isMistake(c.state)).sort(byOldest);
  const due = all
    .filter((c) => !isMistake(c.state) && isDue(c.state, o.now, o.config))
    .sort(byBoxThenOldest);
  const fresh = all.filter((c) => c.state === undefined);

  let picked: Candidate[];
  switch (o.selection) {
    case 'mistakes':
      picked = mistakes;
      break;
    case 'due':
      picked = [...mistakes.filter((c) => isDue(c.state, o.now, o.config)), ...due];
      break;
    case 'all':
      picked = shuffle(all, random);
      break;
    case 'mixed':
      picked = [...mistakes, ...due, ...fresh];
      break;
    case 'test': {
      const almost = all
        .filter((c) => c.state && !isMistake(c.state) && c.state.box < SECURE_BOX)
        .sort(byOldest);
      picked = [...mistakes, ...almost, ...fresh];
      break;
    }
  }
  return shuffle(
    picked.slice(0, o.size).map((c) => c.card),
    random,
  );
}

export interface Progress {
  total: number;
  fresh: number;
  due: number;
  mistakes: number;
  /** Number of cards per box (index 0 = box 1), not counting new cards. */
  boxes: number[];
}

/** Progress per unit for the given directions (F9). */
export function progressByUnit(
  states: ReadonlyMap<string, CardState>,
  o: Omit<SelectOptions, 'selection' | 'size' | 'random'>,
): Map<string, Progress> {
  const result = new Map<string, Progress>();
  const unitOf = new Map(o.entries.map((e) => [e.id, e.unitId]));
  for (const c of candidates(states, o)) {
    const unit = unitOf.get(c.card.entryId)!;
    let p = result.get(unit);
    if (!p) {
      p = { total: 0, fresh: 0, due: 0, mistakes: 0, boxes: o.config.intervalsDays.map(() => 0) };
      result.set(unit, p);
    }
    p.total++;
    if (!c.state) {
      p.fresh++;
      continue;
    }
    p.boxes[c.state.box - 1]++;
    if (isMistake(c.state)) p.mistakes++;
    if (isDue(c.state, o.now, o.config)) p.due++;
  }
  return result;
}

// --- running a session ------------------------------------------------------

/** A wrong card comes back after this many other cards ... */
export const REPEAT_GAP = 3;
/** ... at most this many times per session. */
export const MAX_REPEATS = 2;

export interface SessionResult {
  card: Card;
  correct: boolean;
}

export interface Session {
  readonly queue: readonly Card[];
  readonly results: readonly SessionResult[];
  readonly repeats: Readonly<Record<string, number>>;
}

const key = (c: Card) => `${c.entryId}|${c.direction}`;

export function startSession(cards: readonly Card[]): Session {
  return { queue: [...cards], results: [], repeats: {} };
}

export function currentCard(s: Session): Card | undefined {
  return s.queue[0];
}

export function isFinished(s: Session): boolean {
  return s.queue.length === 0;
}

export function answerCard(s: Session, correct: boolean): Session {
  const [card, ...rest] = s.queue;
  if (!card) return s;
  const results = [...s.results, { card, correct }];
  const repeats = { ...s.repeats };
  const queue = [...rest];
  if (!correct && (repeats[key(card)] ?? 0) < MAX_REPEATS) {
    repeats[key(card)] = (repeats[key(card)] ?? 0) + 1;
    queue.splice(Math.min(REPEAT_GAP, queue.length), 0, card);
  }
  return { queue, results, repeats };
}

/** Summary: distinct cards, and how many were right at their first attempt. */
export function summary(s: Session): { cards: number; firstTry: number; answers: number } {
  const first = new Map<string, boolean>();
  for (const r of s.results) if (!first.has(key(r.card))) first.set(key(r.card), r.correct);
  return {
    cards: first.size,
    firstTry: [...first.values()].filter(Boolean).length,
    answers: s.results.length,
  };
}
