/** Keep local copies of the profiles released to the account up to date (ETag). */
import { ApiError, type ApiClient, type ProfileDocument, type Schemas } from '../api/client';
import type { StoredProfile, UserDb } from './db';

export interface RefreshResult {
  updated: string[];
  removed: string[];
}

/**
 * Fetch the profile list; download profiles whose ETag changed; delete local copies
 * of profiles that are no longer released (their content must not stay on the device).
 * Throws on network errors, so callers can keep working with the local copies offline.
 */
export async function refreshProfiles(
  api: ApiClient,
  db: UserDb,
  now: number = Date.now(),
): Promise<RefreshResult> {
  const list = await api.GET('/api/v1/profiles');
  if (!list.data) throw new ApiError('profile list failed', list.response.status);
  const summaries: Schemas['ProfileSummary'][] = list.data;

  const local = new Map((await db.profiles.toArray()).map((p) => [p.id, p]));
  const updated: string[] = [];
  for (const s of summaries) {
    const have = local.get(s.id);
    if (have?.etag === s.etag) continue;
    const r = await api.GET('/api/v1/profiles/{profile_id}', {
      params: { path: { profile_id: s.id } },
      headers: have ? { 'If-None-Match': have.etag } : {},
      parseAs: 'text',
    });
    if (r.response.status === 304) continue;
    if (!r.response.ok || typeof r.data !== 'string') {
      throw new ApiError(`profile ${s.id} failed`, r.response.status);
    }
    const doc = JSON.parse(r.data) as ProfileDocument;
    const etag = r.response.headers.get('ETag') ?? s.etag;
    await db.profiles.put({ id: s.id, etag, doc, fetchedAt: now });
    updated.push(s.id);
  }

  const released = new Set(summaries.map((s) => s.id));
  const removed = [...local.keys()].filter((id) => !released.has(id));
  if (removed.length) await db.profiles.bulkDelete(removed);
  return { updated, removed };
}

export async function localProfiles(db: UserDb): Promise<StoredProfile[]> {
  return (await db.profiles.toArray()).sort((a, b) =>
    a.doc.profile.title.localeCompare(b.doc.profile.title),
  );
}
