import 'package:capsa/learning/leitner.dart';
import 'package:capsa/learning/match.dart';
import 'package:capsa/learning/session.dart';
import 'package:flutter_test/flutter_test.dart';

const day = 24 * 60 * 60 * 1000;
const now = 1800000000000;
const config = LeitnerConfig(utcOffsetMinutes: 0);
const entries = [
  EntryRef('a', 'u1'),
  EntryRef('b', 'u1'),
  EntryRef('c', 'u1'),
  EntryRef('d', 'u1'),
  EntryRef('e', 'u1'),
  EntryRef('f', 'u1'),
  EntryRef('x', 'u2'),
  EntryRef('y', 'u2'),
];

/// States built from answers: (entry, correct, daysAgo) in chronological order.
Map<String, CardState> states(List<(String, bool, int)> answers) {
  final m = <String, CardState>{};
  for (final (entry, correct, daysAgo) in answers) {
    final k = cardKey('p', entry, Direction.srcToTr);
    m[k] = applyAnswer(m[k], correct, now - daysAgo * day, config);
  }
  return m;
}

List<Card> select(
  Map<String, CardState> st, {
  Selection selection = Selection.mixed,
  Set<String> units = const {'u1'},
  List<Direction> directions = const [Direction.srcToTr],
  int size = 10,
  Random01? random,
}) => selectCards(
  st,
  profileId: 'p',
  entries: entries,
  units: units,
  directions: directions,
  selection: selection,
  size: size,
  now: now,
  config: config,
  random: random ?? () => 0.999, // keeps order: the Fisher-Yates swap is a no-op
);

List<String> ids(Iterable<Card> cards) => [for (final c in cards) c.entryId];

void main() {
  group('selectCards', () {
    // a: mistake; b: due (box 2, 2 days ago); c: not due (box 2, today); d, e, f: new
    final st = states([('a', false, 1), ('b', true, 2), ('c', true, 0)]);

    test('mixed: mistakes, then due, then new cards', () {
      expect(ids(select(st)), ['a', 'b', 'd', 'e', 'f']);
      expect(ids(select(st, size: 3)), ['a', 'b', 'd']);
    });
    test('due only and mistakes only', () {
      expect(ids(select(st, selection: Selection.due)), ['a', 'b']);
      expect(ids(select(st, selection: Selection.mistakes)), ['a']);
    });
    test('all: every card of the selected units', () {
      expect(ids(select(st, selection: Selection.all))..sort(), ['a', 'b', 'c', 'd', 'e', 'f']);
    });
    test('test: cards not yet secure, mistakes first, then box 2, then new', () {
      final s = states([('a', true, 5), ('a', true, 4), ('b', true, 3), ('c', false, 2)]);
      expect(ids(select(s, selection: Selection.test)), ['c', 'b', 'd', 'e', 'f']);
    });
    test('restricts to the selected units', () {
      expect(ids(select(st, units: {'u2'})), ['x', 'y']);
    });
    test('due cards in lower boxes and older ones first', () {
      final s = states([
        ('a', true, 30), ('a', true, 29), ('a', true, 25), // box 4, last 25 days ago
        ('b', true, 5), // box 2, 5 days ago
        ('c', true, 3), // box 2, 3 days ago
      ]);
      expect(ids(select(s, selection: Selection.due)), ['b', 'c', 'a']);
    });
    test('both directions are separate cards', () {
      final cards = select({}, directions: Direction.values, size: 4);
      expect(
        [for (final c in cards) '${c.entryId}:${c.direction.wire}'],
        ['a:src_to_tr', 'a:tr_to_src', 'b:src_to_tr', 'b:tr_to_src'],
      );
    });
    test('shuffles the selection', () {
      var seed = 1;
      double random() => ((seed = (seed * 16807) % 2147483647) - 1) / 2147483646;
      expect(ids(select(st, random: random))..sort(), ['a', 'b', 'd', 'e', 'f']);
    });
  });

  group('progressByUnit', () {
    test('counts new, due, mistakes and boxes per unit', () {
      final st = states([('a', false, 1), ('b', true, 2), ('c', true, 0), ('x', true, 0)]);
      final p = progressByUnit(
        st,
        profileId: 'p',
        entries: entries,
        units: {'u1', 'u2'},
        directions: [Direction.srcToTr],
        now: now,
        config: config,
      );
      expect(p['u1']!.toJson(), {
        'total': 6,
        'fresh': 3,
        'due': 2,
        'mistakes': 1,
        'boxes': [1, 2, 0, 0, 0],
      });
      expect(p['u2']!.toJson(), {
        'total': 2,
        'fresh': 1,
        'due': 0,
        'mistakes': 0,
        'boxes': [0, 1, 0, 0, 0],
      });
    });
  });

  group('session', () {
    final cards = [
      for (final id in ['a', 'b', 'c', 'd', 'e']) Card(id, Direction.srcToTr),
    ];

    test('runs through the cards', () {
      var s = Session.start(cards.sublist(0, 2));
      expect(s.current?.entryId, 'a');
      s = s.answer(true).answer(true);
      expect(s.isFinished, isTrue);
      expect(s.summary, (cards: 2, firstTry: 2, answers: 2));
    });
    test('repeats a wrong card three cards later', () {
      expect(ids(Session.start(cards).answer(false).queue), ['b', 'c', 'd', 'a', 'e']);
    });
    test('repeats at the end when few cards are left', () {
      expect(ids(Session.start(cards.sublist(0, 2)).answer(false).queue), ['b', 'a']);
    });
    test('repeats a card at most $maxRepeats times', () {
      var s = Session.start(cards.sublist(0, 1));
      for (var i = 0; i < 5 && !s.isFinished; i++) {
        s = s.answer(false);
      }
      expect(s.results.length, 1 + maxRepeats);
      expect(s.isFinished, isTrue);
      expect(s.summary, (cards: 1, firstTry: 0, answers: 3));
    });
  });
}
