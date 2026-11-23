import { describe, expect, it } from 'vitest';
import { installAdvice, IOS_WARN_AFTER_MS, type InstallSituation } from './platform';

const now = 1_800_000_000_000;
const base: InstallSituation = { ios: false, standalone: false, canPrompt: false, lastSyncAt: now, now };

describe('installAdvice', () => {
  it('nothing when installed', () => {
    expect(installAdvice({ ...base, standalone: true, ios: true, lastSyncAt: 0 })).toBe('none');
  });

  it('iOS in Safari: hint, or warning when not synced for more than 5 days', () => {
    expect(installAdvice({ ...base, ios: true })).toBe('ios-hint');
    expect(installAdvice({ ...base, ios: true, lastSyncAt: null })).toBe('ios-hint');
    expect(installAdvice({ ...base, ios: true, lastSyncAt: now - IOS_WARN_AFTER_MS })).toBe('ios-hint');
    expect(installAdvice({ ...base, ios: true, lastSyncAt: now - IOS_WARN_AFTER_MS - 1 })).toBe(
      'ios-warning',
    );
  });

  it('Chrome offers an install button when the browser allows it', () => {
    expect(installAdvice({ ...base, canPrompt: true })).toBe('prompt');
    expect(installAdvice(base)).toBe('none');
  });
});
