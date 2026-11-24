/// Answer checking for typed answers (SPEC section 7). Pure functions, no I/O.
///
/// A port of web/src/lib/learning/match.ts; both must pass vectors/match.json.
///
/// An expected string (a meaning from `tr[lang]`, the lemma, or a verb form from `info`)
/// is expanded into a set of accepted variants:
///   1. normalise (NFD, optional removal of combining marks, lower case, ß -> ss,
///      whitespace and apostrophes unified)
///   2. parenthesised parts are optional:     "schau(t)!"        -> "schaut", "schau"
///   3. slash alternatives within a word:      "er/sie/es segelt" -> "er segelt", ...
///   4. `strip_prefixes`, then `optional_articles` may be left out at the start
///   5. `optional_words` may be left out anywhere: "jdm. etw. geben" -> "geben", ...
///   6. sentence punctuation at either end and ellipses are ignored
/// The answer itself is only normalised (steps 1 and 6).
library;

import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'profile.dart';

enum Verdict { correct, almost, wrong }

/// srcToTr: the source word is shown, the translation is typed. trToSrc: the reverse.
enum Direction {
  srcToTr('src_to_tr'),
  trToSrc('tr_to_src');

  const Direction(this.wire);

  /// The name used by the API, in events and in card keys.
  final String wire;

  static Direction fromWire(String s) => values.firstWhere((d) => d.wire == s);
}

class MatchEntry {
  const MatchEntry({required this.lemma, required this.tr, this.info, this.pos});

  factory MatchEntry.of(Entry e) => MatchEntry(lemma: e.lemma, tr: e.tr, info: e.info, pos: e.pos);

  final String lemma;
  final String? info;
  final String? pos;
  final Map<String, List<String>> tr;
}

class MatchContext {
  const MatchContext({
    required this.direction,
    required this.lang,
    required this.sourceLang,
    required this.matching,
  });

  final Direction direction;

  /// Language of the translation side (typed for srcToTr, shown for trToSrc).
  final String lang;
  final String sourceLang;
  final MatchingConfig matching;
}

class MatchResult {
  const MatchResult(this.verdict, this.expected);

  final Verdict verdict;

  /// The original expected string that matched (or nearly matched); null when wrong.
  final String? expected;
}

/// Minimum length of an expected variant for which a single typo counts as "almost".
const almostMinLength = 6;

// Guard against pathological inputs: each expansion step caps the number of variants.
const _maxVariants = 256;

final _marks = RegExp(r'\p{M}', unicode: true);
final _apostrophes = RegExp('[‘’ʼ`´]');
final _spaces = RegExp(r'\s+');
final _slashSpaces = RegExp(r' ?/ ?');

String normalize(String text, bool ignoreDiacritics) {
  var t = unorm.nfd(text);
  if (ignoreDiacritics) t = t.replaceAll(_marks, '');
  t = t.toLowerCase().replaceAll('ß', 'ss');
  t = unorm.nfc(t);
  t = t.replaceAll(_apostrophes, "'");
  t = t.replaceAll(_spaces, ' ');
  t = t.replaceAll(_slashSpaces, '/');
  return t;
}

final _edgePunctuation = RegExp(r'^[\s!?.,;:¡¿]+|[\s!?.,;:¡¿]+$');
final _ellipsis = RegExp(r'…|\.\.\.');

String _finish(String text) => text
    .replaceAll(_ellipsis, ' ')
    .replaceAll(_spaces, ' ')
    .replaceAll(_edgePunctuation, '')
    .trim();

Set<String> _cap(Iterable<String> items) {
  final out = <String>{};
  for (final item in items) {
    if (out.length >= _maxVariants) break;
    out.add(item);
  }
  return out;
}

Set<String> _flatMapSet(Set<String> input, List<String> Function(String) fn) =>
    _cap(input.expand(fn));

final _paren = RegExp(r'\(([^()]*)\)');

/// Every parenthesised group may be kept (without the brackets) or dropped.
List<String> _parenVariants(String s) {
  final m = _paren.firstMatch(s);
  if (m == null) return [s];
  final before = s.substring(0, m.start);
  final after = s.substring(m.end);
  return [..._parenVariants(before + m[1]! + after), ..._parenVariants(before + after)];
}

List<String> _cartesian(List<List<String>> options) {
  var acc = [''];
  for (final opts in options) {
    final next = <String>[];
    // Like the TS version, this only leaves the inner loop; _cap trims the rest.
    for (final prefix in acc) {
      for (final o in opts) {
        next.add(prefix.isNotEmpty ? '$prefix $o' : o);
        if (next.length >= _maxVariants) break;
      }
    }
    acc = next;
  }
  return acc;
}

List<String> _words(String s) => s.split(' ').where((w) => w.isNotEmpty).toList();

/// In a word like "er/sie/es" each part, or the whole word, is accepted.
List<String> _slashVariants(String s) {
  final words = _words(s);
  if (!words.any((w) => w.contains('/'))) return [s];
  return _cartesian([
    for (final w in words)
      if (w.split('/').where((p) => p.isNotEmpty).toList() case final parts when parts.length > 1)
        [w, ...parts]
      else
        [w],
  ]);
}

