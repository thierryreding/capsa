import 'package:capsa/learning/cards.dart';
import 'package:capsa/learning/choice.dart';
import 'package:capsa/learning/match.dart';
import 'package:capsa/learning/profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  final demo = ProfileIndex(loadProfile(demoProfile));
  Entry entry(String id) => demo.entries[id]!;

  group('wordClass', () {
    for (final (id, cls) in [
      ('u1-nauta', WordClass.noun), // "m."
      ('u2-tempestas', WordClass.noun), // "tempestātem f."
      ('u2-navigare', WordClass.verb), // info form
      ('u1-navigat', WordClass.verb), // er/sie/es ...
      ('u1-procul', WordClass.adverb),
      ('u1-trans', WordClass.preposition),
      ('u2-aut', WordClass.conjunction),
      ('u1-is-ea-id', WordClass.pronoun),
      ('u1-heus', WordClass.other),
    ]) {
      test('$id is a ${cls.name}', () => expect(wordClass(entry(id)), cls));
    }
    test('an explicit pos wins', () {
      expect(wordClass(entry('u1-nauta').copyWith(pos: 'verb')), WordClass.verb);
      expect(wordClass(entry('u1-nauta').copyWith(pos: 'numeral')), WordClass.other);
      expect(wordClass(entry('u1-nauta').copyWith(pos: 'other')), WordClass.other);
    });
  });

  group('choicesFor', () {
    test('one correct option and three distinct distractors, shuffled', () {
      final options = choicesFor(
        demo,
        'u1-nauta',
        Direction.srcToTr,
        'de',
        random: seededRandom(1),
      );
      expect(options, hasLength(4));
      expect(options.where((o) => o.correct), [const Choice('der Seemann, der Matrose', true)]);
      expect(options.map((o) => o.text).toSet(), hasLength(4));
    });
    test('prefers the same word class and unit', () {
      // u1-nauta is a noun in unit 1; the other unit-1 nouns are insula and ventus.
      final distractors = [
        for (final o in choicesFor(
          demo,
          'u1-nauta',
          Direction.srcToTr,
          'de',
          random: seededRandom(2),
        ))
          if (!o.correct) o.text,
      ];
      expect(distractors, containsAll(['die Insel', 'der Wind']));
    });
    test('the reverse direction offers lemmas', () {
      final options = choicesFor(
        demo,
        'u2-navigare',
        Direction.trToSrc,
        'de',
        random: seededRandom(3),
      );
      expect(options.firstWhere((o) => o.correct).text, 'nāvigāre');
      expect(options.every((o) => !o.text.contains(',')), isTrue);
    });
    test('never offers an entry that shares a meaning with the right one', () {
      // A made-up second entry that also means "der Wind" must not appear for ventus.
      final json = loadProfileJson(demoProfile);
      ((json['units'] as List)[1]['entries'] as List).add({
        'id': 'u2-aura',
        'lemma': 'aura',
        'info': 'f.',
        'tr': {
          'de': ['der Wind', 'der Hauch'],
        },
      });
      final index = ProfileIndex(ProfileDocument.fromJson(json));
      for (var seed = 0; seed < 30; seed++) {
        final options = choicesFor(
          index,
          'u1-ventus',
          Direction.srcToTr,
          'de',
          random: seededRandom(seed),
        );
        expect(options.map((o) => o.text), isNot(contains('der Wind, der Hauch')));
      }
    });
    test('skips entries without a translation in the language', () {
      for (var seed = 0; seed < 20; seed++) {
        final options = choicesFor(
          demo,
          'u1-nauta',
          Direction.srcToTr,
          'fr',
          random: seededRandom(seed),
        );
        expect(options.every((o) => o.text.isNotEmpty), isTrue);
      }
    });
    test('works with tiny profiles', () {
      final json = loadProfileJson(demoProfile);
      final first = (json['units'] as List)[0] as Map;
      first['entries'] = (first['entries'] as List).sublist(0, 2);
      json['units'] = [first];
      final options = choicesFor(
        ProfileIndex(ProfileDocument.fromJson(json)),
        'u1-nauta',
        Direction.srcToTr,
        'de',
        random: seededRandom(4),
      );
      expect(options, hasLength(2));
    });
    test('is deterministic for a given random source', () {
      final a = choicesFor(demo, 'u1-nauta', Direction.srcToTr, 'de', random: seededRandom(9));
      final b = choicesFor(demo, 'u1-nauta', Direction.srcToTr, 'de', random: seededRandom(9));
      expect(a, b);
    });
  });

  group('seededRandom', () {
    test('matches mulberry32 from the TS version', () {
      // First values of seededRandom(1) in web/src/lib/learning/choice.ts.
      final r = seededRandom(1);
      expect([r(), r(), r()], [0.6270739405881613, 0.002735721180215478, 0.5274470399599522]);
      final q = seededRandom(4294967295);
      expect([q(), q()], [0.8964226141106337, 0.189478256739676]);
    });
  });

  // Property check on private profiles, if present: every entry gets exactly one right
  // option among distinct texts (content is not copied into the repository).
  final privatePaths = privateProfilePaths();
  group('private profiles', skip: privatePaths.isEmpty ? 'no private profiles' : null, () {
    for (final path in privatePaths) {
      test('${path.split('/').last}: exactly one right option for every card', () {
        final index = ProfileIndex(loadProfile(path));
        final lang = index.doc.profile.requiredTranslationLang;
        final problems = <String>[];
        for (final ref in index.refs) {
          for (final direction in Direction.values) {
            final options = choicesFor(index, ref.id, direction, lang, random: seededRandom(7));
            final texts = options.map((o) => o.text).toList();
            if (options.where((o) => o.correct).length != 1) problems.add('${ref.id}: correct');
            if (texts.toSet().length != texts.length) problems.add('${ref.id}: duplicate');
            if (options.length < 4) problems.add('${ref.id}: only ${options.length}');
          }
        }
        expect(problems, isEmpty);
      });
    }
  });
}
