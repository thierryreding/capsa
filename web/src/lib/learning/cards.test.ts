import { describe, expect, it } from 'vitest';
import type { ProfileDocument } from '../api/client';
import { askable, hasExtras, indexProfile, meanings, prompt, solution } from './cards';
import { loadProfile } from './testing';

const doc = loadProfile('profiles/demo/demo-latin.yaml') as unknown as ProfileDocument;
const index = indexProfile(doc);
const nauta = index.entries.get('u1-nauta')!;

describe('cards', () => {
  it('indexes entries in book order and skips deprecated ones in refs', () => {
    expect(index.refs[0]).toEqual({ id: 'u1-nauta', unitId: 'u1' });
    expect(index.unitOf.get('u2-dare')?.id).toBe('u2');
    const withDeprecated = structuredClone(doc);
    withDeprecated.units[0].entries[0].deprecated = true;
    const i2 = indexProfile(withDeprecated);
    expect(i2.refs.some((r) => r.id === 'u1-nauta')).toBe(false);
    expect(i2.entries.has('u1-nauta')).toBe(true); // old events still resolve
  });

  it('prompt and solution per direction', () => {
    expect(prompt(nauta, 'src_to_tr', 'de')).toBe('nauta');
    expect(solution(nauta, 'src_to_tr', 'de')).toBe('der Seemann, der Matrose');
    expect(prompt(nauta, 'tr_to_src', 'fr')).toBe('le marin');
    expect(solution(nauta, 'tr_to_src', 'fr')).toBe('nauta');
    expect(meanings(nauta, 'es')).toBe('');
  });

  it('askable only with a translation in the language', () => {
    expect(askable(index.entries.get('u1-spectat')!, 'fr')).toBe(false);
    expect(askable(index.entries.get('u1-spectat')!, 'de')).toBe(true);
  });

  it('extras behind the info icon', () => {
    expect(hasExtras(nauta)).toBe(true); // a note
    expect(hasExtras(index.entries.get('u1-procul')!)).toBe(false);
  });
});
