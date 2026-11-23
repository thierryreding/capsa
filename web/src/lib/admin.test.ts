import { describe, expect, it } from 'vitest';
import { checkNewUser, checkPassword, errorMessage, listUsers } from './admin';
import { createApiClient } from './api/client';

describe('checks before sending', () => {
  it('username and password', () => {
    expect(checkNewUser({ username: 'lena', password: 'geheim123' })).toBeNull();
    expect(checkNewUser({ username: 'Jürgen.K', password: 'geheim123' })).toBeNull();
    expect(checkNewUser({ username: 'mit leerzeichen', password: 'geheim123' })).toMatch(/Benutzername/);
    expect(checkNewUser({ username: '', password: 'geheim123' })).toMatch(/Benutzername/);
    expect(checkPassword('kurz')).toMatch(/mindestens 8/);
  });
});

describe('errorMessage', () => {
  it.each([
    [400, "username 'lena' is taken", 'schon vergeben'],
    [400, 'password must have at least 8 characters', 'mindestens 8'],
    [400, 'display name: at most 64 characters', 'höchstens 64'],
    [400, 'cannot disable your own account', 'eigenes Konto'],
    [400, 'unknown profiles: x', 'gibt es nicht'],
    [403, 'admin only', 'Elternkonto'],
    [500, 'boom', 'nicht geklappt'],
  ])('%i %s', (status, detail, expected) => {
    expect(errorMessage(status, detail)).toContain(expected);
  });

  it('network errors', () => {
    expect(errorMessage(null)).toContain('Keine Verbindung');
  });
});

describe('API calls', () => {
  const api = (fetch: (r: Request) => Promise<Response>) =>
    createApiClient({ baseUrl: 'https://capsa.test', fetch: fetch as typeof globalThis.fetch });

  it('returns the data or a German error', async () => {
    const users = [{ id: '1', username: 'lena', role: 'learner', disabled: false, profiles: [] }];
    expect(await listUsers(api(async () => Response.json(users)))).toEqual({ ok: true, value: users });
    const forbidden = await listUsers(
      api(async () => Response.json({ detail: 'admin only' }, { status: 403 })),
    );
    expect(forbidden).toEqual({ ok: false, error: expect.stringContaining('Elternkonto') });
    const offline = await listUsers(
      api(async () => {
        throw new TypeError('network');
      }),
    );
    expect(offline.ok).toBe(false);
  });
});
