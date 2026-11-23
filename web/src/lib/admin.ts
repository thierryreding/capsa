/**
 * Account management for admins (parents) over the admin API (SPEC 5). Needs the
 * server; errors come back as German messages for the UI.
 */
import type { ApiClient, Schemas } from './api/client';
import { t, type MessageKey } from './i18n';

export type UserInfo = Schemas['UserInfo'];
export type UserCreate = Schemas['UserCreate'];
export type UserUpdate = Schemas['UserUpdate'];
export type ProfileSummary = Schemas['ProfileSummary'];

export const PASSWORD_MIN = 8;
const USERNAME = /^[\p{L}\p{N}_.-]{1,64}$/u;

export type Result<T> = { ok: true; value: T } | { ok: false; error: string };

/** Checks before sending; the server checks again. */
export function checkNewUser(u: { username: string; password: string }): string | null {
  if (!USERNAME.test(u.username)) return t('admin.error.username');
  return checkPassword(u.password);
}

export function checkPassword(password: string): string | null {
  return [...password].length < PASSWORD_MIN ? t('admin.error.password') : null;
}

/** German message for a server answer (the server's texts are English). */
export function errorMessage(status: number | null, detail?: unknown): string {
  if (status === null) return t('admin.error.offline');
  const text = typeof detail === 'string' ? detail : '';
  const known: [string, MessageKey][] = [
    ['taken', 'admin.error.taken'],
    ['username', 'admin.error.username'],
    ['password', 'admin.error.password'],
    ['display name', 'admin.error.name'],
    ['own account', 'admin.error.self'],
    ['unknown profiles', 'admin.error.profiles'],
  ];
  for (const [needle, key] of known) if (text.includes(needle)) return t(key);
  if (status === 401) return t('login.expired');
  if (status === 403) return t('admin.error.forbidden');
  return t('admin.error.generic');
}

async function call<T>(
  request: () => Promise<{ data?: T; error?: unknown; response: Response }>,
): Promise<Result<T>> {
  try {
    const r = await request();
    if (r.data !== undefined) return { ok: true, value: r.data };
    const detail = (r.error as { detail?: unknown } | undefined)?.detail;
    return { ok: false, error: errorMessage(r.response.status, detail) };
  } catch {
    return { ok: false, error: errorMessage(null) };
  }
}

export function listUsers(api: ApiClient): Promise<Result<UserInfo[]>> {
  return call(() => api.GET('/api/v1/admin/users'));
}

export function listProfiles(api: ApiClient): Promise<Result<ProfileSummary[]>> {
  return call(() => api.GET('/api/v1/profiles'));
}

export function createUser(api: ApiClient, body: UserCreate): Promise<Result<UserInfo>> {
  return call(() => api.POST('/api/v1/admin/users', { body }));
}

export function updateUser(
  api: ApiClient,
  id: string,
  body: UserUpdate,
): Promise<Result<UserInfo>> {
  return call(() =>
    api.PATCH('/api/v1/admin/users/{user_id}', { params: { path: { user_id: id } }, body }),
  );
}
