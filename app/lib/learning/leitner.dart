/// Leitner boxes (SPEC 7). Pure functions, no I/O.
///
/// A port of web/src/lib/learning/leitner.ts; both must pass vectors/leitner.json.
///
/// The learning state is derived deterministically from answer events, ordered by
/// (effective time, id), so every device computes the same state from the same events.
/// State is kept per card: (profile, entry, direction).
library;

import 'match.dart';

class LeitnerConfig {
  const LeitnerConfig({this.intervalsDays = defaultIntervalsDays, required this.utcOffsetMinutes});

  /// The device's settings now: default intervals and the local UTC offset.
  factory LeitnerConfig.local([DateTime? now]) =>
      LeitnerConfig(utcOffsetMinutes: (now ?? DateTime.now()).timeZoneOffset.inMinutes);

  /// Interval per box in calendar days; index 0 is box 1.
  final List<int> intervalsDays;

  /// Offset of local time from UTC in minutes (e.g. 60 for CET), for calendar days.
  final int utcOffsetMinutes;
}

const defaultIntervalsDays = [0, 1, 3, 7, 21];

/// A client clock more than this far ahead of the server is not trusted (SPEC 6).
const maxClockAheadMs = 24 * 60 * 60 * 1000;

const dayMs = 24 * 60 * 60 * 1000;

class AnswerEvent {
  const AnswerEvent({
    required this.id,
    required this.profileId,
    required this.entryId,
    required this.direction,
    required this.correct,
    required this.ts,
    this.receivedAt,
  });

  /// The shape used in vectors/*.json.
  factory AnswerEvent.fromJson(Map<String, Object?> j) => AnswerEvent(
    id: j['id'] as String,
    profileId: j['profile_id'] as String,
    entryId: j['entry_id'] as String,
    direction: Direction.fromWire(j['direction'] as String),
    correct: j['correct'] as bool,
    ts: (j['ts'] as num).toInt(),
    receivedAt: (j['received_at'] as num?)?.toInt(),
  );

  final String id;
  final String profileId;
  final String entryId;
  final Direction direction;
  final bool correct;

  /// Client time of the answer (ms since epoch).
  final int ts;

  /// Server receive time (ms since epoch); null while not yet synced.
  final int? receivedAt;
}

class CardState {
  const CardState({
    required this.box,
    required this.lastAt,
    required this.lastCorrect,
    required this.correctCount,
    required this.wrongCount,
  });

  final int box;

  /// Effective time of the last answer (ms since epoch).
  final int lastAt;
  final bool lastCorrect;
  final int correctCount;
  final int wrongCount;

  Map<String, Object> toJson() => {
    'box': box,
    'lastAt': lastAt,
    'lastCorrect': lastCorrect,
    'correctCount': correctCount,
    'wrongCount': wrongCount,
  };

  @override
  bool operator ==(Object other) =>
      other is CardState &&
      other.box == box &&
      other.lastAt == lastAt &&
      other.lastCorrect == lastCorrect &&
      other.correctCount == correctCount &&
      other.wrongCount == wrongCount;

  @override
  int get hashCode => Object.hash(box, lastAt, lastCorrect, correctCount, wrongCount);

  @override
  String toString() => 'CardState${toJson()}';
}

String cardKey(String profileId, String entryId, Direction direction) =>
    '$profileId|$entryId|${direction.wire}';

/// The time an event counts at: `ts`, unless it lies clearly after its arrival.
int effectiveTime(AnswerEvent e) {
  final r = e.receivedAt;
  if (r != null && e.ts > r + maxClockAheadMs) return r;
  return e.ts;
}

int compareEvents(AnswerEvent a, AnswerEvent b) {
  final d = effectiveTime(a) - effectiveTime(b);
  if (d != 0) return d.sign;
  return a.id.compareTo(b.id);
}

CardState applyAnswer(CardState? state, bool correct, int at, LeitnerConfig config) {
  final boxes = config.intervalsDays.length;
  final box = state?.box ?? 1;
  return CardState(
    box: correct ? (box + 1 > boxes ? boxes : box + 1) : 1,
    lastAt: at,
    lastCorrect: correct,
    correctCount: (state?.correctCount ?? 0) + (correct ? 1 : 0),
    wrongCount: (state?.wrongCount ?? 0) + (correct ? 0 : 1),
  );
}

/// States of all cards that have events, keyed by cardKey().
Map<String, CardState> computeStates(Iterable<AnswerEvent> events, LeitnerConfig config) {
  final sorted = events.toList()..sort(compareEvents);
  final seen = <String>{};
  final states = <String, CardState>{};
  for (final e in sorted) {
    if (!seen.add(e.id)) continue; // the same event from two sources counts once
    final key = cardKey(e.profileId, e.entryId, e.direction);
    states[key] = applyAnswer(states[key], e.correct, effectiveTime(e), config);
  }
  return states;
}

/// Local calendar day number of a timestamp.
int dayNumber(int ms, int utcOffsetMinutes) => ((ms + utcOffsetMinutes * 60000) / dayMs).floor();

/// Calendar day on which the card becomes due again.
int dueDay(CardState state, LeitnerConfig config) {
  final i = state.box - 1;
  final interval = i >= 0 && i < config.intervalsDays.length ? config.intervalsDays[i] : 0;
  return dayNumber(state.lastAt, config.utcOffsetMinutes) + interval;
}

/// New cards (no state) are not "due": they are offered separately.
bool isDue(CardState? state, int now, LeitnerConfig config) {
  if (state == null) return false;
  return dayNumber(now, config.utcOffsetMinutes) >= dueDay(state, config);
}

/// A card whose last answer was wrong.
bool isMistake(CardState? state) => state != null && !state.lastCorrect;
