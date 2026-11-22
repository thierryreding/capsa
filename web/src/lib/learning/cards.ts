/** What a card shows and expects, derived from the profile. Pure functions. */
import type { Entry, ProfileDocument, Unit } from '../api/client';
import type { Direction, MatchContext } from './match';
import type { EntryRef } from './session';

export interface ProfileIndex {
  doc: ProfileDocument;
  entries: Map<string, Entry>;
  unitOf: Map<string, Unit>;
  /** Active entries in book order. */
  refs: EntryRef[];
}

export function indexProfile(doc: ProfileDocument): ProfileIndex {
  const entries = new Map<string, Entry>();
  const unitOf = new Map<string, Unit>();
  const refs: EntryRef[] = [];
  for (const unit of doc.units) {
    for (const entry of unit.entries) {
      entries.set(entry.id, entry);
      unitOf.set(entry.id, unit);
      if (!entry.deprecated) refs.push({ id: entry.id, unitId: unit.id });
    }
  }
  return { doc, entries, unitOf, refs };
}

/** Meanings in one language, joined for display (SPEC 4). */
export function meanings(entry: Entry, lang: string): string {
  return (entry.tr[lang] ?? []).join(', ');
}

/** The text shown on the front of the card. */
export function prompt(entry: Entry, direction: Direction, lang: string): string {
  return direction === 'src_to_tr' ? entry.lemma : meanings(entry, lang);
}

/** The solution shown after answering. */
export function solution(entry: Entry, direction: Direction, lang: string): string {
  return direction === 'src_to_tr' ? meanings(entry, lang) : entry.lemma;
}

/** Whether the entry can be asked in this language (it has a translation there). */
export function askable(entry: Entry, lang: string): boolean {
  return (entry.tr[lang]?.length ?? 0) > 0;
}

export function matchContext(doc: ProfileDocument, direction: Direction, lang: string): MatchContext {
  return {
    direction,
    lang,
    sourceLang: doc.profile.source_lang,
    matching: doc.profile.matching ?? {},
  };
}

/** Whether the entry has anything to show behind the info icon (F2). */
export function hasExtras(entry: Entry): boolean {
  return Boolean(
    entry.notes?.length ||
      entry.examples?.length ||
      Object.keys(entry.loanwords ?? {}).length ||
      entry.refs?.length,
  );
}
