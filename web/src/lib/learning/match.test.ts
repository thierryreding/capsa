import { describe, expect, it } from 'vitest';
import {
  acceptedVariants,
  checkAnswer,
  infoForms,
  levenshtein,
  normalize,
  type Direction,
  type MatchContext,
  type Verdict,
} from './match';
import { entriesById, loadJson, loadProfile, privateProfilePaths, type ProfileDoc } from './testing';

interface Vector {
  entry: string;
  direction: Direction;
  lang: string;
  answer: string;
  verdict: Verdict;
  why?: string;
}

const vectors = loadJson<{ profile: string; cases: Vector[] }>('vectors/match.json');
const demo = loadProfile(vectors.profile);
const demoEntries = entriesById(demo);

function ctx(doc: ProfileDoc, direction: Direction, lang: string): MatchContext {
  return {
    direction,
    lang,
    sourceLang: doc.profile.source_lang,
    matching: doc.profile.matching ?? {},
  };
}

describe('shared vectors (vectors/match.json)', () => {
  it.each(vectors.cases)('$entry $direction/$lang: "$answer" -> $verdict', (v) => {
    const entry = demoEntries.get(v.entry);
    expect(entry, `entry ${v.entry} missing from demo profile`).toBeDefined();
    expect(checkAnswer(entry!, v.answer, ctx(demo, v.direction, v.lang)).verdict).toBe(v.verdict);
  });
});

describe('normalize', () => {
  it('strips combining marks only when asked', () => {
    expect(normalize('nāvigō', true)).toBe('navigo');
    expect(normalize('nāvigō', false)).toBe('nāvigō');
  });
  it('recomposes so precomposed and decomposed input compare equal', () => {
    expect(normalize('été', false)).toBe(normalize('été', false));
  });
  it('folds case and ß', () => {
    expect(normalize('GROSS Straße', false)).toBe('gross strasse');
  });
});

describe('acceptedVariants', () => {
  it('expands parentheses, slashes, prefixes and optional words', () => {
    const cfg = demo.profile.matching!;
    expect([...acceptedVariants('er/sie/es fährt (zur See)', 'de', cfg)].sort()).toEqual(
      [
        'er/sie/es fahrt (zur see)',
        'er/sie/es fahrt zur see',
        'er/sie/es fahrt',
        ...['er', 'sie', 'es'].flatMap((p) => [
          `${p} fahrt (zur see)`,
          `${p} fahrt zur see`,
          `${p} fahrt`,
        ]),
        'fahrt (zur see)',
        'fahrt zur see',
        'fahrt',
      ].sort(),
    );
  });
  it('drops prefixes and articles only at a word boundary', () => {
    const cfg = { optional_articles: { de: ['die'], fr: ["l'"] }, strip_prefixes: { de: ['er/sie/es'] } };
    expect([...acceptedVariants('dieser Wind', 'de', cfg)]).toEqual(['dieser wind']);
    expect(acceptedVariants('die Insel', 'de', cfg)).toContain('insel');
    expect(acceptedVariants("l'île", 'fr', cfg)).toContain('île');
    expect(acceptedVariants('er/sie/es segelt', 'de', cfg)).toContain('segelt');
  });
  it('still accepts prefixes written with a trailing space', () => {
    const cfg = { optional_articles: { de: ['die '] } };
    expect(acceptedVariants('die Insel', 'de', cfg)).toContain('insel');
    expect([...acceptedVariants('dieser Wind', 'de', cfg)]).toEqual(['dieser wind']);
  });
  it('stays bounded on pathological input', () => {
    const many = Array.from({ length: 20 }, (_, i) => `a${i}/b${i}`).join(' ');
    expect(acceptedVariants(many, 'de', {}).size).toBeLessThanOrEqual(256);
  });
});

describe('infoForms', () => {
  it.each([
    [{ info: 'nāvigō' }, ['nāvigō']],
    [{ info: 'ferō, fers, fert' }, ['ferō', 'fers', 'fert']],
    [{ info: 'm.' }, []],
    [{ info: 'tempestātem f.' }, []],
    [{ info: 'Präp. + Akk.' }, []],
    [{ info: 'Adv.' }, []],
    [{}, []],
    [{ info: 'nāvigō', pos: 'noun' }, []],
    [{ info: 'dō, dedī', pos: 'verb' }, ['dō', 'dedī']],
  ])('%o -> %o', (entry, forms) => {
    expect(infoForms(entry)).toEqual(forms);
  });
});

describe('levenshtein', () => {
  it.each([
    ['', '', 0],
    ['abc', '', 3],
    ['kitten', 'sitting', 3],
    ['seemann', 'seeman', 1],
    ['ab', 'ba', 2],
  ])('%s / %s = %i', (a, b, d) => {
    expect(levenshtein(a, b)).toBe(d);
  });
});

// Property checks against private profiles, if present on this machine.
// They assert general invariants and never copy profile content into the repository.
const privatePaths = privateProfilePaths();
describe.skipIf(privatePaths.length === 0)('private profiles', () => {
  for (const path of privatePaths) {
    const doc = loadProfile(path);
    const { required_translation_lang: req, matching = {} } = doc.profile;
    const entries = doc.units.flatMap((u) => u.entries).filter((e) => !e.deprecated);
    const toTr = ctx(doc, 'src_to_tr', req);
    const toSrc = ctx(doc, 'tr_to_src', req);
    const strip = (s: string) => s.normalize('NFD').replace(/\p{M}/gu, '');

    it(`${doc.profile.id}: every meaning accepts itself, upper-cased and unaccented`, () => {
      const failures: string[] = [];
      for (const e of entries) {
        for (const m of e.tr[req] ?? []) {
          for (const answer of [m, m.toUpperCase(), matching.ignore_diacritics ? strip(m) : m]) {
            if (checkAnswer(e, answer, toTr).verdict !== 'correct') failures.push(e.id);
          }
        }
      }
      expect(failures).toEqual([]);
    });

    it(`${doc.profile.id}: every meaning is accepted without its prefix`, () => {
      const prefixes = matching.strip_prefixes?.[req] ?? [];
      const failures: string[] = [];
      for (const e of entries) {
        for (const m of e.tr[req] ?? []) {
          for (const p of prefixes) {
            if (m.startsWith(p) && checkAnswer(e, m.slice(p.length), toTr).verdict !== 'correct') {
              failures.push(e.id);
            }
          }
        }
      }
      expect(failures).toEqual([]);
    });

    it(`${doc.profile.id}: every lemma and info form is accepted, with and without macrons`, () => {
      const failures: string[] = [];
      for (const e of entries) {
        for (const form of [e.lemma, ...infoForms(e)]) {
          for (const answer of [form, strip(form)]) {
            if (checkAnswer(e, answer, toSrc).verdict !== 'correct') failures.push(e.id);
          }
        }
      }
      expect(failures).toEqual([]);
    });

    it(`${doc.profile.id}: no expected string expands to nothing`, () => {
      const empty = entries.filter((e) =>
        (e.tr[req] ?? []).some((m) => acceptedVariants(m, req, matching).size === 0),
      );
      expect(empty.map((e) => e.id)).toEqual([]);
    });
  }
});
