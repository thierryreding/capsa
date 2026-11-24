import 'package:capsa/learning/cards.dart';
import 'package:capsa/learning/leitner.dart';
import 'package:capsa/learning/match.dart';
import 'package:capsa/learning/profile.dart';
import 'package:capsa/learning/stats.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  group('cards', () {
    final index = ProfileIndex(loadProfile(demoProfile));
    final nauta = index.entries['u1-nauta']!;

    test('indexes entries in book order and skips deprecated ones in refs', () {
      expect((index.refs.first.id, index.refs.first.unitId), ('u1-nauta', 'u1'));
      expect(index.unitOf['u2-dare']?.id, 'u2');
      final json = loadProfileJson(demoProfile);
      ((json['units'] as List)[0]['entries'] as List)[0]['deprecated'] = true;
      final i2 = ProfileIndex(ProfileDocument.fromJson(json));
      expect(i2.refs.any((r) => r.id == 'u1-nauta'), isFalse);
      expect(i2.entries.containsKey('u1-nauta'), isTrue); // old events still resolve
    });
    test('prompt and solution per direction', () {
      expect(prompt(nauta, Direction.srcToTr, 'de'), 'nauta');
      expect(solution(nauta, Direction.srcToTr, 'de'), 'der Seemann, der Matrose');
      expect(prompt(nauta, Direction.trToSrc, 'fr'), 'le marin');
      expect(solution(nauta, Direction.trToSrc, 'fr'), 'nauta');
      expect(meanings(nauta, 'es'), '');
    });
    test('askable only with a translation in the language', () {
      expect(askable(index.entries['u1-spectat']!, 'fr'), isFalse);
      expect(askable(index.entries['u1-spectat']!, 'de'), isTrue);
    });
    test('extras behind the info icon', () {
      expect(hasExtras(nauta), isTrue); // a note
      expect(hasExtras(index.entries['u1-procul']!), isFalse);
    });
  });

  group('learningStats', () {
    final vectors = loadJson('vectors/stats.json') as Map;
    final demo = loadProfile(vectors['profile'] as String);
    final c = vectors['config'] as Map;
    final config = LeitnerConfig(
      intervalsDays: (c['intervalsDays'] as List).cast<int>(),
      utcOffsetMinutes: c['utcOffsetMinutes'] as int,
    );
    final events = [
      for (final e in vectors['events'] as List) AnswerEvent.fromJson((e as Map).cast()),
    ];
    final now = vectors['now'] as int;

    test('shared vector (vectors/stats.json), as on the server', () {
      expect(learningStats(demo, events, now, config).toJson(), vectors['expected']);
    });
    test('the API shape round-trips, so server stats show in the same view', () {
      final expected = (vectors['expected'] as Map).cast<String, Object?>();
      expect(LearningStats.fromJson(expected).toJson(), expected);
    });
    test('no events', () {
      final s = learningStats(demo, [], now, config);
      expect(s.totalAnswers, 0);
      expect(s.lastAnswerAt, isNull);
      expect([for (final u in s.units) u.fresh], [10, 9]);
      expect(s.days, hasLength(14));
    });
  });
}
