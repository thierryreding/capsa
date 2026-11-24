import 'package:capsa/learning/leitner.dart';
import 'package:capsa/learning/match.dart';
import 'package:capsa/learning/plan.dart';
import 'package:capsa/learning/session.dart';
import 'package:flutter_test/flutter_test.dart';

const config = LeitnerConfig(utcOffsetMinutes: 60);
// 2027-01-15 09:00 CET
final now = DateTime.utc(2027, 1, 15, 8).millisecondsSinceEpoch;
const hour = 3600000;
const entries = [
  EntryRef('a', 'u1'),
  EntryRef('b', 'u1'),
  EntryRef('c', 'u2'),
  EntryRef('x', 'u3'),
];

CardState state(List<bool> answers) {
  CardState? s;
  for (var i = 0; i < answers.length; i++) {
    s = applyAnswer(s, answers[i], now - (10 - i) * 86400000, config);
  }
  return s!;
}

String key(String id) => cardKey('p', id, Direction.srcToTr);

AnswerEvent event(String id, bool correct, int ts) => AnswerEvent(
  id: '$id-$ts',
  profileId: 'p',
  entryId: id,
  direction: Direction.srcToTr,
  correct: correct,
  ts: ts,
);

PlanStatus status(
  TestPlan plan, {
  Map<String, CardState> states = const {},
  List<AnswerEvent> events = const [],
  int? at,
}) => planStatus(
  plan,
  profileId: 'p',
  entries: entries,
  directions: [Direction.srcToTr],
  states: states,
  events: events,
  now: at ?? now,
  config: config,
);

void main() {
  test('local calendar dates and day numbers agree', () {
    expect(localDate(now, 60), '2027-01-15');
    expect(localDate(DateTime.utc(2027, 1, 15, 23, 30).millisecondsSinceEpoch, 60), '2027-01-16');
    expect(dateDay('2027-01-16') - dateDay('2027-01-15'), 1);
    expect(dateDay(localDate(now, 60)), dayNumber(now, 60));
  });

  test('neededFor: secure from box 3 on', () {
    expect(neededFor(null), 2);
    expect(neededFor(state([false])), 2);
    expect(neededFor(state([true])), 1); // box 2
    expect(neededFor(state([true, true])), 0); // box 3
    expect(neededFor(state([true, true, false])), 2); // mistake: back to box 1
  });

  group('planStatus', () {
    const plan = TestPlan(date: '2027-01-20', units: ['u1', 'u2']);
    TestPlan on(String date) => TestPlan(date: date, units: plan.units);

    test('counts cards, secure cards and the answers needed', () {
      final states = {
        key('a'): state([true, true]), // secure
        key('b'): state([true]), // needs 1
        // c is new: needs 2; x is not in the plan
        key('x'): state([false]),
      };
      expect(status(plan, states: states).toJson(), {
        'daysLeft': 5,
        'cards': 3,
        'secure': 1,
        'needed': 3,
        'goalToday': 1,
        'doneToday': 0,
      });
    });
    test('spreads the need over the days before the test', () {
      final s = status(on('2027-01-17'));
      expect(s.needed, 6);
      expect(s.goalToday, 3); // two learning days: today and tomorrow
    });
    test('the goal does not shrink while answering today', () {
      var states = <String, CardState>{};
      final events = <AnswerEvent>[];
      for (final id in ['a', 'b']) {
        final ts = now + hour;
        states = {...states, key(id): applyAnswer(states[key(id)], true, ts, config)};
        events.add(event(id, true, ts));
      }
      final s = status(on('2027-01-17'), states: states, events: events, at: now + 2 * hour);
      expect([s.needed, s.doneToday, s.goalToday], [4, 2, 3]);
    });
    test("yesterday's answers and other units do not count for today", () {
      final events = [
        event('a', true, now - 24 * hour),
        event('x', true, now),
        event('b', false, now),
      ];
      expect(status(plan, events: events).doneToday, 0);
    });
    test('on the test day everything left is for today; afterwards nothing', () {
      final today = status(on('2027-01-15'));
      expect([today.daysLeft, today.goalToday], [0, 6]);
      final over = status(on('2027-01-14'));
      expect([over.daysLeft, over.goalToday], [-1, 0]);
    });
    test('both directions double the cards', () {
      expect(
        planCards(plan, profileId: 'p', entries: entries, directions: Direction.values),
        hasLength(6),
      );
    });
  });
}
