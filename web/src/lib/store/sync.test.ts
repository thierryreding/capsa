import 'fake-indexeddb/auto';
import { afterEach, describe, expect, it } from 'vitest';
import { createApiClient, type ApiClient } from '../api/client';
import { computeStates, DEFAULT_INTERVALS_DAYS } from '../learning/leitner';
import { recordAnswer, UserDb, type Answer } from './db';
import { mergeSettings } from './settings';
import { localSettings, pullEvents, pushEvents, setSetting, syncAll, unsyncedCount } from './sync';

/**
 * In-memory stand-in for the sync endpoints, following the server's rules
 * (idempotent upload, server_seq paging, last-write-wins settings).
 */
class FakeServer {
  events: Record<string, unknown>[] = [];
  settings = new Map<string, { value: unknown; updated_at: string }>();
  released = new Set(['demo-latin']);
  requests: string[] = [];
  failNext = 0;
  now = 1_800_000_000_000;

  client(): ApiClient {
    const fetch = async (req: Request) => {
      const url = new URL(req.url);
      this.requests.push(`${req.method} ${url.pathname}${url.search}`);
      if (this.failNext > 0) {
        this.failNext--;
        return new Response('{"detail":"boom"}', { status: 500 });
      }
      const body = req.method === 'GET' ? null : await req.json();
      return Response.json(this.handle(req.method, url, body));
    };
    return createApiClient({ baseUrl: 'https://capsa.test', fetch: fetch as typeof globalThis.fetch });
  }

  handle(method: string, url: URL, body: any): unknown {
    const path = url.pathname;
    if (path === '/api/v1/sync/events' && method === 'POST') {
      let accepted = 0;
      let duplicates = 0;
      const rejected: { id: string; reason: string }[] = [];
      for (const e of body.events) {
        if (this.events.some((x) => x.id === e.id)) duplicates++;
        else if (!this.released.has(e.profile_id)) rejected.push({ id: e.id, reason: 'unknown_profile' });
        else {
          this.events.push({
            ...e,
            server_seq: this.events.length + 1,
            received_at: new Date(this.now).toISOString(),
          });
          accepted++;
        }
      }
      return { accepted, duplicates, rejected };
    }
    if (path === '/api/v1/sync/events') {
      const since = Number(url.searchParams.get('since') ?? 0);
      const limit = Number(url.searchParams.get('limit') ?? 500);
      const rest = this.events.filter((e) => (e.server_seq as number) > since);
      const page = rest.slice(0, limit);
      return {
        events: page,
        next_since: page.length ? page.at(-1)!.server_seq : since,
        more: rest.length > limit,
      };
    }
    if (path === '/api/v1/settings') {
      return [...this.settings].map(([key, s]) => ({ key, ...s }));
    }
    const key = path.split('/').pop()!;
    const current = this.settings.get(key);
    if (!current || Date.parse(body.updated_at) > Date.parse(current.updated_at)) {
      this.settings.set(key, { value: body.value, updated_at: body.updated_at });
    }
    return { key, ...this.settings.get(key)! };
  }
}

const dbs: UserDb[] = [];
function device(): UserDb {
  const db = new UserDb(`sync-${Math.random()}`);
  dbs.push(db);
  return db;
}
afterEach(async () => {
  for (const db of dbs.splice(0)) await db.delete();
});

const answer = (entryId: string, correct = true): Answer => ({
  profileId: 'demo-latin',
  entryId,
  direction: 'src_to_tr',
  mode: 'typed',
  correct,
  responseMs: 1000,
});

describe('pushEvents', () => {
  it('uploads pending events and marks them synced', async () => {
    const server = new FakeServer();
    const db = device();
    await recordAnswer(db, answer('u1-nauta'), 'dev-a', 1);
    await recordAnswer(db, answer('u1-ventus', false), 'dev-a', 2);
    expect(await pushEvents(server.client(), db)).toEqual({ pushed: 2, rejected: 0 });
    expect(await unsyncedCount(db)).toBe(0);
    expect(server.events.map((e) => e.entry_id)).toEqual(['u1-nauta', 'u1-ventus']);
    expect(await pushEvents(server.client(), db)).toEqual({ pushed: 0, rejected: 0 });
  });

  it('uploads in batches of 500', async () => {
    const server = new FakeServer();
    const db = device();
    for (let i = 0; i < 501; i++) await recordAnswer(db, answer('u1-nauta'), 'dev-a', i);
    expect((await pushEvents(server.client(), db)).pushed).toBe(501);
    expect(server.requests.filter((r) => r.startsWith('POST')).length).toBe(2);
  });

  it('marks rejected events and does not retry them', async () => {
    const server = new FakeServer();
    const db = device();
    await recordAnswer(db, { ...answer('x'), profileId: 'withdrawn' }, 'dev-a', 1);
    expect(await pushEvents(server.client(), db)).toEqual({ pushed: 0, rejected: 1 });
    expect((await db.events.toArray())[0]).toMatchObject({ synced: 1, rejected: 'unknown_profile' });
    expect(await pushEvents(server.client(), db)).toEqual({ pushed: 0, rejected: 0 });
  });

  it('keeps events pending when the upload fails, and retries safely', async () => {
    const server = new FakeServer();
    const db = device();
    await recordAnswer(db, answer('u1-nauta'), 'dev-a', 1);
    server.failNext = 1;
    await expect(pushEvents(server.client(), db)).rejects.toThrow('upload failed');
    expect(await unsyncedCount(db)).toBe(1);
    expect((await pushEvents(server.client(), db)).pushed).toBe(1);
  });
});

