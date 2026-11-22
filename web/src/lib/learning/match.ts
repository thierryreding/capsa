/**
 * Answer checking for typed answers (SPEC section 7). Pure functions, no I/O.
 *
 * An expected string (a meaning from `tr[lang]`, the lemma, or a verb form from `info`)
 * is expanded into a set of accepted variants:
 *   1. normalise (NFD, optional removal of combining marks, lower case, ß -> ss,
 *      whitespace and apostrophes unified)
 *   2. parenthesised parts are optional:     "schau(t)!"        -> "schaut", "schau"
 *   3. slash alternatives within a word:      "er/sie/es segelt" -> "er segelt", "sie segelt", ...
 *   4. `strip_prefixes`, then `optional_articles` may be left out at the start
 *   5. `optional_words` may be left out anywhere: "jdm. etw. geben" -> "geben", ...
 *   6. sentence punctuation at either end and ellipses are ignored
 * The answer itself is only normalised (steps 1 and 6).
 */

export type Verdict = 'correct' | 'almost' | 'wrong';

/** src_to_tr: the source word is shown, the translation is typed. tr_to_src: the reverse. */
export type Direction = 'src_to_tr' | 'tr_to_src';

export interface MatchingConfig {
  ignore_diacritics?: boolean;
  strip_prefixes?: Record<string, string[]>;
  optional_articles?: Record<string, string[]>;
  optional_words?: Record<string, string[]>;
}

export interface MatchEntry {
  lemma: string;
  info?: string;
  pos?: string;
  tr: Record<string, string[]>;
}

export interface MatchContext {
  direction: Direction;
  /** Language of the translation side (the one typed for src_to_tr, shown for tr_to_src). */
  lang: string;
  sourceLang: string;
  matching: MatchingConfig;
}

export interface MatchResult {
  verdict: Verdict;
  /** The original expected string that matched (or nearly matched); null when wrong. */
  expected: string | null;
}

/** Minimum length of an expected variant for which a single typo counts as "almost". */
export const ALMOST_MIN_LENGTH = 6;

// Guard against pathological inputs: each expansion step caps the number of variants.
const MAX_VARIANTS = 256;

