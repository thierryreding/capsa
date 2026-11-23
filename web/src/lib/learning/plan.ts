/**
 * Planning towards a test date (SPEC 7, F8). Pure functions.
 *
 * Goal: every card of the test units is answered correctly at least twice by the test.
 * "Secure" means box 3 or higher, i.e. two right answers in a row since the last
 * mistake (so an old success followed by a mistake does not count). A new or box-1
 * card needs two more right answers, a box-2 card one. The remaining need is spread
 * evenly over the days until the day before the test.
 */
import {
  cardKey,
  dayNumber,
  effectiveTime,
  type AnswerEvent,
  type CardState,
  type LeitnerConfig,
} from './leitner';
import type { Direction } from './match';
import { SECURE_BOX, type EntryRef } from './session';

export { SECURE_BOX };

export interface TestPlan {
  /** Local calendar date of the test, YYYY-MM-DD. */
  date: string;
  units: string[];
}

export interface PlanScope {
  profileId: string;
  entries: EntryRef[];
  directions: readonly Direction[];
}

export interface PlanStatus {
  /** Calendar days until the test: 1 = tomorrow, 0 = today, negative = over. */
  daysLeft: number;
  cards: number;
  secure: number;
  /** Right answers still needed in total. */
  needed: number;
  /** Right answers to give today, judged from the state at the start of the day. */
  goalToday: number;
  /** Right answers given today on cards of the plan. */
  doneToday: number;
}

/** Right answers a card still needs to become secure. */
export function neededFor(state: CardState | undefined): number {
  const box = state?.box ?? 1;
  return Math.max(0, SECURE_BOX - box);
}

/** Calendar day number of a YYYY-MM-DD date, comparable with dayNumber(). */
export function dateDay(date: string): number {
  const [y, m, d] = date.split('-').map(Number);
  return Math.floor(Date.UTC(y, m - 1, d) / 86_400_000);
}

/** Local calendar date (YYYY-MM-DD) of a timestamp. */
export function localDate(ms: number, utcOffsetMinutes: number): string {
  return new Date(dayNumber(ms, utcOffsetMinutes) * 86_400_000).toISOString().slice(0, 10);
}

export function planCards(plan: TestPlan, scope: PlanScope): string[] {
  const units = new Set(plan.units);
  return scope.entries
    .filter((e) => units.has(e.unitId))
    .flatMap((e) => scope.directions.map((d) => cardKey(scope.profileId, e.id, d)));
}

export function planStatus(
  plan: TestPlan,
  scope: PlanScope,
  states: ReadonlyMap<string, CardState>,
  /** Answer events of the profile (only today's matter here). */
  events: readonly AnswerEvent[],
  now: number,
  config: LeitnerConfig,
): PlanStatus {
  const today = dayNumber(now, config.utcOffsetMinutes);
  const daysLeft = dateDay(plan.date) - today;
  const keys = planCards(plan, scope);
  const inPlan = new Set(keys);

  let secure = 0;
  let needed = 0;
  for (const key of keys) {
    const n = neededFor(states.get(key));
    needed += n;
    if (n === 0) secure++;
  }

  let doneToday = 0;
  for (const e of events) {
    if (!e.correct || dayNumber(effectiveTime(e), config.utcOffsetMinutes) !== today) continue;
    if (inPlan.has(cardKey(e.profile_id, e.entry_id, e.direction))) doneToday++;
  }

  // Learning days: today up to the day before the test (on the test day itself: today).
  const days = Math.max(1, daysLeft);
  // Each right answer today removed (at most) one needed answer, so the need at the
  // start of the day is about needed + doneToday; the goal stays fixed during the day.
  const goalToday = daysLeft < 0 ? 0 : Math.ceil((needed + doneToday) / days);
  return { daysLeft, cards: keys.length, secure, needed, goalToday, doneToday };
}
