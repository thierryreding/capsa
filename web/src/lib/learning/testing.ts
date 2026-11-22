// Test helpers: load profiles and vectors from the repository. Only used by tests.
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse } from 'yaml';
import type { MatchEntry, MatchingConfig } from './match';

export const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '../../../..');

export interface ProfileDoc {
  profile: {
    id: string;
    source_lang: string;
    required_translation_lang: string;
    translation_langs: string[];
    matching?: MatchingConfig;
  };
  units: { id: string; entries: (MatchEntry & { id: string; deprecated?: boolean })[] }[];
}

export function loadProfile(path: string): ProfileDoc {
  return parse(readFileSync(resolve(REPO, path), 'utf-8')) as ProfileDoc;
}

export function loadJson<T>(path: string): T {
  return JSON.parse(readFileSync(resolve(REPO, path), 'utf-8')) as T;
}

export function entriesById(doc: ProfileDoc): Map<string, MatchEntry> {
  return new Map(doc.units.flatMap((u) => u.entries.map((e) => [e.id, e] as const)));
}

export function privateProfilePaths(): string[] {
  const dir = join(REPO, 'profiles', 'private');
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter((f) => f.endsWith('.yaml'))
    .map((f) => join(dir, f));
}
