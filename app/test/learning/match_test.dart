import 'package:capsa/learning/match.dart';
import 'package:capsa/learning/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../support.dart';

MatchContext ctx(ProfileDocument doc, Direction direction, String lang) => MatchContext(
  direction: direction,
  lang: lang,
  sourceLang: doc.profile.sourceLang,
  matching: doc.profile.matching,
);

Map<String, MatchEntry> entriesById(ProfileDocument doc) => {
  for (final u in doc.units)
    for (final e in u.entries) e.id: MatchEntry.of(e),
};

void main() {
  final vectors = loadJson('vectors/match.json') as Map;
  final demo = loadProfile(vectors['profile'] as String);
  final demoEntries = entriesById(demo);

  group('shared vectors (vectors/match.json)', () {
    for (final v in (vectors['cases'] as List).cast<Map>()) {
      final direction = Direction.fromWire(v['direction'] as String);
      test('${v['entry']} ${direction.wire}/${v['lang']}: "${v['answer']}" -> ${v['verdict']}', () {
        final entry = demoEntries[v['entry']];
        expect(entry, isNotNull, reason: 'entry ${v['entry']} missing from demo profile');
        final result = checkAnswer(
          entry!,
          v['answer'] as String,
          ctx(demo, direction, v['lang'] as String),
        );
        expect(result.verdict.name, v['verdict'], reason: v['why'] as String?);
      });
    }
  });

  group('normalize', () {
    test('strips combining marks only when asked', () {
      expect(normalize('nāvigō', true), 'navigo');
      expect(normalize('nāvigō', false), 'nāvigō');
    });
    test('recomposes so precomposed and decomposed input compare equal', () {
      expect(normalize(unorm.nfd('été'), false), normalize(unorm.nfc('été'), false));
    });
    test('folds case and ß', () {
      expect(normalize('GROSS Straße', false), 'gross strasse');
    });
  });

  group('acceptedVariants', () {
    test('expands parentheses, slashes, prefixes and optional words', () {
      final got = acceptedVariants(
        'er/sie/es fährt (zur See)',
        'de',
        demo.profile.matching,
      ).toList()..sort();
      final want = [
        'er/sie/es fahrt (zur see)',
        'er/sie/es fahrt zur see',
        'er/sie/es fahrt',
        for (final p in ['er', 'sie', 'es']) ...[
          '$p fahrt (zur see)',
          '$p fahrt zur see',
          '$p fahrt',
        ],
        'fahrt (zur see)',
        'fahrt zur see',
        'fahrt',
      ]..sort();
      expect(got, want);
    });
    test('drops prefixes and articles only at a word boundary', () {
      const cfg = MatchingConfig(
        optionalArticles: {
          'de': ['die'],
          'fr': ["l'"],
        },
        stripPrefixes: {
          'de': ['er/sie/es'],
        },
      );
      expect(acceptedVariants('dieser Wind', 'de', cfg).toList(), ['dieser wind']);
      expect(acceptedVariants('die Insel', 'de', cfg), contains('insel'));
      expect(acceptedVariants("l'île", 'fr', cfg), contains('île'));
      expect(acceptedVariants('er/sie/es segelt', 'de', cfg), contains('segelt'));
    });
    test('still accepts prefixes written with a trailing space', () {
      const cfg = MatchingConfig(
        optionalArticles: {
          'de': ['die '],
        },
      );
      expect(acceptedVariants('die Insel', 'de', cfg), contains('insel'));
      expect(acceptedVariants('dieser Wind', 'de', cfg).toList(), ['dieser wind']);
    });
    test('stays bounded on pathological input', () {
      final many = [for (var i = 0; i < 20; i++) 'a$i/b$i'].join(' ');
      expect(acceptedVariants(many, 'de', const MatchingConfig()).length, lessThanOrEqualTo(256));
    });
  });

  group('infoForms', () {
    final cases = <(String?, String?, List<String>)>[
      ('nāvigō', null, ['nāvigō']),
      ('ferō, fers, fert', null, ['ferō', 'fers', 'fert']),
      ('m.', null, []),
      ('tempestātem f.', null, []),
      ('Präp. + Akk.', null, []),
      ('Adv.', null, []),
      (null, null, []),
      ('nāvigō', 'noun', []),
      ('dō, dedī', 'verb', ['dō', 'dedī']),
    ];
    for (final (info, pos, forms) in cases) {
      test('$info/$pos -> $forms', () => expect(infoForms(info: info, pos: pos), forms));
    }
  });

  group('levenshtein', () {
    for (final (a, b, d) in [
      ('', '', 0),
      ('abc', '', 3),
      ('kitten', 'sitting', 3),
      ('seemann', 'seeman', 1),
      ('ab', 'ba', 2),
    ]) {
      test('$a / $b = $d', () => expect(levenshtein(a, b), d));
    }
  });

  // Property checks against private profiles, if present on this machine.
  // They assert general invariants and never copy profile content into the repository.
  final privatePaths = privateProfilePaths();
  group('private profiles', skip: privatePaths.isEmpty ? 'no private profiles' : null, () {
    for (final path in privatePaths) {
      final doc = loadProfile(path);
      final req = doc.profile.requiredTranslationLang;
      final matching = doc.profile.matching;
      final entries = [
        for (final u in doc.units)
          for (final e in u.entries)
            if (!e.deprecated) e,
      ];
      final toTr = ctx(doc, Direction.srcToTr, req);
      final toSrc = ctx(doc, Direction.trToSrc, req);
      String strip(String s) => unorm.nfd(s).replaceAll(RegExp(r'\p{M}', unicode: true), '');

      test('${doc.profile.id}: every meaning accepts itself, upper-cased and unaccented', () {
        final failures = <String>[];
        for (final e in entries) {
          for (final m in e.tr[req] ?? const <String>[]) {
            for (final answer in [m, m.toUpperCase(), matching.ignoreDiacritics ? strip(m) : m]) {
              if (checkAnswer(MatchEntry.of(e), answer, toTr).verdict != Verdict.correct) {
                failures.add(e.id);
              }
            }
          }
        }
        expect(failures, isEmpty);
      });

      test('${doc.profile.id}: every meaning is accepted without its prefix', () {
        final failures = <String>[];
        for (final e in entries) {
          for (final m in e.tr[req] ?? const <String>[]) {
            for (final p in matching.stripPrefixes[req] ?? const <String>[]) {
              if (m.startsWith(p) &&
                  checkAnswer(MatchEntry.of(e), m.substring(p.length), toTr).verdict !=
                      Verdict.correct) {
                failures.add(e.id);
              }
            }
          }
        }
        expect(failures, isEmpty);
      });

      test(
        '${doc.profile.id}: every lemma and info form is accepted, with and without macrons',
        () {
          final failures = <String>[];
          for (final e in entries) {
            for (final form in [e.lemma, ...infoForms(info: e.info, pos: e.pos)]) {
              for (final answer in [form, strip(form)]) {
                if (checkAnswer(MatchEntry.of(e), answer, toSrc).verdict != Verdict.correct) {
                  failures.add(e.id);
                }
              }
            }
          }
          expect(failures, isEmpty);
        },
      );

      test('${doc.profile.id}: no expected string expands to nothing', () {
        final empty = [
          for (final e in entries)
            if ((e.tr[req] ?? const <String>[]).any(
              (m) => acceptedVariants(m, req, matching).isEmpty,
            ))
              e.id,
        ];
        expect(empty, isEmpty);
      });
    }
  });
}