describe('pullEvents', () => {
  it('pages through new events and remembers where it stopped', async () => {
    const server = new FakeServer();
    const a = device();
    for (let i = 0; i < 1203; i++) await recordAnswer(a, answer('u1-nauta'), 'dev-a', i);
    await pushEvents(server.client(), a);

    const b = device();
    expect(await pullEvents(server.client(), b)).toBe(1203);
    expect(server.requests.filter((r) => r.startsWith('GET /api/v1/sync')).length).toBe(3);
    server.requests.length = 0;
    expect(await pullEvents(server.client(), b)).toBe(0);
    expect(server.requests).toEqual(['GET /api/v1/sync/events?since=1203&limit=500']);
  });

  it('gives own events their received_at', async () => {
    const server = new FakeServer();
    const db = device();
    const e = await recordAnswer(db, answer('u1-nauta'), 'dev-a', 5);
    await pushEvents(server.client(), db);
    expect(await pullEvents(server.client(), db)).toBe(0); // not new, but updated
    expect(await db.events.get(e.id)).toMatchObject({ received_at: server.now, server_seq: 1 });
  });
});

describe('two devices', () => {
  it('converge on the same learning state', async () => {
    const server = new FakeServer();
    const phone = device();
    const tablet = device();
    await recordAnswer(phone, answer('u1-nauta'), 'phone', 1000);
    await recordAnswer(tablet, answer('u1-nauta', false), 'tablet', 2000);
    await recordAnswer(tablet, answer('u1-ventus'), 'tablet', 3000);
    await recordAnswer(phone, answer('u1-ventus'), 'phone', 4000); // offline meanwhile

    await syncAll(server.client(), phone);
    await syncAll(server.client(), tablet);
    await syncAll(server.client(), phone);

    const config = { intervalsDays: DEFAULT_INTERVALS_DAYS, utcOffsetMinutes: 0 };
    const statesOf = async (db: UserDb) => computeStates(await db.events.toArray(), config);
    const phoneStates = await statesOf(phone);
    expect(phoneStates).toEqual(await statesOf(tablet));
    expect(phoneStates.get('demo-latin|u1-nauta|src_to_tr')?.box).toBe(1); // wrong last
    expect(phoneStates.get('demo-latin|u1-ventus|src_to_tr')?.box).toBe(3); // right twice
  });
});

describe('settings', () => {
  it('merge: newer wins, server wins ties, unknown local values are pushed', () => {
    const local = {
      a: { value: 'local', updatedAt: 20, dirty: true },
      b: { value: 'local', updatedAt: 10, dirty: true },
      c: { value: 'local', updatedAt: 10, dirty: true },
      d: { value: 'local', updatedAt: 10, dirty: true },
    };
    const remote = [
      { key: 'a', value: 'remote', updatedAt: 10 },
      { key: 'b', value: 'remote', updatedAt: 20 },
      { key: 'c', value: 'remote', updatedAt: 10 },
      { key: 'e', value: 'remote', updatedAt: 5 },
    ];
    const { settings, push } = mergeSettings(local, remote);
    expect(push.sort()).toEqual(['a', 'd']);
    expect(settings.a.value).toBe('local');
    expect(settings.b).toEqual({ value: 'remote', updatedAt: 20, dirty: false });
    expect(settings.c.value).toBe('remote');
    expect(settings.e.value).toBe('remote');
  });

  it('sync between two devices, last write wins', async () => {
    const server = new FakeServer();
    const phone = device();
    const tablet = device();
    await setSetting(phone, 'test-date', '2027-02-01', 1000);
    await syncAll(server.client(), phone);
    await syncAll(server.client(), tablet);
    expect((await localSettings(tablet))['test-date'].value).toBe('2027-02-01');

    await setSetting(tablet, 'test-date', '2027-03-01', 3000);
    await setSetting(phone, 'test-date', '2027-01-20', 2000); // older, made offline
    await syncAll(server.client(), phone);
    await syncAll(server.client(), tablet);
    await syncAll(server.client(), phone);
    for (const db of [phone, tablet]) {
      expect((await localSettings(db))['test-date']).toEqual({
        value: '2027-03-01',
        updatedAt: 3000,
        dirty: false,
      });
    }
  });
});
