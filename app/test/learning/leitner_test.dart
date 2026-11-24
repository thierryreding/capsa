import 'dart:typed_data';

import 'package:capsa/learning/leitner.dart';
import 'package:capsa/learning/match.dart';
import 'package:capsa/learning/uuid.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  final vectors = loadJson('vectors/leitner.json') as Map;
  final c = vectors['config'] as Map;
  final config = LeitnerConfig(
    intervalsDays: (c['intervalsDays'] as List).cast<int>(),
    utcOffsetMinutes: c['utcOffsetMinutes'] as int,
  );

  group('shared vectors (vectors/leitner.json)', () {
    for (final s in (vectors['scenarios'] as List).cast<Map>()) {
      test(s['name'] as String, () {
        final events = [
          for (final e in s['events'] as List) AnswerEvent.fromJson((e as Map).cast()),
        ];
        final states = computeStates(events, config);
        expect({for (final e in states.entries) e.key: e.value.toJson()}, s['states']);
        for (final check in (s['checks'] as List).cast<Map>()) {
          final due = [
            for (final e in states.entries)
              if (isDue(e.value, check['now'] as int, config)) e.key,
          ]..sort();
          expect(due, check['due'], reason: check['why'] as String? ?? '${check['now']}');
        }
      });
    }
  });

  group('leitner', () {
    const config = LeitnerConfig(utcOffsetMinutes: 0);

    test('new cards are neither due nor mistakes', () {
      expect(isDue(null, DateTime.now().millisecondsSinceEpoch, config), isFalse);
      expect(isMistake(null), isFalse);
    });

    test('configurable number of boxes', () {
      const three = LeitnerConfig(intervalsDays: [0, 2, 5], utcOffsetMinutes: 0);
      var st = applyAnswer(null, true, 0, three);
      st = applyAnswer(st, true, 1, three);
      st = applyAnswer(st, true, 2, three);
      expect(st.box, 3);
    });

    test('mistake is a card whose last answer was wrong', () {
      final wrong = applyAnswer(null, false, 0, config);
      expect(isMistake(wrong), isTrue);
      expect(isMistake(applyAnswer(wrong, true, 1, config)), isFalse);
    });

    test('effective time ignores received_at for unsynced events', () {
      const e = AnswerEvent(
        id: 'x',
        profileId: 'p',
        entryId: 'e',
        direction: Direction.srcToTr,
        correct: true,
        ts: 5,
      );
      expect(effectiveTime(e), 5);
    });

    test('cardKey', () => expect(cardKey('p', 'e', Direction.trToSrc), 'p|e|tr_to_src'));

    test('day numbers before 1970 round down', () => expect(dayNumber(-1, 0), -1));
  });

  group('uuidv7', () {
    test('encodes time, version and variant', () {
      final id = uuidv7(0x0189abcdef01, (n) => Uint8List(n)..fillRange(0, n, 0xff));
      expect(id, '0189abcd-ef01-7fff-bfff-ffffffffffff');
    });
    test('sorts by time', () => expect(uuidv7(1000).compareTo(uuidv7(2000)), lessThan(0)));
    test('is random within the same millisecond', () => expect(uuidv7(5), isNot(uuidv7(5))));
  });
}
