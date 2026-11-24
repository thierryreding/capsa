/// Multiple choice (F5): the correct solution plus distractors from other entries.
/// Pure functions; randomness is injected. A port of web/src/lib/learning/choice.ts.
///
/// Distractors should be plausible, or the answer is guessed from its shape: they come
/// preferably from the same word class and the same unit, then from nearby units.
/// An entry that shares a meaning (or form) with the correct one is never offered,
/// so there is always exactly one right option.
library;

import 'cards.dart';
import 'match.dart';
import 'profile.dart';
import 'session.dart';

enum WordClass { noun, verb, adverb, preposition, conjunction, pronoun, other }

const options = 4;

final _noun = RegExp(r'(^|\s)[mfn]\.(\s|$)|\bPl\.');
final _verbMeaning = RegExp(r'^(er/sie/es|il/elle) ');

/// Word class from `pos`, or guessed from the book's info column (German
/// abbreviations) and the translation. Unknown cases are 'other'.
WordClass wordClass(Entry entry) {
  final pos = entry.pos;
  if (pos != null) {
    return WordClass.values.firstWhere(
      (c) => c.name == pos && c != WordClass.other,
      orElse: () => WordClass.other,
    );
  }
  final info = entry.info ?? '';
  if (_noun.hasMatch(info)) return WordClass.noun;
  if (info.contains('Präp')) return WordClass.preposition;
  if (info.contains('Konj')) return WordClass.conjunction;
  if (info.contains('Pron')) return WordClass.pronoun;
  if (info.contains('Adv')) return WordClass.adverb;
  if (infoForms(info: entry.info, pos: entry.pos).isNotEmpty) return WordClass.verb;
  if (entry.tr.values.expand((m) => m).any(_verbMeaning.hasMatch)) return WordClass.verb;
  return WordClass.other;
}

/// Normalised meanings or forms that would make an entry a second right answer.
Set<String> _answers(Entry entry, Direction direction, String lang) {
  final raw = direction == Direction.srcToTr
      ? (entry.tr[lang] ?? const <String>[])
      : [entry.lemma, ...infoForms(info: entry.info, pos: entry.pos)];
  return {for (final x in raw) normalize(x, true).trim()};
}

class Choice {
  const Choice(this.text, this.correct);

  final String text;
  final bool correct;

  @override
  bool operator ==(Object other) =>
      other is Choice && other.text == text && other.correct == correct;

  @override
  int get hashCode => Object.hash(text, correct);

  @override
  String toString() => 'Choice($text, $correct)';
}

/// Options for one card: the correct solution and up to count-1 distractors, shuffled.
/// Only active entries that can be asked in `lang` are used as distractors.
List<Choice> choicesFor(
  ProfileIndex index,
  String entryId,
  Direction direction,
  String lang, {
  Random01 random = defaultRandom,
  int count = options,
}) {
  final entry = index.entries[entryId]!;
  int unitNumber(String id) => index.unitOf[id]?.number ?? 0;
  final correctText = solution(entry, direction, lang);
  final own = _answers(entry, direction, lang);
  final cls = wordClass(entry);
  final unit = unitNumber(entryId);

  final seen = {normalize(correctText, true)};
  final candidates = [
    for (final r in index.refs)
      if (index.entries[r.id]! case final e
          when e.id != entryId &&
              (e.tr[lang]?.length ?? 0) > 0 &&
              !_answers(e, direction, lang).any(own.contains))
        (
          text: solution(e, direction, lang),
          // lower is better: same word class first, then closeness of the unit
          rank: (wordClass(e) == cls ? 0 : 1000) + (unitNumber(e.id) - unit).abs(),
          tiebreak: random(),
        ),
  ]..sort((a, b) => a.rank != b.rank ? a.rank - b.rank : a.tiebreak.compareTo(b.tiebreak));

  final distractors = <String>[];
  for (final c in candidates) {
    if (distractors.length >= count - 1) break;
    // identical texts would be two equal buttons
    if (!seen.add(normalize(c.text, true))) continue;
    distractors.add(c.text);
  }
  return shuffled([
    Choice(correctText, true),
    for (final text in distractors) Choice(text, false),
  ], random);
}

/// Deterministic random numbers in [0, 1) for tests (mulberry32, as in the TS version).
Random01 seededRandom(int seed) {
  var a = seed & 0xffffffff;
  // Math.imul in 16-bit halves, so no product exceeds 2^53 when compiled to JavaScript.
  int imul(int x, int y) {
    final xh = (x >> 16) & 0xffff, xl = x & 0xffff, yh = (y >> 16) & 0xffff, yl = y & 0xffff;
    return (xl * yl + (((xh * yl + xl * yh) & 0xffff) << 16)) & 0xffffffff;
  }

  return () {
    a = (a + 0x6d2b79f5) & 0xffffffff;
    var t = a;
    t = imul(t ^ (t >> 15), t | 1);
    t ^= (t + imul(t ^ (t >> 7), t | 61)) & 0xffffffff;
    return ((t ^ (t >> 14)) & 0xffffffff) / 4294967296;
  };
}
