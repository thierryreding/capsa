/**
 * Multiple choice (F5): the correct solution plus distractors from other entries.
 * Pure functions; randomness is injected.
 *
 * Distractors should be plausible, or the answer is guessed from its shape: they come
 * preferably from the same word class and the same unit, then from nearby units.
 * An entry that shares a meaning (or form) with the correct one is never offered,
 * so there is always exactly one right option.
 */
import type { Entry } from '../api/client';
import { solution, type ProfileIndex } from './cards';
import { infoForms, normalize, type Direction } from './match';

export type WordClass =
  | 'noun'
  | 'verb'
  | 'adverb'
  | 'preposition'
  | 'conjunction'
  | 'pronoun'
  | 'other';

export const OPTIONS = 4;

/**
 * Word class from `pos`, or guessed from the book's info column (German
 * abbreviations) and the translation. Unknown cases are 'other'.
 */
export function wordClass(entry: Pick<Entry, 'pos' | 'info' | 'tr'>): WordClass {
  switch (entry.pos) {
    case 'noun':
    case 'verb':
    case 'adverb':
    case 'preposition':
    case 'conjunction':
    case 'pronoun':
      return entry.pos;
    case undefined:
      break;
    default:
      return 'other';
  }
  const info = entry.info ?? '';
  if (/(^|\s)[mfn]\.(\s|$)|\bPl\./.test(info)) return 'noun';
  if (/Präp/.test(info)) return 'preposition';
  if (/Konj/.test(info)) return 'conjunction';
  if (/Pron/.test(info)) return 'pronoun';
  if (/Adv/.test(info)) return 'adverb';
  if (infoForms(entry).length > 0) return 'verb';
  const meanings = Object.values(entry.tr).flat();
  if (meanings.some((m) => /^(er\/sie\/es|il\/elle) /.test(m))) return 'verb';
  return 'other';
}

/** Normalised meanings or forms that would make an entry a second right answer. */
function answers(entry: Entry, direction: Direction, lang: string): Set<string> {
  const raw = direction === 'src_to_tr' ? (entry.tr[lang] ?? []) : [entry.lemma, ...infoForms(entry)];
  return new Set(raw.map((x) => normalize(x, true).trim()));
}

export interface Choice {
  text: string;
  correct: boolean;
}

function shuffle<T>(items: T[], random: () => number): T[] {
  const a = [...items];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

/**
 * Options for one card: the correct solution and up to OPTIONS-1 distractors, shuffled.
 * Only active entries that can be asked in `lang` are used as distractors.
 */
export function choicesFor(
  index: ProfileIndex,
  entryId: string,
  direction: Direction,
  lang: string,
  random: () => number = Math.random,
  count: number = OPTIONS,
): Choice[] {
  const entry = index.entries.get(entryId)!;
  const unitNumber = (id: string) => index.unitOf.get(id)?.number ?? 0;
  const correctText = solution(entry, direction, lang);
  const own = answers(entry, direction, lang);
  const cls = wordClass(entry);
  const unit = unitNumber(entryId);

  const seen = new Set([normalize(correctText, true)]);
  const candidates = index.refs
    .map((r) => index.entries.get(r.id)!)
    .filter((e) => e.id !== entryId && (e.tr[lang]?.length ?? 0) > 0)
    .filter((e) => ![...answers(e, direction, lang)].some((a) => own.has(a)))
    .map((e) => ({
      text: solution(e, direction, lang),
      // lower is better: same word class first, then closeness of the unit
      rank: (wordClass(e) === cls ? 0 : 1000) + Math.abs(unitNumber(e.id) - unit),
      tiebreak: random(),
    }))
    .sort((a, b) => a.rank - b.rank || a.tiebreak - b.tiebreak);

  const distractors: string[] = [];
  for (const c of candidates) {
    if (distractors.length >= count - 1) break;
    const key = normalize(c.text, true);
    if (seen.has(key)) continue; // identical texts would be two equal buttons
    seen.add(key);
    distractors.push(c.text);
  }
  return shuffle(
    [{ text: correctText, correct: true }, ...distractors.map((text) => ({ text, correct: false }))],
    random,
  );
}

/** Deterministic random numbers in [0, 1) for tests (mulberry32). */
export function seededRandom(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
