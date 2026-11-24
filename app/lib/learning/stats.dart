/// Learning statistics for one profile (F9). Pure functions.
///
/// A port of web/src/lib/learning/stats.ts, which mirrors api/src/capsa/progress.py;
/// all three must pass vectors/stats.json, so the child's view (computed here, offline)
/// and the parent's view (from the server) agree. The result has the shape of the
/// API's LearningStats, so the same widget shows both.
library;

import 'leitner.dart';
import 'match.dart';
import 'plan.dart' show isoDay;
import 'profile.dart';
import 'session.dart';

const historyDays = 14;
const recentDays = 30;
const hardestCount = 10;

class DayCount {
  DayCount(this.date, [this.correct = 0, this.wrong = 0]);

  factory DayCount.fromJson(Map<String, Object?> j) =>
      DayCount(j['date'] as String, (j['correct'] as num).toInt(), (j['wrong'] as num).toInt());

  final String date;
  int correct;
  int wrong;

  Map<String, Object> toJson() => {'date': date, 'correct': correct, 'wrong': wrong};
}

class UnitStats {
  UnitStats({
    required this.unitId,
    required this.number,
    required this.title,
    required this.cards,
    required this.boxes,
    this.fresh = 0,
    this.secure = 0,
    this.mistakes = 0,
    this.answersRecent = 0,
    this.correctRecent = 0,
  });

  factory UnitStats.fromJson(Map<String, Object?> j) => UnitStats(
    unitId: j['unit_id'] as String,
    number: (j['number'] as num).toInt(),
    title: j['title'] as String,
    cards: (j['cards'] as num).toInt(),
    fresh: (j['fresh'] as num).toInt(),
    secure: (j['secure'] as num).toInt(),
    mistakes: (j['mistakes'] as num).toInt(),
    boxes: [for (final b in j['boxes'] as List) (b as num).toInt()],
    answersRecent: (j['answers_recent'] as num).toInt(),
    correctRecent: (j['correct_recent'] as num).toInt(),
  );

  final String unitId;
  final int number;
  final String title;
  final int cards;
  int fresh;
  int secure;
  int mistakes;
  final List<int> boxes;
  int answersRecent;
  int correctRecent;

  Map<String, Object> toJson() => {
    'unit_id': unitId,
    'number': number,
    'title': title,
    'cards': cards,
    'fresh': fresh,
    'secure': secure,
    'mistakes': mistakes,
    'boxes': boxes,
    'answers_recent': answersRecent,
    'correct_recent': correctRecent,
  };
}

class HardEntry {
  const HardEntry({
    required this.entryId,
    required this.lemma,
    required this.meaning,
    required this.wrong,
    required this.correct,
    required this.lastCorrect,
  });

  factory HardEntry.fromJson(Map<String, Object?> j) => HardEntry(
    entryId: j['entry_id'] as String,
    lemma: j['lemma'] as String,
    meaning: j['meaning'] as String,
    wrong: (j['wrong'] as num).toInt(),
    correct: (j['correct'] as num).toInt(),
    lastCorrect: j['last_correct'] as bool,
  );

  final String entryId;
  final String lemma;
  final String meaning;
  final int wrong;
  final int correct;
  final bool lastCorrect;

  Map<String, Object> toJson() => {
    'entry_id': entryId,
    'lemma': lemma,
    'meaning': meaning,
    'wrong': wrong,
    'correct': correct,
    'last_correct': lastCorrect,
  };
}

class LearningStats {
  const LearningStats({
    required this.profileId,
    required this.directions,
    required this.totalAnswers,
    required this.lastAnswerAt,
    required this.days,
    required this.units,
    required this.hardest,
  });

  /// The API's LearningStats (GET /admin/users/{id}/progress/{profile}).
  factory LearningStats.fromJson(Map<String, Object?> j) => LearningStats(
    profileId: j['profile_id'] as String,
    directions: [for (final d in j['directions'] as List) Direction.fromWire(d as String)],
    totalAnswers: (j['total_answers'] as num).toInt(),
    lastAnswerAt: (j['last_answer_at'] as num?)?.toInt(),
    days: [for (final d in j['days'] as List) DayCount.fromJson((d as Map).cast())],
    units: [for (final u in j['units'] as List) UnitStats.fromJson((u as Map).cast())],
    hardest: [for (final h in j['hardest'] as List) HardEntry.fromJson((h as Map).cast())],
  );

  final String profileId;
  final List<Direction> directions;
  final int totalAnswers;
  final int? lastAnswerAt;
  final List<DayCount> days;
  final List<UnitStats> units;
  final List<HardEntry> hardest;

