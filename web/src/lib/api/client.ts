/**
 * Typed client for the Capsa API. Types are generated from schemas/openapi.json
 * (`npm run gen`); never edit schema.d.ts or profile.d.ts by hand.
 */
import createClient from 'openapi-fetch';
import type { components, paths } from './schema';

export type {
  CapsaVocabularyProfile as ProfileDocument,
  Entry,
  Example,
  Note,
  Table,
  Unit,
} from './profile';
export type Schemas = components['schemas'];
export type ApiClient = ReturnType<typeof createApiClient>;

/** A request the server answered with an error status (`status`), as opposed to a
 * network failure (a TypeError from fetch). 401 means the session has ended. */
export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

/** Sent on every state-changing request; the server refuses them without it. */
export const CSRF_HEADER = 'X-Capsa-CSRF';
const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

export function createApiClient(options: { baseUrl?: string; fetch?: typeof fetch } = {}) {
  const client = createClient<paths>({
    baseUrl: options.baseUrl ?? '',
    credentials: 'same-origin', // the session cookie lives on /api of the same origin
    fetch: options.fetch,
  });
  client.use({
    onRequest({ request }) {
      if (!SAFE_METHODS.has(request.method)) request.headers.set(CSRF_HEADER, '1');
      return request;
    },
  });
  return client;
}
