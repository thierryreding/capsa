import { describe, expect, it } from 'vitest';
import { relativeTime, t } from './i18n';

describe('i18n', () => {
  it('fills parameters', () => {
    expect(t('home.hello', { name: 'Lena' })).toBe('Hallo Lena!');
    expect(t('home.hello')).toBe('Hallo {name}!');
  });

  it('relative times', () => {
    const now = 1_800_000_000_000;
    expect(relativeTime(now - 20_000, now)).toBe('gerade eben');
    expect(relativeTime(now - 5 * 60_000, now)).toBe('vor 5 Minuten');
    expect(relativeTime(now - 3 * 3_600_000, now)).toBe('vor 3 Stunden');
    expect(relativeTime(now - 86_400_000, now)).toBe('gestern');
  });
});
