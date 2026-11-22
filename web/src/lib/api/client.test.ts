import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { createApiClient, CSRF_HEADER, type Schemas } from './client';

const WEB = resolve(import.meta.dirname, '../../..');

function recordingFetch(body: unknown, status = 200) {
  const requests: Request[] = [];
  const fetch = async (input: Request) => {
    requests.push(input);
    return new Response(JSON.stringify(body), {
      status,
      headers: { 'Content-Type': 'application/json' },
    });
  };
  return { requests, fetch: fetch as unknown as typeof globalThis.fetch };
}

describe('createApiClient', () => {
  it('adds the CSRF header to state-changing requests only', async () => {
    const me: Schemas['Me'] = { id: 'x', username: 'lena', role: 'learner' };
    const { requests, fetch } = recordingFetch(me);
    const api = createApiClient({ baseUrl: 'https://capsa.test', fetch });

    const login = await api.POST('/api/v1/auth/login', {
      body: { username: 'lena', password: 'geheim123' },
    });
    expect(login.data?.username).toBe('lena');
    await api.GET('/api/v1/me');

    expect(requests.map((r) => [r.method, r.url, r.headers.get(CSRF_HEADER)])).toEqual([
      ['POST', 'https://capsa.test/api/v1/auth/login', '1'],
      ['GET', 'https://capsa.test/api/v1/me', null],
    ]);
  });

  it('fills path and query parameters', async () => {
    const { requests, fetch } = recordingFetch({ events: [], next_since: 7, more: false });
    const api = createApiClient({ baseUrl: 'https://capsa.test', fetch });
    await api.GET('/api/v1/sync/events', { params: { query: { since: 7, limit: 100 } } });
    await api.GET('/api/v1/profiles/{profile_id}', { params: { path: { profile_id: 'demo-latin' } } });
    expect(new URL(requests[0].url).search).toBe('?since=7&limit=100');
    expect(requests[1].url).toMatch(/\/api\/v1\/profiles\/demo-latin$/);
  });
});

describe('generated types', () => {
  // Fails when schemas/*.json changed without `npm run gen`.
  const out = mkdtempSync(join(tmpdir(), 'capsa-gen-'));
  const bin = (name: string) => join(WEB, 'node_modules', '.bin', name);

  it('schema.d.ts matches schemas/openapi.json', () => {
    const target = join(out, 'schema.d.ts');
    execFileSync(bin('openapi-typescript'), ['../schemas/openapi.json', '-o', target], {
      cwd: WEB,
      stdio: 'ignore',
    });
    expect(readFileSync(target, 'utf-8')).toBe(
      readFileSync(join(WEB, 'src/lib/api/schema.d.ts'), 'utf-8'),
    );
  });

  it('profile.d.ts matches schemas/profile.schema.json', () => {
    const target = join(out, 'profile.d.ts');
    execFileSync(
      bin('json2ts'),
      ['-i', '../schemas/profile.schema.json', '-o', target, '--no-additionalProperties'],
      { cwd: WEB, stdio: 'ignore' },
    );
    expect(readFileSync(target, 'utf-8')).toBe(
      readFileSync(join(WEB, 'src/lib/api/profile.d.ts'), 'utf-8'),
    );
  });
});
