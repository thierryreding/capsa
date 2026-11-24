/// The profile document as served by `GET /api/v1/profiles/{id}` (SPEC 4).
///
/// Mirrors schemas/profile.schema.json. Only what the app reads is typed; the
/// document is parsed once when it is loaded from the local store.
library;

List<String> _strings(Object? v) => [for (final x in (v as List?) ?? const []) x as String];

Map<String, List<String>> _stringsByLang(Object? v) => {
  for (final e in ((v as Map?) ?? const {}).entries) e.key as String: _strings(e.value),
};

class MatchingConfig {
  const MatchingConfig({
    this.ignoreDiacritics = false,
    this.stripPrefixes = const {},
    this.optionalArticles = const {},
    this.optionalWords = const {},
  });

  factory MatchingConfig.fromJson(Map<String, Object?>? j) {
    if (j == null) return const MatchingConfig();
    return MatchingConfig(
      ignoreDiacritics: j['ignore_diacritics'] as bool? ?? false,
      stripPrefixes: _stringsByLang(j['strip_prefixes']),
      optionalArticles: _stringsByLang(j['optional_articles']),
      optionalWords: _stringsByLang(j['optional_words']),
    );
  }

  final bool ignoreDiacritics;
  final Map<String, List<String>> stripPrefixes;
  final Map<String, List<String>> optionalArticles;
  final Map<String, List<String>> optionalWords;
}

class Note {
  const Note({required this.kind, required this.text, this.refs = const [], this.marker});

  factory Note.fromJson(Map<String, Object?> j) => Note(
    kind: j['kind'] as String,
    text: j['text'] as String,
    refs: _strings(j['refs']),
    marker: j['marker'] as String?,
  );

  final String kind;
  final String text;
  final List<String> refs;
  final String? marker;
}

class Entry {
  const Entry({
    required this.id,
    required this.lemma,
    required this.tr,
    this.info,
    this.pos,
    this.loanwords = const {},
    this.examples = const [],
    this.notes = const [],
    this.refs = const [],
    this.deprecated = false,
  });

  factory Entry.fromJson(Map<String, Object?> j) => Entry(
    id: j['id'] as String,
    lemma: j['lemma'] as String,
    info: j['info'] as String?,
    pos: j['pos'] as String?,
    tr: _stringsByLang(j['tr']),
    loanwords: _stringsByLang(j['loanwords']),
    examples: [
      for (final x in (j['examples'] as List?) ?? const [])
        {for (final e in (x as Map).entries) e.key as String: e.value as String},
    ],
    notes: [for (final x in (j['notes'] as List?) ?? const []) Note.fromJson(_map(x))],
    refs: _strings(j['refs']),
    deprecated: j['deprecated'] as bool? ?? false,
  );

  final String id;
  final String lemma;
  final String? info;
  final String? pos;

  /// Meanings per language (SPEC 4: joined with ", " for display).
  final Map<String, List<String>> tr;
  final Map<String, List<String>> loanwords;

  /// One sentence per language code.
  final List<Map<String, String>> examples;
  final List<Note> notes;
  final List<String> refs;
  final bool deprecated;

  Entry copyWith({String? pos, bool? deprecated}) => Entry(
    id: id,
    lemma: lemma,
    tr: tr,
    info: info,
    pos: pos ?? this.pos,
    loanwords: loanwords,
    examples: examples,
    notes: notes,
    refs: refs,
    deprecated: deprecated ?? this.deprecated,
  );
}

class Unit {
  const Unit({required this.id, required this.number, required this.title, required this.entries});

  factory Unit.fromJson(Map<String, Object?> j) => Unit(
    id: j['id'] as String,
    number: (j['number'] as num).toInt(),
    title: j['title'] as String,
    entries: [for (final x in j['entries'] as List) Entry.fromJson(_map(x))],
  );

  final String id;
  final int number;
  final String title;
  final List<Entry> entries;
}

class ProfileInfo {
  const ProfileInfo({
    required this.id,
    required this.title,
    required this.sourceLang,
    required this.requiredTranslationLang,
    required this.translationLangs,
    required this.revision,
    this.matching = const MatchingConfig(),
  });

  factory ProfileInfo.fromJson(Map<String, Object?> j) => ProfileInfo(
    id: j['id'] as String,
    title: j['title'] as String,
    sourceLang: j['source_lang'] as String,
    requiredTranslationLang: j['required_translation_lang'] as String,
    translationLangs: _strings(j['translation_langs']),
    revision: (j['revision'] as num).toInt(),
    matching: MatchingConfig.fromJson(j['matching'] == null ? null : _map(j['matching'])),
  );

  final String id;
  final String title;
  final String sourceLang;
  final String requiredTranslationLang;
  final List<String> translationLangs;
  final int revision;
  final MatchingConfig matching;
}

class ProfileDocument {
  const ProfileDocument({required this.profile, required this.units});

  factory ProfileDocument.fromJson(Map<String, Object?> j) => ProfileDocument(
    profile: ProfileInfo.fromJson(_map(j['profile'])),
    units: [for (final x in j['units'] as List) Unit.fromJson(_map(x))],
  );

  final ProfileInfo profile;
  final List<Unit> units;
}

Map<String, Object?> _map(Object? v) => (v as Map).cast<String, Object?>();