/// A prefix is dropped only at a word boundary: it must be followed by a space, unless it
/// ends in an apostrophe (elision, e.g. French "l'"). So "die" never strips "dieser".
List<String> _prefixVariants(String s, List<String> prefixes) {
  final out = [s];
  for (final raw in prefixes) {
    final p = raw.trim();
    if (p.isEmpty || !s.startsWith(p)) continue;
    final rest = s.substring(p.length);
    if (!p.endsWith("'") && !rest.startsWith(' ')) continue;
    if (rest.trim().isNotEmpty) out.add(rest.trim());
  }
  return out;
}

List<String> _optionalWordVariants(String s, Set<String> words) {
  if (words.isEmpty) return [s];
  return _cartesian([
    for (final t in _words(s)) words.contains(t) ? [t, ''] : [t],
  ]).map((v) => v.replaceAll(_spaces, ' ').trim()).toList();
}

/// All accepted, finished variants of one expected string, for the language being typed.
Set<String> acceptedVariants(String expected, String lang, MatchingConfig cfg) {
  final ign = cfg.ignoreDiacritics;
  List<String> norm(List<String>? list) => [for (final p in list ?? const []) normalize(p, ign)];

  var set = {normalize(expected, ign).trim()};
  set = _flatMapSet(set, (s) => [s, ..._parenVariants(s)]);
  set = _flatMapSet(set, (s) => [s, ..._slashVariants(s)]);
  set = _flatMapSet(set, (s) => _prefixVariants(s, norm(cfg.stripPrefixes[lang])));
  set = _flatMapSet(set, (s) => _prefixVariants(s, norm(cfg.optionalArticles[lang])));
  final words = {for (final w in norm(cfg.optionalWords[lang])) w.trim()};
  set = _flatMapSet(set, (s) => _optionalWordVariants(s, words));

  return {
    for (final v in set)
      if (_finish(v) case final f when f.isNotEmpty) f,
  };
}

final _abbreviation = RegExp(r'[.+]');
final _listSeparator = RegExp(r'[,;]');

/// Verb forms from `info` that are accepted as alternatives to the lemma (SPEC 7, rule 6).
/// With an explicit `pos`, only verbs qualify. Without it, `info` counts as a list of forms
/// when it contains no abbreviation dot and no "+".
List<String> infoForms({String? info, String? pos}) {
  final i = info?.trim();
  if (i == null || i.isEmpty) return [];
  if (pos != null && pos != 'verb') return [];
  if (pos == null && _abbreviation.hasMatch(i)) return [];
  return i.split(_listSeparator).map((f) => f.trim()).where((f) => f.isNotEmpty).toList();
}

/// The expected strings for an entry in the given direction.
List<String> expectedStrings(MatchEntry entry, MatchContext ctx) {
  if (ctx.direction == Direction.srcToTr) return entry.tr[ctx.lang] ?? [];
  return [entry.lemma, ...infoForms(info: entry.info, pos: entry.pos)];
}

/// Edit distance over code points (not UTF-16 units), like `Array.from` in the TS version.
int levenshtein(String a, String b) {
  final x = a.runes.toList();
  final y = b.runes.toList();
  if (x.isEmpty) return y.length;
  if (y.isEmpty) return x.length;
  var prev = List<int>.generate(y.length + 1, (j) => j);
  for (var i = 1; i <= x.length; i++) {
    final cur = List<int>.filled(y.length + 1, 0)..[0] = i;
    for (var j = 1; j <= y.length; j++) {
      final cost = x[i - 1] == y[j - 1] ? 0 : 1;
      final a = prev[j] + 1, b = cur[j - 1] + 1, c = prev[j - 1] + cost;
      cur[j] = a < b ? (a < c ? a : c) : (b < c ? b : c);
    }
    prev = cur;
  }
  return prev[y.length];
}

typedef _Candidate = ({String original, Set<String> variants});

MatchResult _matchPart(String answer, List<_Candidate> candidates) {
  if (answer.isEmpty) return const MatchResult(Verdict.wrong, null);
  for (final c in candidates) {
    if (c.variants.contains(answer)) return MatchResult(Verdict.correct, c.original);
  }
  for (final c in candidates) {
    for (final v in c.variants) {
      if (v.runes.length >= almostMinLength && levenshtein(answer, v) == 1) {
        return MatchResult(Verdict.almost, c.original);
      }
    }
  }
  return const MatchResult(Verdict.wrong, null);
}

const _rank = {Verdict.wrong: 0, Verdict.almost: 1, Verdict.correct: 2};

/// Check a typed answer. One correct meaning is enough. If the answer lists several
/// meanings separated by "," or ";", every one of them must be acceptable; the
/// result is the weakest verdict among them.
MatchResult checkAnswer(MatchEntry entry, String answer, MatchContext ctx) {
  final typedLang = ctx.direction == Direction.srcToTr ? ctx.lang : ctx.sourceLang;
  final ign = ctx.matching.ignoreDiacritics;
  final candidates = [
    for (final original in expectedStrings(entry, ctx))
      (original: original, variants: acceptedVariants(original, typedLang, ctx.matching)),
  ];

  final normalized = normalize(answer, ign);
  final whole = _matchPart(_finish(normalized), candidates);
  if (whole.verdict == Verdict.correct) return whole;

  final parts = normalized.split(_listSeparator).map(_finish).toList();
  if (parts.length < 2) return whole;
  final results = [for (final p in parts) _matchPart(p, candidates)];
  final weakest = results.reduce((a, b) => _rank[b.verdict]! < _rank[a.verdict]! ? b : a);
  if (weakest.verdict == Verdict.wrong) return whole;
  return MatchResult(weakest.verdict, results.first.expected);
}
