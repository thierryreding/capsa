import { describe, expect, it } from 'vitest';
import type { ProfileDocument } from '../api/client';
import { indexProfile } from './cards';
import { choicesFor, seededRandom, wordClass } from './choice';
import { loadProfile, privateProfilePaths } from './testing';

const demo = indexProfile(loadProfile('profiles/demo/demo-latin.yaml') as unknown as ProfileDocument);
const entry = (id: string) => demo.entries.get(id)!;

describe('wordClass', () => {
  it.each([
    ['u1-nauta', 'noun'], // "m."
    ['u2-tempestas', 'noun'], // "tempestātem f."
    ['u2-navigare', 'verb'], // info form
    ['u1-navigat', 'verb'], // er/sie/es ...
    ['u1-procul', 'adverb'],
    ['u1-trans', 'preposition'],
    ['u2-aut', 'conjunction'],
    ['u1-is-ea-id', 'pronoun'],
    ['u1-heus', 'other'],
  ])('%s is a %s', (id, cls) => {
    expect(wordClass(entry(id))).toBe(cls);
  });

  it('an explicit pos wins', () => {
    expect(wordClass({ ...entry('u1-nauta'), pos: 'verb' })).toBe('verb');
    expect(wordClass({ ...entry('u1-nauta'), pos: 'numeral' })).toBe('other');
  });
});

describe('choicesFor', () => {
  it('one correct option and three distinct distractors, shuffled', () => {
    const options = choicesFor(demo, 'u1-nauta', 'src_to_tr', 'de', seededRandom(1));
    expect(options).toHaveLength(4);
    expect(options.filter((o) => o.correct)).toEqual([
      { text: 'der Seemann, der Matrose', correct: true },
    ]);
    expect(new Set(options.map((o) => o.text)).size).toBe(4);
  });

  it('prefers the same word class and unit', () => {
    // u1-nauta is a noun in unit 1; the other unit-1 nouns are insula and ventus.
    const distractors = choicesFor(demo, 'u1-nauta', 'src_to_tr', 'de', seededRandom(2))
      .filter((o) => !o.correct)
      .map((o) => o.text);
    expect(distractors).toContain('die Insel');
    expect(distractors).toContain('der Wind');
  });

  it('the reverse direction offers lemmas', () => {
    const options = choicesFor(demo, 'u2-navigare', 'tr_to_src', 'de', seededRandom(3));
    expect(options.find((o) => o.correct)?.text).toBe('nāvigāre');
    expect(options.every((o) => !o.text.includes(','))).toBe(true);
  });

  it('never offers an entry that shares a meaning with the right one', () => {
    // A made-up second entry that also means "der Wind" must not appear for ventus.
    const doc = structuredClone(demo.doc);
    doc.units[1].entries.push({ id: 'u2-aura', lemma: 'aura', info: 'f.', tr: { de: ['der Wind', 'der Hauch'] } });
    const index = indexProfile(doc);
    for (let seed = 0; seed < 30; seed++) {
      const options = choicesFor(index, 'u1-ventus', 'src_to_tr', 'de', seededRandom(seed));
      expect(options.map((o) => o.text)).not.toContain('der Wind, der Hauch');
    }
  });

  it('skips entries without a translation in the language', () => {
    for (let seed = 0; seed < 20; seed++) {
      const options = choicesFor(demo, 'u1-nauta', 'src_to_tr', 'fr', seededRandom(seed));
      expect(options.every((o) => o.text.length > 0)).toBe(true);
    }
  });

  it('works with tiny profiles', () => {
    const doc = structuredClone(demo.doc);
    doc.units = [{ ...doc.units[0], entries: doc.units[0].entries.slice(0, 2) }];
    const options = choicesFor(indexProfile(doc), 'u1-nauta', 'src_to_tr', 'de', seededRandom(4));
    expect(options).toHaveLength(2);
  });

  it('is deterministic for a given random source', () => {
    const a = choicesFor(demo, 'u1-nauta', 'src_to_tr', 'de', seededRandom(9));
    const b = choicesFor(demo, 'u1-nauta', 'src_to_tr', 'de', seededRandom(9));
    expect(a).toEqual(b);
  });
});

// Property check on private profiles, if present: every entry gets exactly one right
// option among distinct texts (content is not copied into the repository).
const privatePaths = privateProfilePaths();
describe.skipIf(privatePaths.length === 0)('private profiles', () => {
  for (const path of privatePaths) {
    it(`${path.split('/').pop()}: exactly one right option for every card`, () => {
      const index = indexProfile(loadProfile(path) as unknown as ProfileDocument);
      const lang = index.doc.profile.required_translation_lang;
      const problems: string[] = [];
      for (const ref of index.refs) {
        for (const direction of ['src_to_tr', 'tr_to_src'] as const) {
          const options = choicesFor(index, ref.id, direction, lang, seededRandom(7));
          const texts = options.map((o) => o.text);
          if (options.filter((o) => o.correct).length !== 1) problems.push(`${ref.id}: correct`);
          if (new Set(texts).size !== texts.length) problems.push(`${ref.id}: duplicate`);
          if (options.length < 4) problems.push(`${ref.id}: only ${options.length}`);
        }
      }
      expect(problems).toEqual([]);
    });
  }
});
