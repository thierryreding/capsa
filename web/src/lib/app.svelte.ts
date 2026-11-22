/**
 * Application state and actions (Svelte 5 runes). Offline-first: the app starts from
 * the last signed-in account and local data, and talks to the server in the background.
 */
import { createApiClient } from './api/client';
import { indexProfile, askable, type ProfileIndex } from './learning/cards';
import {
  applyAnswer,
  cardKey,
  computeStates,
  DEFAULT_INTERVALS_DAYS,
  type CardState,
  type LeitnerConfig,
} from './learning/leitner';
import type { Direction } from './learning/match';
import {
  answerCard,
  DEFAULT_SESSION_SIZE,
  isFinished,
  selectCards,
  startSession,
  type Card,
  type Selection,
  type Session,
} from './learning/session';
import {
  deviceId,
  eventsForProfile,
  lastUser,
  recordAnswer,
  setLastUser,
  UserDb,
  type Me,
  type Mode,
  type StoredProfile,
} from './store/db';
import { localProfiles, refreshProfiles } from './store/profiles';

export type View = 'loading' | 'login' | 'home' | 'quiz' | 'summary';
export type DirectionChoice = Direction | 'mixed';
export type QuizMode = Extract<Mode, 'typed' | 'flashcard'>;

export interface Prefs {
  units: string[] | null; // null: all units
  mode: QuizMode;
  direction: DirectionChoice;
  selection: Selection;
  lang: string | null; // null: the profile's required translation language
}

const DEFAULT_PREFS: Prefs = {
  units: null,
  mode: 'typed',
  direction: 'src_to_tr',
  selection: 'mixed',
  lang: null,
};

export function leitnerConfig(now = new Date()): LeitnerConfig {
  return { intervalsDays: DEFAULT_INTERVALS_DAYS, utcOffsetMinutes: -now.getTimezoneOffset() };
}

export class App {
  readonly api = createApiClient();

  view = $state<View>('loading');
  me = $state<Me | null>(null);
  online = $state(true);
  notice = $state<string | null>(null);

  profiles = $state<StoredProfile[]>([]);
  profileId = $state<string | null>(null);
  prefs = $state<Prefs>({ ...DEFAULT_PREFS });
  states = $state<Map<string, CardState>>(new Map());
  session = $state<Session | null>(null);

  #db: UserDb | null = null;
  #answering = false;
  #device = '';
  #allPrefs: Record<string, Prefs> = {};

  index = $derived.by((): ProfileIndex | null => {
    const p = this.profiles.find((x) => x.id === this.profileId);
    return p ? indexProfile(p.doc) : null;
  });

  lang = $derived(
    this.prefs.lang ?? this.index?.doc.profile.required_translation_lang ?? 'de',
  );

  /** Units to learn: the chosen ones, or all. */
  units = $derived(
    new Set(this.prefs.units ?? this.index?.doc.units.map((u) => u.id) ?? []),
  );

  directions = $derived<Direction[]>(
    this.prefs.direction === 'mixed' ? ['src_to_tr', 'tr_to_src'] : [this.prefs.direction],
  );

  async start(): Promise<void> {
    this.#device = await deviceId();
    const known = await lastUser();
    if (!known) {
      this.view = 'login';
      return;
    }
    await this.#enter(known);
    this.view = 'home'; // from local data at once; the server is asked in the background
    void this.#checkSession();
  }

  async login(username: string, password: string): Promise<string | null> {
    try {
      const r = await this.api.POST('/api/v1/auth/login', { body: { username, password } });
      if (r.response.status === 429) {
        const seconds = Number(r.response.headers.get('Retry-After') ?? '60');
        return 'rateLimited:' + Math.ceil(seconds / 60);
      }
      if (!r.data) return 'failed';
      this.online = true;
      await setLastUser(r.data);
      await this.#enter(r.data);
      await this.refresh(); // first sign-in: show home once the profiles are loaded
      this.view = 'home';
      return null;
    } catch {
      return 'offline';
    }
  }

  async logout(): Promise<void> {
    try {
      await this.api.POST('/api/v1/auth/logout');
    } catch {
      // offline: the session cookie expires on its own
    }
    await setLastUser(null);
    this.#db?.close();
    this.#db = null;
    this.me = null;
    this.profiles = [];
    this.profileId = null;
    this.view = 'login';
  }