export function normalize(text: string, ignoreDiacritics: boolean): string {
  let t = text.normalize('NFD');
  if (ignoreDiacritics) t = t.replace(/\p{M}/gu, '');
  t = t.toLowerCase().replace(/ß/g, 'ss');
  t = t.normalize('NFC');
  t = t.replace(/[‘’ʼ`´]/g, "'");
  t = t.replace(/\s+/g, ' ');
  t = t.replace(/ ?\/ ?/g, '/');
  return t;
}

const EDGE_PUNCTUATION = /^[\s!?.,;:¡¿]+|[\s!?.,;:¡¿]+$/g;

function finish(text: string): string {
  return text
    .replace(/…|\.\.\./g, ' ')
    .replace(/\s+/g, ' ')
    .replace(EDGE_PUNCTUATION, '')
    .trim();
}

function cap<T>(items: Iterable<T>): Set<T> {
  const out = new Set<T>();
  for (const item of items) {
    if (out.size >= MAX_VARIANTS) break;
    out.add(item);
  }
  return out;
}

function flatMapSet(input: Set<string>, fn: (s: string) => string[]): Set<string> {
  const out: string[] = [];
  for (const s of input) out.push(...fn(s));
  return cap(out);
}

/** Every parenthesised group may be kept (without the brackets) or dropped. */
function parenVariants(s: string): string[] {
  const m = /\(([^()]*)\)/.exec(s);
  if (!m) return [s];
  const before = s.slice(0, m.index);
  const after = s.slice(m.index + m[0].length);
  return [
    ...parenVariants(before + m[1] + after),
    ...parenVariants(before + after),
  ];
}

function cartesian(options: string[][]): string[] {
  let acc: string[] = [''];
  for (const opts of options) {
    const next: string[] = [];
    for (const prefix of acc) {
      for (const o of opts) {
        next.push(prefix ? `${prefix} ${o}` : o);
        if (next.length >= MAX_VARIANTS) break;
      }
    }
    acc = next;
  }
  return acc;
}

/** In a word like "er/sie/es" each part, or the whole word, is accepted. */
function slashVariants(s: string): string[] {
  const words = s.split(' ').filter(Boolean);
  if (!words.some((w) => w.includes('/'))) return [s];
  return cartesian(
    words.map((w) => {
      const parts = w.split('/').filter(Boolean);
      return parts.length > 1 ? [w, ...parts] : [w];
    }),
  );
}

/**
 * A prefix is dropped only at a word boundary: it must be followed by a space, unless it
 * ends in an apostrophe (elision, e.g. French "l'"). So "die" never strips "dieser".
 */
function prefixVariants(s: string, prefixes: string[]): string[] {
  const out = [s];
  for (const raw of prefixes) {
    const p = raw.trim();
    if (!p || !s.startsWith(p)) continue;
    const rest = s.slice(p.length);
    if (!p.endsWith("'") && !rest.startsWith(' ')) continue;
    if (rest.trim()) out.push(rest.trim());
  }
  return out;
}

function optionalWordVariants(s: string, words: Set<string>): string[] {
  if (words.size === 0) return [s];
  const tokens = s.split(' ').filter(Boolean);
  return cartesian(tokens.map((t) => (words.has(t) ? [t, ''] : [t]))).map((v) =>
    v.replace(/\s+/g, ' ').trim(),
  );
}

/** All accepted, finished variants of one expected string, for the language being typed. */
export function acceptedVariants(expected: string, lang: string, cfg: MatchingConfig): Set<string> {
  const ign = cfg.ignore_diacritics ?? false;
  const norm = (list: string[] | undefined) => (list ?? []).map((p) => normalize(p, ign));

  let set = new Set([normalize(expected, ign).trim()]);
  set = flatMapSet(set, (s) => [s, ...parenVariants(s)]);
  set = flatMapSet(set, (s) => [s, ...slashVariants(s)]);
  set = flatMapSet(set, (s) => prefixVariants(s, norm(cfg.strip_prefixes?.[lang])));
  set = flatMapSet(set, (s) => prefixVariants(s, norm(cfg.optional_articles?.[lang])));
  const words = new Set(norm(cfg.optional_words?.[lang]).map((w) => w.trim()));
  set = flatMapSet(set, (s) => optionalWordVariants(s, words));

  const out = new Set<string>();
  for (const v of set) {
    const f = finish(v);
    if (f) out.add(f);
  }
  return out;
}

/**
 * Verb forms from `info` that are accepted as alternatives to the lemma (SPEC 7, rule 6).
 * With an explicit `pos`, only verbs qualify. Without it, `info` counts as a list of forms
 * when it contains no abbreviation dot and no "+" (so "m.", "Adv.", "+ Akk.",
 * "tempestātem f." are excluded, while "nāvigō" or "ferō, fers, fert" are accepted).
 */
export function infoForms(entry: Pick<MatchEntry, 'info' | 'pos'>): string[] {
  const info = entry.info?.trim();
  if (!info) return [];
  if (entry.pos !== undefined && entry.pos !== 'verb') return [];
  if (entry.pos === undefined && /[.+]/.test(info)) return [];
  return info
    .split(/[,;]/)
    .map((f) => f.trim())
    .filter(Boolean);
}

/** The expected strings for an entry in the given direction. */
export function expectedStrings(entry: MatchEntry, ctx: MatchContext): string[] {
  if (ctx.direction === 'src_to_tr') return entry.tr[ctx.lang] ?? [];
  return [entry.lemma, ...infoForms(entry)];
}

export function levenshtein(a: string, b: string): number {
  const x = Array.from(a);
  const y = Array.from(b);
  if (x.length === 0) return y.length;
  if (y.length === 0) return x.length;
  let prev = Array.from({ length: y.length + 1 }, (_, j) => j);
  for (let i = 1; i <= x.length; i++) {
    const cur = [i];
    for (let j = 1; j <= y.length; j++) {
      const cost = x[i - 1] === y[j - 1] ? 0 : 1;
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
    }
    prev = cur;
  }
  return prev[y.length];
}

interface Candidate {
  original: string;
  variants: Set<string>;
}

function matchPart(answer: string, candidates: Candidate[]): MatchResult {
  if (!answer) return { verdict: 'wrong', expected: null };
  for (const c of candidates) {
    if (c.variants.has(answer)) return { verdict: 'correct', expected: c.original };
  }
  for (const c of candidates) {
    for (const v of c.variants) {
      if (Array.from(v).length >= ALMOST_MIN_LENGTH && levenshtein(answer, v) === 1) {
        return { verdict: 'almost', expected: c.original };
      }
    }
  }
  return { verdict: 'wrong', expected: null };
}

const RANK: Record<Verdict, number> = { wrong: 0, almost: 1, correct: 2 };

/**
 * Check a typed answer. One correct meaning is enough. If the answer lists several
 * meanings separated by "," or ";", every one of them must be acceptable; the
 * result is the weakest verdict among them.
 */
export function checkAnswer(entry: MatchEntry, answer: string, ctx: MatchContext): MatchResult {
  const typedLang = ctx.direction === 'src_to_tr' ? ctx.lang : ctx.sourceLang;
  const ign = ctx.matching.ignore_diacritics ?? false;
  const candidates: Candidate[] = expectedStrings(entry, ctx).map((original) => ({
    original,
    variants: acceptedVariants(original, typedLang, ctx.matching),
  }));

  const normalized = normalize(answer, ign);
  const whole = matchPart(finish(normalized), candidates);
  if (whole.verdict === 'correct') return whole;

  const parts = normalized.split(/[,;]/).map(finish);
  if (parts.length < 2) return whole;
  const results = parts.map((p) => matchPart(p, candidates));
  const weakest = results.reduce((a, b) => (RANK[b.verdict] < RANK[a.verdict] ? b : a));
  if (weakest.verdict === 'wrong') return whole;
  return { verdict: weakest.verdict, expected: results[0].expected };
}
