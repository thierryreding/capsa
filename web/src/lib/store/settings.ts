/**
 * Synced settings, last write wins by `updatedAt` (SPEC 6). The merge is a pure function;
 * on equal timestamps the server's value stays, as the server decides it too.
 */

export type Json = string | number | boolean | null | Json[] | { [key: string]: Json };

export interface LocalSetting {
  value: Json;
  /** Time of the change (ms since epoch). */
  updatedAt: number;
  /** Changed locally and not yet confirmed by the server. */
  dirty: boolean;
}

export interface RemoteSetting {
  key: string;
  value: Json;
  updatedAt: number;
}

export interface MergeResult {
  settings: Record<string, LocalSetting>;
  /** Keys whose local value has to be sent to the server. */
  push: string[];
}

export function mergeSettings(
  local: Readonly<Record<string, LocalSetting>>,
  remote: readonly RemoteSetting[],
): MergeResult {
  const settings: Record<string, LocalSetting> = { ...local };
  for (const r of remote) {
    const mine = local[r.key];
    if (!mine || r.updatedAt >= mine.updatedAt) {
      settings[r.key] = { value: r.value, updatedAt: r.updatedAt, dirty: false };
    }
  }
  // Whatever is still dirty is newer than the server's value (or unknown to it).
  const push = Object.keys(settings).filter((k) => settings[k].dirty);
  return { settings, push };
}
