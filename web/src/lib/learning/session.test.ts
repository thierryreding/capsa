import { describe, expect, it } from 'vitest';
import { applyAnswer, cardKey, type CardState, type LeitnerConfig } from './leitner';
import {
  answerCard,
  currentCard,
  isFinished,
  MAX_REPEATS,
  progressByUnit,
  selectCards,
  startSession,
  summary,
  type Card,
  type EntryRef,
  type SelectOptions,
} from './session';

const DAY = 24 * 60 * 60 * 1000;
const NOW = 1_800_000_000_000;
const config: LeitnerConfig = { intervalsDays: [0, 1, 3, 7, 21], utcOffsetMinutes: 0 };

const entries: EntryRef[] = [
  ...['a', 'b', 'c', 'd', 'e', 'f'].map((id) => ({ id, unitId: 'u1' })),
  ...['x', 'y'].map((id) => ({ id, unitId: 'u2' })),
];

/** States built from answers: [entry, correct, daysAgo] in chronological order. */
function states(answers: [string, boolean, number][]): Map<string, CardState> {
  const m = new Map<string, CardState>();
  for (const [entry, correct, daysAgo] of answers) {
    const k = cardKey('p', entry, 'src_to_tr');
    m.set(k, applyAnswer(m.get(k), correct, NOW - daysAgo * DAY, config));
  }
  return m;
}

function options(overrides: Partial<SelectOptions> = {}): SelectOptions {
  return {
    profileId: 'p',
    entries,
    units: new Set(['u1']),
    directions: ['src_to_tr'],
    selection: 'mixed',
    size: 10,
    now: NOW,
    config,
    random: () => 0.999, // keeps order: the Fisher-Yates swap is a no-op
    ...overrides,
  };
}

const ids = (cards: Card[]) => cards.map((c) => c.entryId);

describe('selectCards', () => {
  // a: mistake; b: due (box 2, 2 days ago); c: not due (box 2, today); d, e, f: new
  const st = states([
    ['a', false, 1],
    ['b', true, 2],
    ['c', true, 0],
  ]);

  it('mixed: mistakes, then due, then new cards', () => {
    expect(ids(selectCards(st, options()))).toEqual(['a', 'b', 'd', 'e', 'f']);
    expect(ids(selectCards(st, options({ size: 3 })))).toEqual(['a', 'b', 'd']);
  });

  it('due only and mistakes only', () => {
    expect(ids(selectCards(st, options({ selection: 'due' })))).toEqual(['a', 'b']);
    expect(ids(selectCards(st, options({ selection: 'mistakes' })))).toEqual(['a']);
  });

  it('all: every card of the selected units', () => {
    expect(ids(selectCards(st, options({ selection: 'all' }))).sort()).toEqual(
      ['a', 'b', 'c', 'd', 'e', 'f'],
    );
  });

  it('restricts to the selected units', () => {
    expect(ids(selectCards(st, options({ units: new Set(['u2']) })))).toEqual(['x', 'y']);
  });

  it('due cards in lower boxes and older ones first', () => {
    const s = states([
      ['a', true, 30], ['a', true, 29], ['a', true, 25], // box 4, last 25 days ago
      ['b', true, 5], // box 2, 5 days ago
      ['c', true, 3], // box 2, 3 days ago
    ]);
    expect(ids(selectCards(s, options({ selection: 'due' })))).toEqual(['b', 'c', 'a']);
  });

  it('both directions are separate cards', () => {
    const cards = selectCards(new Map(), options({ directions: ['src_to_tr', 'tr_to_src'], size: 4 }));
    expect(cards.map((c) => `${c.entryId}:${c.direction}`)).toEqual([
      'a:src_to_tr', 'a:tr_to_src', 'b:src_to_tr', 'b:tr_to_src',
    ]);
  });

  it('shuffles the selection', () => {
    let seed = 1;
    const random = () => ((seed = (seed * 16807) % 2147483647) - 1) / 2147483646;
    const cards = ids(selectCards(st, options({ random })));
    expect(cards.sort()).toEqual(['a', 'b', 'd', 'e', 'f']);
  });
});

describe('progressByUnit', () => {
  it('counts new, due, mistakes and boxes per unit', () => {
    const st = states([
      ['a', false, 1],
      ['b', true, 2],
      ['c', true, 0],
      ['x', true, 0],
    ]);
    const p = progressByUnit(st, options({ units: new Set(['u1', 'u2']) }));
    expect(p.get('u1')).toEqual({ total: 6, fresh: 3, due: 2, mistakes: 1, boxes: [1, 2, 0, 0, 0] });
    expect(p.get('u2')).toEqual({ total: 2, fresh: 1, due: 0, mistakes: 0, boxes: [0, 1, 0, 0, 0] });
  });
});

describe('session', () => {
  const cards: Card[] = ['a', 'b', 'c', 'd', 'e'].map((entryId) => ({
    entryId,
    direction: 'src_to_tr',
  }));

  it('runs through the cards', () => {
    let s = startSession(cards.slice(0, 2));
    expect(currentCard(s)?.entryId).toBe('a');
    s = answerCard(s, true);
    s = answerCard(s, true);
    expect(isFinished(s)).toBe(true);
    expect(summary(s)).toEqual({ cards: 2, firstTry: 2, answers: 2 });
  });

  it('repeats a wrong card three cards later', () => {
    let s = startSession(cards);
    s = answerCard(s, false); // a wrong
    expect(ids([...s.queue])).toEqual(['b', 'c', 'd', 'a', 'e']);
  });

  it('repeats at the end when few cards are left', () => {
    let s = startSession(cards.slice(0, 2));
    s = answerCard(s, false);
    expect(ids([...s.queue])).toEqual(['b', 'a']);
  });

  it(`repeats a card at most ${MAX_REPEATS} times`, () => {
    let s = startSession(cards.slice(0, 1));
    for (let i = 0; i < 5 && !isFinished(s); i++) s = answerCard(s, false);
    expect(s.results.length).toBe(1 + MAX_REPEATS);
    expect(isFinished(s)).toBe(true);
    expect(summary(s)).toEqual({ cards: 1, firstTry: 0, answers: 3 });
  });
});
