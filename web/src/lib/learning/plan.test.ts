import { describe, expect, it } from 'vitest';
import { applyAnswer, cardKey, type AnswerEvent, type CardState, type LeitnerConfig } from './leitner';
import { dateDay, localDate, neededFor, planCards, planStatus, type PlanScope } from './plan';

const config: LeitnerConfig = { intervalsDays: [0, 1, 3, 7, 21], utcOffsetMinutes: 60 };
// 2027-01-15 09:00 CET
const NOW = Date.UTC(2027, 0, 15, 8, 0);
const HOUR = 3_600_000;

const scope: PlanScope = {
  profileId: 'p',
  entries: [
    { id: 'a', unitId: 'u1' },
    { id: 'b', unitId: 'u1' },
    { id: 'c', unitId: 'u2' },
    { id: 'x', unitId: 'u3' },
  ],
  directions: ['src_to_tr'],
};

function state(...answers: boolean[]): CardState {
  let s: CardState | undefined;
  answers.forEach((c, i) => (s = applyAnswer(s, c, NOW - (10 - i) * 86_400_000, config)));
  return s!;
}

const key = (id: string) => cardKey('p', id, 'src_to_tr');

function event(id: string, correct: boolean, ts: number): AnswerEvent {
  return { id: `${id}-${ts}`, profile_id: 'p', entry_id: id, direction: 'src_to_tr', correct, ts };
}

describe('dates', () => {
  it('local calendar dates and day numbers agree', () => {
    expect(localDate(NOW, 60)).toBe('2027-01-15');
    expect(localDate(Date.UTC(2027, 0, 15, 23, 30), 60)).toBe('2027-01-16'); // 00:30 CET
    expect(dateDay('2027-01-16') - dateDay('2027-01-15')).toBe(1);
  });
});

describe('neededFor', () => {
  it('secure from box 3 on', () => {
    expect(neededFor(undefined)).toBe(2);
    expect(neededFor(state(false))).toBe(2);
    expect(neededFor(state(true))).toBe(1); // box 2
    expect(neededFor(state(true, true))).toBe(0); // box 3
    expect(neededFor(state(true, true, false))).toBe(2); // mistake: back to box 1
  });
});

describe('planStatus', () => {
  const plan = { date: '2027-01-20', units: ['u1', 'u2'] };

  it('counts cards, secure cards and the answers needed', () => {
    const states = new Map([
      [key('a'), state(true, true)], // secure
      [key('b'), state(true)], // needs 1
      // c is new: needs 2; x is not in the plan
      [key('x'), state(false)],
    ]);
    const s = planStatus(plan, scope, states, [], NOW, config);
    expect(s).toEqual({ daysLeft: 5, cards: 3, secure: 1, needed: 3, goalToday: 1, doneToday: 0 });
  });

  it('spreads the need over the days before the test', () => {
    const s = planStatus({ ...plan, date: '2027-01-17' }, scope, new Map(), [], NOW, config);
    expect(s.needed).toBe(6);
    expect(s.goalToday).toBe(3); // two learning days: today and tomorrow
  });

  it('the goal does not shrink while answering today', () => {
    const p = { ...plan, date: '2027-01-17' };
    let states = new Map<string, CardState>();
    const events: AnswerEvent[] = [];
    for (const id of ['a', 'b']) {
      const ts = NOW + HOUR;
      states = new Map(states).set(key(id), applyAnswer(states.get(key(id)), true, ts, config));
      events.push(event(id, true, ts));
    }
    const s = planStatus(p, scope, states, events, NOW + 2 * HOUR, config);
    expect([s.needed, s.doneToday, s.goalToday]).toEqual([4, 2, 3]);
  });

  it("yesterday's answers and other units do not count for today", () => {
    const events = [event('a', true, NOW - 24 * HOUR), event('x', true, NOW), event('b', false, NOW)];
    expect(planStatus(plan, scope, new Map(), events, NOW, config).doneToday).toBe(0);
  });

  it('on the test day everything left is for today; afterwards nothing', () => {
    expect(planStatus({ ...plan, date: '2027-01-15' }, scope, new Map(), [], NOW, config)).toMatchObject(
      { daysLeft: 0, goalToday: 6 },
    );
    expect(planStatus({ ...plan, date: '2027-01-14' }, scope, new Map(), [], NOW, config)).toMatchObject(
      { daysLeft: -1, goalToday: 0 },
    );
  });

  it('both directions double the cards', () => {
    const both = { ...scope, directions: ['src_to_tr', 'tr_to_src'] as const };
    expect(planCards(plan, both)).toHaveLength(6);
  });
});
