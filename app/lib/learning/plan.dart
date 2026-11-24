/// Planning towards a test date (SPEC 7, F8). Pure functions.
/// A port of web/src/lib/learning/plan.ts.
///
/// Goal: every card of the test units is answered correctly at least twice by the test.
/// "Secure" means box 3 or higher, i.e. two right answers in a row since the last
/// mistake. A new or box-1 card needs two more right answers, a box-2 card one. The
/// remaining need is spread evenly over the days until the day before the test.
library;

import 'leitner.dart';
import 'match.dart';
import 'session.dart';

class TestPlan {
  const TestPlan({required this.date, required this.units});

  static TestPlan? fromJson(Object? j) {
    if (j is! Map) return null;
    return TestPlan(
      date: j['date'] as String,
      units: [for (final u in j['units'] as List) u as String],
    );
  }

  /// Local calendar date of the test, YYYY-MM-DD.
  final String date;
  final List<String> units;

  Map<String, Object> toJson() => {'date': date, 'units': units};
}

class PlanStatus {
  const PlanStatus({
    required this.daysLeft,
    required this.cards,
    required this.secure,
    required this.needed,
    required this.goalToday,
    required this.doneToday,
  });

  /// Calendar days until the test: 1 = tomorrow, 0 = today, negative = over.
  final int daysLeft;
  final int cards;
  final int secure;

  /// Right answers still needed in total.
  final int needed;

  /// Right answers to give today, judged from the state at the start of the day.
  final int goalToday;

  /// Right answers given today on cards of the plan.
  final int doneToday;

  Map<String, int> toJson() => {
    'daysLeft': daysLeft,
    'cards': cards,
    'secure': secure,
    'needed': needed,
    'goalToday': goalToday,
    'doneToday': doneToday,
  };
}

/// Right answers a card still needs to become secure.
int neededFor(CardState? state) {
  final box = state?.box ?? 1;
  return secureBox - box > 0 ? secureBox - box : 0;
}

/// Calendar day number of a YYYY-MM-DD date, comparable with dayNumber().
int dateDay(String date) {
  final p = date.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]).millisecondsSinceEpoch ~/ dayMs;
}

/// Local calendar date (YYYY-MM-DD) of a timestamp.
String localDate(int ms, int utcOffsetMinutes) => isoDay(dayNumber(ms, utcOffsetMinutes));

/// YYYY-MM-DD of a day number.
String isoDay(int day) => DateTime.fromMillisecondsSinceEpoch(
  day * dayMs,
  isUtc: true,
).toIso8601String().substring(0, 10);

List<String> planCards(
  TestPlan plan, {
  required String profileId,
  required List<EntryRef> entries,
  required List<Direction> directions,
}) {
  final units = plan.units.toSet();
  return [
    for (final e in entries)
      if (units.contains(e.unitId))
        for (final d in directions) cardKey(profileId, e.id, d),
  ];
}

PlanStatus planStatus(
  TestPlan plan, {
  required String profileId,
  required List<EntryRef> entries,
  required List<Direction> directions,
  required Map<String, CardState> states,

  /// Answer events of the profile (only today's matter here).
  required Iterable<AnswerEvent> events,
  required int now,
  required LeitnerConfig config,
}) {
  final today = dayNumber(now, config.utcOffsetMinutes);
  final daysLeft = dateDay(plan.date) - today;
  final keys = planCards(plan, profileId: profileId, entries: entries, directions: directions);
  final inPlan = keys.toSet();

  var secure = 0;
  var needed = 0;
  for (final key in keys) {
    final n = neededFor(states[key]);
    needed += n;
    if (n == 0) secure++;
  }

  var doneToday = 0;
  for (final e in events) {
    if (!e.correct || dayNumber(effectiveTime(e), config.utcOffsetMinutes) != today) continue;
    if (inPlan.contains(cardKey(e.profileId, e.entryId, e.direction))) doneToday++;
  }

  // Learning days: today up to the day before the test (on the test day itself: today).
  final days = daysLeft > 1 ? daysLeft : 1;
  // Each right answer today removed (at most) one needed answer, so the need at the
  // start of the day is about needed + doneToday; the goal stays fixed during the day.
  final goalToday = daysLeft < 0 ? 0 : ((needed + doneToday) / days).ceil();
  return PlanStatus(
    daysLeft: daysLeft,
    cards: keys.length,
    secure: secure,
    needed: needed,
    goalToday: goalToday,
    doneToday: doneToday,
  );
}
