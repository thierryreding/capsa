/// Choosing cards for a learning session and running it (SPEC 7, F7). Pure functions.
///
/// A port of web/src/lib/learning/session.ts.
///
/// A card is one entry in one direction. A session has 10 cards by default; the
/// default selection mixes mistakes, due cards and new cards. Within a session a
/// wrongly answered card comes back a few cards later (box 1 = "same session").
library;

import 'dart:math' as math;

import 'leitner.dart';
import 'match.dart';

/// Box from which a card counts as secure for a test (two right answers in a row).
const secureBox = 3;

class Card {
  const Card(this.entryId, this.direction);

  final String entryId;
  final Direction direction;

  String get key => '$entryId|${direction.wire}';

  @override
  bool operator ==(Object other) =>
      other is Card && other.entryId == entryId && other.direction == direction;

  @override
  int get hashCode => Object.hash(entryId, direction);

  @override
  String toString() => 'Card($entryId, ${direction.wire})';
}

class EntryRef {
  const EntryRef(this.id, this.unitId);

  final String id;
  final String unitId;
}

/// mixed: mistakes, then due, then new cards.
/// test: cards not yet secure for a test (box < 3): mistakes, then box 2, then new.
enum Selection { mixed, due, mistakes, all, test }

const defaultSessionSize = 10;

/// Random number in [0, 1); injectable for tests.
typedef Random01 = double Function();

final _rng = math.Random();
double defaultRandom() => _rng.nextDouble();

List<T> shuffled<T>(List<T> items, Random01 random) {
  final a = [...items];
  for (var i = a.length - 1; i > 0; i--) {
    final j = (random() * (i + 1)).floor();
    final t = a[i];
    a[i] = a[j];
    a[j] = t;
  }
  return a;
}

typedef _Candidate = ({Card card, CardState? state, int order});

List<_Candidate> _candidates(
  Map<String, CardState> states,
  String profileId,
  List<EntryRef> entries,
  Set<String> units,
  List<Direction> directions,
) {
  final out = <_Candidate>[];
  var order = 0;
  for (final e in entries) {
    if (!units.contains(e.unitId)) continue;
    for (final direction in directions) {
      out.add((
        card: Card(e.id, direction),
        state: states[cardKey(profileId, e.id, direction)],
        order: order++,
      ));
    }
  }
  return out;
}

int _byOldest(_Candidate a, _Candidate b) => (a.state!.lastAt - b.state!.lastAt).sign;
int _byBoxThenOldest(_Candidate a, _Candidate b) {
  final d = a.state!.box - b.state!.box;
  return d != 0 ? d.sign : _byOldest(a, b);
}

/// Dart's List.sort is not stable; the TS version relies on a stable sort.
List<T> _stableSorted<T extends _Candidate>(Iterable<T> items, int Function(T, T) compare) {
  final list = items.toList();
  list.sort((a, b) {
    final c = compare(a, b);
    return c != 0 ? c : a.order - b.order;
  });
  return list;
}

List<Card> selectCards(
  Map<String, CardState> states, {
  required String profileId,

  /// Active (non-deprecated) entries in book order.
  required List<EntryRef> entries,
  required Set<String> units,
  required List<Direction> directions,
  required Selection selection,
  int size = defaultSessionSize,
  required int now,
  required LeitnerConfig config,
  Random01 random = defaultRandom,
}) {
  final all = _candidates(states, profileId, entries, units, directions);
  final mistakes = _stableSorted(all.where((c) => isMistake(c.state)), _byOldest);
  final due = _stableSorted(
    all.where((c) => !isMistake(c.state) && isDue(c.state, now, config)),
    _byBoxThenOldest,
  );
  final fresh = all.where((c) => c.state == null).toList();

  final List<_Candidate> picked = switch (selection) {
    Selection.mistakes => mistakes,
    Selection.due => [...mistakes.where((c) => isDue(c.state, now, config)), ...due],
    Selection.all => shuffled(all, random),
    Selection.mixed => [...mistakes, ...due, ...fresh],
    Selection.test => [
      ...mistakes,
      ..._stableSorted(
        all.where((c) => c.state != null && !isMistake(c.state) && c.state!.box < secureBox),
        _byOldest,
      ),
      ...fresh,
    ],
  };
  return shuffled([for (final c in picked.take(size)) c.card], random);
}

class Progress {
  Progress({
    required this.total,
    required this.fresh,
    required this.due,
    required this.mistakes,
    required this.boxes,
  });

  int total;
  int fresh;
  int due;
  int mistakes;

  /// Number of cards per box (index 0 = box 1), not counting new cards.
  final List<int> boxes;

  Map<String, Object> toJson() => {
    'total': total,
    'fresh': fresh,
    'due': due,
    'mistakes': mistakes,
    'boxes': boxes,
  };
}

/// Progress per unit for the given directions (F9).
Map<String, Progress> progressByUnit(
  Map<String, CardState> states, {
  required String profileId,
  required List<EntryRef> entries,
  required Set<String> units,
  required List<Direction> directions,
  required int now,
  required LeitnerConfig config,
}) {
  final result = <String, Progress>{};
  final unitOf = {for (final e in entries) e.id: e.unitId};
  for (final c in _candidates(states, profileId, entries, units, directions)) {
    final p = result.putIfAbsent(
      unitOf[c.card.entryId]!,
      () => Progress(
        total: 0,
        fresh: 0,
        due: 0,
        mistakes: 0,
        boxes: List.filled(config.intervalsDays.length, 0),
      ),
    );
    p.total++;
    final s = c.state;
    if (s == null) {
      p.fresh++;
      continue;
    }
    p.boxes[s.box - 1]++;
    if (isMistake(s)) p.mistakes++;
    if (isDue(s, now, config)) p.due++;
  }
  return result;
}

// --- running a session ------------------------------------------------------

/// A wrong card comes back after this many other cards ...
const repeatGap = 3;

/// ... at most this many times per session.
const maxRepeats = 2;

typedef SessionResult = ({Card card, bool correct});

/// An immutable session; answering returns a new one.
class Session {
  const Session._(this.queue, this.results, this.repeats);

  factory Session.start(List<Card> cards) =>
      Session._(List.unmodifiable(cards), const [], const {});

  final List<Card> queue;
  final List<SessionResult> results;
  final Map<String, int> repeats;

  Card? get current => queue.isEmpty ? null : queue.first;
  bool get isFinished => queue.isEmpty;

  Session answer(bool correct) {
    final card = current;
    if (card == null) return this;
    final results = [...this.results, (card: card, correct: correct)];
    final repeats = {...this.repeats};
    final queue = [...this.queue.skip(1)];
    final done = repeats[card.key] ?? 0;
    if (!correct && done < maxRepeats) {
      repeats[card.key] = done + 1;
      queue.insert(math.min(repeatGap, queue.length), card);
    }
    return Session._(
      List.unmodifiable(queue),
      List.unmodifiable(results),
      Map.unmodifiable(repeats),
    );
  }

  /// Distinct cards, and how many were right at their first attempt.
  ({int cards, int firstTry, int answers}) get summary {
    final first = <String, bool>{};
    for (final r in results) {
      first.putIfAbsent(r.card.key, () => r.correct);
    }
    return (
      cards: first.length,
      firstTry: first.values.where((c) => c).length,
      answers: results.length,
    );
  }
}
