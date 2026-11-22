import 'fake-indexeddb/auto';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { createApiClient } from '../api/client';
import { loadProfile } from '../learning/testing';
import {
  deviceId,
  eventsForProfile,
  lastUser,
  recordAnswer,
  setLastUser,
  UserDb,
} from './db';
import { localProfiles, refreshProfiles } from './profiles';

const demo = loadProfile('profiles/demo/demo-latin.yaml');

/** A fake server for the profile endpoints; `profiles` maps id -> [etag, document]. */
function fakeApi(profiles: Map<string, [string, unknown]>) {
  const calls: string[] = [];
  const fetch = async (req: Request) => {
    const url = new URL(req.url);
    calls.push(`${url.pathname} ${req.headers.get('If-None-Match') ?? ''}`.trim());
    const json = (body: unknown, headers: Record<string, string> = {}) =>
      new Response(JSON.stringify(body), {
        headers: { 'Content-Type': 'application/json', ...headers },
      });
    if (url.pathname === '/api/v1/profiles') {
      return json(
        [...profiles].map(([id, [etag]]) => ({
          id, etag, title: id, source_lang: 'la', required_translation_lang: 'de',
          translation_langs: ['de'], revision: 1,
        })),
      );
    }
    const id = url.pathname.split('/').pop()!;
    const found = profiles.get(id);
    if (!found) return new Response('{}', { status: 404 });
    if (req.headers.get('If-None-Match') === found[0]) {
      return new Response(null, { status: 304, headers: { ETag: found[0] } });
    }
    return json(found[1], { ETag: found[0] });
  };
  const api = createApiClient({ baseUrl: 'https://capsa.test', fetch: fetch as typeof globalThis.fetch });
  return { api, calls };
}

let db: UserDb;
beforeEach(() => {
  db = new UserDb(`test-${Math.random()}`);
});
afterEach(async () => {
  await db.delete();
});

describe('device', () => {
  it('keeps a stable device id', async () => {
    const a = await deviceId();
    expect(a).toMatch(/^[0-9a-f]{32}$/);
    expect(await deviceId()).toBe(a);
  });

  it('remembers the last user', async () => {
    const me = { id: 'u1', username: 'lena', role: 'learner' as const };
    await setLastUser(me);
    expect(await lastUser()).toEqual(me);
    await setLastUser(null);
    expect(await lastUser()).toBeUndefined();
  });
});

describe('answers', () => {
  it('records unsynced events per profile', async () => {
    const answer = {
      profileId: 'demo-latin', entryId: 'u1-nauta', direction: 'src_to_tr' as const,
      mode: 'typed' as const, correct: true, responseMs: 1200,
    };
    const e = await recordAnswer(db, answer, 'dev1', 1_800_000_000_000);
    await recordAnswer(db, { ...answer, profileId: 'other' }, 'dev1');
    expect(e).toMatchObject({ ts: 1_800_000_000_000, synced: 0, received_at: null });
    const events = await eventsForProfile(db, 'demo-latin');
    expect(events.map((x) => x.id)).toEqual([e.id]);
  });
});

describe('refreshProfiles', () => {
  it('downloads new profiles and revalidates with the ETag', async () => {
    const server = new Map<string, [string, unknown]>([['demo-latin', ['"v1"', demo]]]);
    const { api, calls } = fakeApi(server);
    expect(await refreshProfiles(api, db)).toEqual({ updated: ['demo-latin'], removed: [] });
    const [stored] = await localProfiles(db);
    expect(stored.etag).toBe('"v1"');
    expect(stored.doc.units.length).toBe(2);

    calls.length = 0;
    expect(await refreshProfiles(api, db)).toEqual({ updated: [], removed: [] });
    expect(calls).toEqual(['/api/v1/profiles']); // same ETag in the list: no download

    server.set('demo-latin', ['"v2"', { ...demo, profile: { ...demo.profile, revision: 2 } }]);
    expect((await refreshProfiles(api, db)).updated).toEqual(['demo-latin']);
    expect(calls.at(-1)).toBe('/api/v1/profiles/demo-latin "v1"');
    expect((await db.profiles.get('demo-latin'))?.etag).toBe('"v2"');
  });

  it('removes local copies of profiles that are no longer released', async () => {
    const server = new Map<string, [string, unknown]>([['demo-latin', ['"v1"', demo]]]);
    const { api } = fakeApi(server);
    await refreshProfiles(api, db);
    server.clear();
    expect(await refreshProfiles(api, db)).toEqual({ updated: [], removed: ['demo-latin'] });
    expect(await db.profiles.count()).toBe(0);
  });

  it('fails without touching local copies when offline', async () => {
    const { api } = fakeApi(new Map([['demo-latin', ['"v1"', demo]]]));
    await refreshProfiles(api, db);
    const offline = createApiClient({
      baseUrl: 'https://capsa.test',
      fetch: (async () => {
        throw new TypeError('network down');
      }) as typeof fetch,
    });
    await expect(refreshProfiles(offline, db)).rejects.toThrow('network down');
    expect(await db.profiles.count()).toBe(1);
  });
});
