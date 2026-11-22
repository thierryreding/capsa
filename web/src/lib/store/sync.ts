/**
 * Synchronisation with the server (SPEC 6). Local data is the source of truth; the
 * server collects events from all devices. Every step is idempotent, so an interrupted
 * sync is simply repeated next time.
 *
 * Runs at app start, when the app returns to the foreground, after a learning session
 * and when the network comes back; Safari on iOS has no background sync (SPEC 9).
 */
import type { ApiClient, Schemas } from '../api/client';
import type { LocalEvent, UserDb } from './db';
import { mergeSettings, type Json, type LocalSetting } from './settings';

export const BATCH = 500;
const SINCE_KEY = 'sync.since';
const SETTINGS_KEY = 'settings';
const LAST_SYNC_KEY = 'sync.last';

export interface SyncResult {
  pushed: number;
  pulled: number;
  rejected: number;
  settingsPushed: number;
}

export class SyncError extends Error {
  constructor(
    message: string,
    readonly status: number | null,
  ) {
    super(message);
  }
}

function check<T>(r: { data?: T; response: Response }, what: string): T {
  if (r.data === undefined) throw new SyncError(`${what} failed`, r.response.status);
  return r.data;
}

/** Upload events not yet on the server. */
export async function pushEvents(api: ApiClient, db: UserDb): Promise<{ pushed: number; rejected: number }> {
  let pushed = 0;
  let rejected = 0;
  for (;;) {
    const pending = await db.events.where('synced').equals(0).limit(BATCH).toArray();
    if (pending.length === 0) break;
    const result = check(
      await api.POST('/api/v1/sync/events', {
        body: {
          events: pending.map((e) => ({
            id: e.id,
            device_id: e.device_id,
            profile_id: e.profile_id,
            entry_id: e.entry_id,
            direction: e.direction,
            mode: e.mode,
            correct: e.correct,
            response_ms: e.response_ms,
            ts: new Date(e.ts).toISOString(),
          })),
        },
      }),
      'upload',
    );
    const reasons = new Map(result.rejected.map((r) => [r.id, r.reason]));
    await db.transaction('rw', db.events, async () => {
      for (const e of pending) {
        // Rejected events are not retried (e.g. the profile was withdrawn).
        await db.events.update(e.id, { synced: 1, rejected: reasons.get(e.id) ?? null });
      }
    });
    pushed += result.accepted;
    rejected += result.rejected.length;
    if (pending.length < BATCH) break;
  }
  return { pushed, rejected };
}

function fromServer(e: Schemas['StoredEvent']): LocalEvent {
  return {
    id: e.id,
    device_id: e.device_id,
    profile_id: e.profile_id,
    entry_id: e.entry_id,
    direction: e.direction,
    mode: e.mode,
    correct: e.correct,
    response_ms: e.response_ms ?? null,
    ts: Date.parse(e.ts),
    received_at: Date.parse(e.received_at),
    server_seq: e.server_seq,
    synced: 1,
    rejected: null,
  };
}

/** Fetch events this device has not seen yet (from all devices, including its own). */
export async function pullEvents(api: ApiClient, db: UserDb): Promise<number> {
  let since = (await db.getMeta<number>(SINCE_KEY)) ?? 0;
  let pulled = 0;
  for (;;) {
    const page = check(
      await api.GET('/api/v1/sync/events', { params: { query: { since, limit: BATCH } } }),
      'download',
    );
    const events = page.events.map(fromServer);
    await db.transaction('rw', db.events, db.meta, async () => {
      const known = new Set(
        (await db.events.bulkGet(events.map((e) => e.id))).filter(Boolean).map((e) => e!.id),
      );
      pulled += events.filter((e) => !known.has(e.id)).length;
      // Server copies win: they carry received_at and server_seq.
      await db.events.bulkPut(events);
      await db.setMeta(SINCE_KEY, page.next_since);
    });
    since = page.next_since;
    if (!page.more) break;
  }
  return pulled;
}

export async function localSettings(db: UserDb): Promise<Record<string, LocalSetting>> {
  return (await db.getMeta<Record<string, LocalSetting>>(SETTINGS_KEY)) ?? {};
}

/** Change a setting locally; it is sent with the next sync. */
export async function setSetting(db: UserDb, key: string, value: Json, now = Date.now()): Promise<void> {
  await db.transaction('rw', db.meta, async () => {
    const all = await localSettings(db);
    all[key] = { value, updatedAt: now, dirty: true };
    await db.setMeta(SETTINGS_KEY, all);
  });
}

export async function syncSettings(api: ApiClient, db: UserDb): Promise<number> {
  const remote = check(await api.GET('/api/v1/settings'), 'settings').map((s) => ({
    key: s.key,
    value: s.value as Json,
    updatedAt: Date.parse(s.updated_at),
  }));
  const { settings, push } = mergeSettings(await localSettings(db), remote);
  for (const key of push) {
    const s = settings[key];
    const winner = check(
      await api.PUT('/api/v1/settings/{key}', {
        params: { path: { key } },
        body: { value: s.value, updated_at: new Date(s.updatedAt).toISOString() },
      }),
      `setting ${key}`,
    );
    settings[key] = { value: winner.value as Json, updatedAt: Date.parse(winner.updated_at), dirty: false };
  }
  // Keep changes made while this sync was running.
  await db.transaction('rw', db.meta, async () => {
    const current = await localSettings(db);
    for (const [key, s] of Object.entries(current)) {
      if (s.dirty && s.updatedAt > (settings[key]?.updatedAt ?? -1)) settings[key] = s;
    }
    await db.setMeta(SETTINGS_KEY, settings);
  });
  return push.length;
}

/** Full sync: upload, download, settings. Throws on network or server errors. */
export async function syncAll(api: ApiClient, db: UserDb, now = Date.now()): Promise<SyncResult> {
  const { pushed, rejected } = await pushEvents(api, db);
  const pulled = await pullEvents(api, db);
  const settingsPushed = await syncSettings(api, db);
  await db.setMeta(LAST_SYNC_KEY, now);
  return { pushed, pulled, rejected, settingsPushed };
}

export async function lastSync(db: UserDb): Promise<number | undefined> {
  return db.getMeta<number>(LAST_SYNC_KEY);
}

export function unsyncedCount(db: UserDb): Promise<number> {
  return db.events.where('synced').equals(0).count();
}
