import { describe, expect, it } from 'vitest';
import {
  applyAnswer,
  cardKey,
  computeStates,
  DEFAULT_INTERVALS_DAYS,
  effectiveTime,
  isDue,
  isMistake,
  type AnswerEvent,
  type CardState,
  type LeitnerConfig,
} from './leitner';
import { loadJson } from './testing';

interface Scenario {
  name: string;
  events: AnswerEvent[];
  states: Record<string, CardState>;
  checks: { now: number; due: string[]; why?: string }[];
}

const vectors = loadJson<{ config: LeitnerConfig; scenarios: Scenario[] }>('vectors/leitner.json');

describe('shared vectors (vectors/leitner.json)', () => {
  it.each(vectors.scenarios)('$name', (s) => {
    const states = computeStates(s.events, vectors.config);
    expect(Object.fromEntries(states)).toEqual(s.states);
    for (const check of s.checks) {
      const due = [...states].filter(([, st]) => isDue(st, check.now, vectors.config));
      expect(due.map(([k]) => k).sort(), check.why ?? String(check.now)).toEqual(check.due);
    }
  });
});

describe('leitner', () => {
  const config: LeitnerConfig = { intervalsDays: DEFAULT_INTERVALS_DAYS, utcOffsetMinutes: 0 };

  it('new cards are neither due nor mistakes', () => {
    expect(isDue(undefined, Date.now(), config)).toBe(false);
    expect(isMistake(undefined)).toBe(false);
  });

  it('configurable number of boxes', () => {
    const three = { ...config, intervalsDays: [0, 2, 5] };
    let st = applyAnswer(undefined, true, 0, three);
    st = applyAnswer(st, true, 1, three);
    st = applyAnswer(st, true, 2, three);
    expect(st.box).toBe(3);
  });

  it('mistake is a card whose last answer was wrong', () => {
    const wrong = applyAnswer(undefined, false, 0, config);
    expect(isMistake(wrong)).toBe(true);
    expect(isMistake(applyAnswer(wrong, true, 1, config))).toBe(false);
  });

  it('effective time ignores received_at for unsynced events', () => {
    expect(effectiveTime({ ts: 5 })).toBe(5);
    expect(effectiveTime({ ts: 5, received_at: null })).toBe(5);
  });

  it('cardKey', () => {
    expect(cardKey('p', 'e', 'tr_to_src')).toBe('p|e|tr_to_src');
  });
});