  /** Fetch profile updates; keeps working with local copies when offline. */
  async refresh(): Promise<void> {
    if (!this.#db) return;
    try {
      await refreshProfiles(this.api, this.#db);
      this.online = true;
    } catch {
      this.online = false;
    }
    await this.#loadProfiles();
  }

  async selectProfile(id: string): Promise<void> {
    this.profileId = id;
    this.prefs = { ...DEFAULT_PREFS, ...this.#allPrefs[id] };
    await this.#db?.setMeta('profile', id);
    const events = this.#db ? await eventsForProfile(this.#db, id) : [];
    this.states = computeStates(events, leitnerConfig());
  }

  async setPrefs(change: Partial<Prefs>): Promise<void> {
    this.prefs = { ...this.prefs, ...change };
    if (this.profileId) {
      this.#allPrefs[this.profileId] = $state.snapshot(this.prefs);
      await this.#db?.setMeta('prefs', this.#allPrefs);
    }
  }

  /** The cards a session would get now. */
  plannedCards(): Card[] {
    const index = this.index;
    if (!index) return [];
    const lang = this.lang;
    return selectCards(this.states, {
      profileId: index.doc.profile.id,
      entries: index.refs.filter((r) => askable(index.entries.get(r.id)!, lang)),
      units: this.units,
      directions: this.directions,
      selection: this.prefs.selection,
      size: DEFAULT_SESSION_SIZE,
      now: Date.now(),
      config: leitnerConfig(),
    });
  }

  beginSession(): void {
    const cards = this.plannedCards();
    if (cards.length === 0) return;
    this.session = startSession(cards);
    this.view = 'quiz';
  }

  /** Store the answer as an event, update the box, advance the session.
   * Ignored while the previous answer is still being stored (e.g. a double tap). */
  async answer(correct: boolean, responseMs: number | null): Promise<void> {
    const session = this.session;
    const card = session?.queue[0];
    if (!session || !card || !this.#db || !this.profileId || this.#answering) return;
    this.#answering = true;
    try {
      await this.#store(session, card, correct, responseMs);
    } finally {
      this.#answering = false;
    }
  }

  async #store(session: Session, card: Card, correct: boolean, responseMs: number | null) {
    if (!this.#db || !this.profileId) return;
    const event = await recordAnswer(
      this.#db,
      {
        profileId: this.profileId,
        entryId: card.entryId,
        direction: card.direction,
        mode: this.prefs.mode,
        correct,
        responseMs,
      },
      this.#device,
    );
    const key = cardKey(this.profileId, card.entryId, card.direction);
    const next = new Map(this.states);
    next.set(key, applyAnswer(next.get(key), correct, event.ts, leitnerConfig()));
    this.states = next;
    this.session = answerCard(session, correct);
    if (isFinished(this.session)) this.view = 'summary';
  }

  quitSession(): void {
    this.view = this.session && this.session.results.length > 0 ? 'summary' : 'home';
  }

  goHome(): void {
    this.session = null;
    this.view = 'home';
  }

  async #enter(me: Me): Promise<void> {
    this.me = me;
    this.#db = new UserDb(me.id);
    this.#allPrefs = (await this.#db.getMeta<Record<string, Prefs>>('prefs')) ?? {};
    await this.#loadProfiles();
  }

  async #loadProfiles(): Promise<void> {
    if (!this.#db) return;
    this.profiles = await localProfiles(this.#db);
    const wanted = this.profileId ?? (await this.#db.getMeta<string>('profile'));
    const id = this.profiles.find((p) => p.id === wanted)?.id ?? this.profiles[0]?.id ?? null;
    if (id) await this.selectProfile(id);
    else this.profileId = null;
  }

  /** Background check: is the session still valid? Then refresh profiles. */
  async #checkSession(): Promise<void> {
    try {
      const r = await this.api.GET('/api/v1/me');
      if (r.response.status === 401) {
        this.notice = 'expired';
        await setLastUser(null);
        this.view = 'login';
        return;
      }
      if (r.data) {
        this.me = r.data;
        await setLastUser(r.data);
      }
      await this.refresh();
    } catch {
      this.online = false;
    }
  }
}
