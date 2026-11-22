/**
 * Local storage in IndexedDB (Dexie). The local store is the source of truth for
 * progress (SPEC 3); the server is the sync target.
 *
 * - One database per account (`capsa-<user id>`), so several children can share a
 *   device without mixing progress.
 * - One device-wide database (`capsa-device`) for the device id and the last
 *   signed-in account (to start offline).
 */
import Dexie, { type Table } from 'dexie';
import type { ProfileDocument, Schemas } from '../api/client';
import type { AnswerEvent } from '../learning/leitner';
import type { Direction } from '../learning/match';
import { uuidv7 } from '../learning/uuid';

export type Mode = Schemas['Event']['mode'];
export type Me = Schemas['Me'];

export interface StoredProfile {
  id: string;
  etag: string;
  doc: ProfileDocument;
  fetchedAt: number;
}

export interface LocalEvent extends AnswerEvent {
  device_id: string;
  mode: Mode;
  response_ms: number | null;
  received_at: number | null;
  server_seq: number | null;
  /** 0 = not yet uploaded, 1 = on the server (numbers, so Dexie can index it). */
  synced: 0 | 1;
  /** Why the server refused the event, if it did; such events are not retried. */
  rejected: string | null;
}

interface MetaRow {
  key: string;
  value: unknown;
}

export class UserDb extends Dexie {
  profiles!: Table<StoredProfile, string>;
  events!: Table<LocalEvent, string>;
  meta!: Table<MetaRow, string>;

  constructor(userId: string) {
    super(`capsa-${userId}`);
    this.version(1).stores({
      profiles: 'id',
      events: 'id, profile_id, synced',
      meta: 'key',
    });
  }

  async getMeta<T>(key: string): Promise<T | undefined> {
    return (await this.meta.get(key))?.value as T | undefined;
  }

  async setMeta(key: string, value: unknown): Promise<void> {
    await this.meta.put({ key, value });
  }
}

class DeviceDb extends Dexie {
  meta!: Table<MetaRow, string>;

  constructor() {
    super('capsa-device');
    this.version(1).stores({ meta: 'key' });
  }
}

let device: DeviceDb | undefined;
const deviceDb = () => (device ??= new DeviceDb());

/** Stable random id of this browser installation. */
export async function deviceId(): Promise<string> {
  const db = deviceDb();
  return db.transaction('rw', db.meta, async () => {
    const found = (await db.meta.get('device_id'))?.value as string | undefined;
    if (found) return found;
    const id = uuidv7().replaceAll('-', '');
    await db.meta.put({ key: 'device_id', value: id });
    return id;
  });
}

/** The last signed-in account, so the app can start without a network. */
export async function lastUser(): Promise<Me | undefined> {
  return (await deviceDb().meta.get('last_user'))?.value as Me | undefined;
}

export async function setLastUser(me: Me | null): Promise<void> {
  if (me) await deviceDb().meta.put({ key: 'last_user', value: me });
  else await deviceDb().meta.delete('last_user');
}

export interface Answer {
  profileId: string;
  entryId: string;
  direction: Direction;
  mode: Mode;
  correct: boolean;
  responseMs: number | null;
}

export async function recordAnswer(
  db: UserDb,
  answer: Answer,
  device: string,
  now: number = Date.now(),
): Promise<LocalEvent> {
  const event: LocalEvent = {
    id: uuidv7(now),
    device_id: device,
    profile_id: answer.profileId,
    entry_id: answer.entryId,
    direction: answer.direction,
    mode: answer.mode,
    correct: answer.correct,
    response_ms: answer.responseMs,
    ts: now,
    received_at: null,
    server_seq: null,
    synced: 0,
    rejected: null,
  };
  await db.events.add(event);
  return event;
}

export function eventsForProfile(db: UserDb, profileId: string): Promise<LocalEvent[]> {
  return db.events.where('profile_id').equals(profileId).toArray();
}