  Map<String, Object?> toJson() => {
    'profile_id': profileId,
    'directions': [for (final d in directions) d.wire],
    'total_answers': totalAnswers,
    'last_answer_at': lastAnswerAt,
    'days': [for (final d in days) d.toJson()],
    'units': [for (final u in units) u.toJson()],
    'hardest': [for (final h in hardest) h.toJson()],
  };
}

LearningStats learningStats(
  ProfileDocument doc,
  Iterable<AnswerEvent> events,
  int now,
  LeitnerConfig config,
) {
  final profile = doc.profile;
  final lang = profile.requiredTranslationLang;
  final order = <String, int>{};
  final unitOf = <String, String>{};
  final entryById = <String, Entry>{};
  for (final unit in doc.units) {
    for (final entry in unit.entries) {
      if (entry.deprecated) continue;
      order[entry.id] = order.length;
      unitOf[entry.id] = unit.id;
      entryById[entry.id] = entry;
    }
  }

  final unique = <String, AnswerEvent>{};
  for (final e in events) {
    if (e.profileId == profile.id && order.containsKey(e.entryId)) {
      unique.putIfAbsent(e.id, () => e);
    }
  }
  final mine = unique.values.toList()..sort(compareEvents);

  final practised = {for (final e in mine) e.direction}.toList()
    ..sort((a, b) => a.wire.compareTo(b.wire));
  final directions = practised.isNotEmpty ? practised : [Direction.srcToTr];
  final states = computeStates(mine, config);
  final today = dayNumber(now, config.utcOffsetMinutes);
  int dayOf(AnswerEvent e) => dayNumber(effectiveTime(e), config.utcOffsetMinutes);

  final units = [
    for (final unit in doc.units)
      () {
        final entries = unit.entries.where((e) => !e.deprecated).toList();
        final row = UnitStats(
          unitId: unit.id,
          number: unit.number,
          title: unit.title,
          cards: entries.length * directions.length,
          boxes: List.filled(config.intervalsDays.length, 0),
        );
        for (final entry in entries) {
          for (final direction in directions) {
            final state = states[cardKey(profile.id, entry.id, direction)];
            if (state == null) {
              row.fresh++;
              continue;
            }
            row.boxes[state.box - 1]++;
            if (state.box >= secureBox) row.secure++;
            if (isMistake(state)) row.mistakes++;
          }
        }
        return row;
      }(),
  ];
  final byUnit = {for (final u in units) u.unitId: u};
  for (final e in mine) {
    if (today - dayOf(e) < recentDays) {
      final u = byUnit[unitOf[e.entryId]]!;
      u.answersRecent++;
      if (e.correct) u.correctRecent++;
    }
  }

  final first = today - historyDays + 1;
  final days = [for (var i = 0; i < historyDays; i++) DayCount(isoDay(first + i))];
  for (final e in mine) {
    final i = dayOf(e) - first;
    if (i >= 0 && i < historyDays) {
      if (e.correct) {
        days[i].correct++;
      } else {
        days[i].wrong++;
      }
    }
  }

  final perEntry = <String, ({int wrong, int correct, bool last})>{};
  for (final e in mine) {
    final s = perEntry[e.entryId] ?? (wrong: 0, correct: 0, last: false);
    perEntry[e.entryId] = (
      wrong: s.wrong + (e.correct ? 0 : 1),
      correct: s.correct + (e.correct ? 1 : 0),
      last: e.correct,
    );
  }
  final hardest = perEntry.entries.where((x) => x.value.wrong > 0).toList()
    ..sort((x, y) {
      final a = x.value, b = y.value;
      if (a.wrong != b.wrong) return b.wrong - a.wrong;
      // higher error rate first, compared exactly
      final ratio = b.wrong * (a.wrong + a.correct) - a.wrong * (b.wrong + b.correct);
      if (ratio != 0) return ratio;
      return order[x.key]! - order[y.key]!;
    });

  return LearningStats(
    profileId: profile.id,
    directions: directions,
    totalAnswers: mine.length,
    lastAnswerAt: mine.isEmpty ? null : effectiveTime(mine.last),
    days: days,
    units: units,
    hardest: [
      for (final MapEntry(key: id, value: s) in hardest.take(hardestCount))
        HardEntry(
          entryId: id,
          lemma: entryById[id]!.lemma,
          meaning: entryById[id]!.tr[lang]?.firstOrNull ?? '',
          wrong: s.wrong,
          correct: s.correct,
          lastCorrect: s.last,
        ),
    ],
  );
}
