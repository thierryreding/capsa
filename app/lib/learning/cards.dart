/// What a card shows and expects, derived from the profile. Pure functions.
/// A port of web/src/lib/learning/cards.ts.
library;

import 'match.dart';
import 'profile.dart';
import 'session.dart';

class ProfileIndex {
  ProfileIndex._(this.doc, this.entries, this.unitOf, this.refs);

  factory ProfileIndex(ProfileDocument doc) {
    final entries = <String, Entry>{};
    final unitOf = <String, Unit>{};
    final refs = <EntryRef>[];
    for (final unit in doc.units) {
      for (final entry in unit.entries) {
        entries[entry.id] = entry;
        unitOf[entry.id] = unit;
        if (!entry.deprecated) refs.add(EntryRef(entry.id, unit.id));
      }
    }
    return ProfileIndex._(doc, entries, unitOf, refs);
  }

  final ProfileDocument doc;
  final Map<String, Entry> entries;
  final Map<String, Unit> unitOf;

  /// Active entries in book order.
  final List<EntryRef> refs;
}

/// Meanings in one language, joined for display (SPEC 4).
String meanings(Entry entry, String lang) => (entry.tr[lang] ?? const []).join(', ');

/// The text shown on the front of the card.
String prompt(Entry entry, Direction direction, String lang) =>
    direction == Direction.srcToTr ? entry.lemma : meanings(entry, lang);

/// The solution shown after answering.
String solution(Entry entry, Direction direction, String lang) =>
    direction == Direction.srcToTr ? meanings(entry, lang) : entry.lemma;

/// Whether the entry can be asked in this language (it has a translation there).
bool askable(Entry entry, String lang) => (entry.tr[lang]?.length ?? 0) > 0;

MatchContext matchContext(ProfileDocument doc, Direction direction, String lang) => MatchContext(
  direction: direction,
  lang: lang,
  sourceLang: doc.profile.sourceLang,
  matching: doc.profile.matching,
);

/// Whether the entry has anything to show behind the info icon (F2).
bool hasExtras(Entry entry) =>
    entry.notes.isNotEmpty ||
    entry.examples.isNotEmpty ||
    entry.loanwords.isNotEmpty ||
    entry.refs.isNotEmpty;
