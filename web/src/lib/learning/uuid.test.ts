import { describe, expect, it } from 'vitest';
import { uuidv7 } from './uuid';

describe('uuidv7', () => {
  it('encodes time, version and variant', () => {
    const id = uuidv7(0x0189_abcd_ef01, (b) => b.fill(0xff));
    expect(id).toBe('0189abcd-ef01-7fff-bfff-ffffffffffff');
  });
  it('sorts by time', () => {
    expect(uuidv7(1000) < uuidv7(2000)).toBe(true);
  });
  it('is random within the same millisecond', () => {
    expect(uuidv7(5)).not.toBe(uuidv7(5));
  });
});
