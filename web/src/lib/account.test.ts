import { describe, expect, it } from 'vitest';
import { displayNameInput, greetingName } from './account';

describe('greetingName', () => {
  it('prefers the display name and falls back to the username', () => {
    expect(greetingName({ username: 'lena', display_name: 'Lena' })).toBe('Lena');
    expect(greetingName({ username: 'lena', display_name: null })).toBe('lena');
    expect(greetingName({ username: 'lena' })).toBe('lena');
    expect(greetingName({ username: 'lena', display_name: '  ' })).toBe('lena');
  });
});

describe('displayNameInput', () => {
  it('trims and clears', () => {
    expect(displayNameInput('  Lena Müller ')).toBe('Lena Müller');
    expect(displayNameInput('   ')).toBeNull();
  });
  it('counts characters, not UTF-16 units', () => {
    expect(displayNameInput('🦉'.repeat(64))).toBe('🦉'.repeat(64));
    expect(displayNameInput('x'.repeat(65))).toBe('invalid');
  });
  it('refuses control characters', () => {
    expect(displayNameInput('Le\nna')).toBe('invalid');
    expect(displayNameInput('a\u0085b')).toBe('invalid');
  });
});
