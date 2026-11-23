/**
 * Application state and actions (Svelte 5 runes). Offline-first: the app starts from
 * the last signed-in account and local data, and talks to the server in the background.
 */
import { ApiError, createApiClient } from './api/client';
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
import { requestPersistentStorage } from './platform';
import { localProfiles, refreshProfiles } from './store/profiles';
import type { Json } from './store/settings';
import {
  lastSync,
  localSettings,
  setSetting,
  syncAll,
  unsyncedCount,
} from './store/sync';

/** Setting key of the display name (validated by the server). */
export const DISPLAY_NAME = 'display_name';

export type View = 'loading' | 'login' | 'home' | 'quiz' | 'summary' | 'admin';
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

  /** A new app version is waiting; offered in the overview, applied by reloading. */
  updateAvailable = $state(false);
  applyUpdate: () => void = () => location.reload();

  /** Sync status for the overview. */
  syncing = $state(false);
  lastSyncAt = $state<number | null>(null);
  unsynced = $state(0);

  #db: UserDb | null = null;
  #answering = false;
  #device = '';
  #allPrefs: Record<string, Prefs> = {};
  #refreshing: Promise<void> | null = null;
  #prefsTimer: ReturnType<typeof setTimeout> | undefined;

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

  /**
   * Change the own display name (null clears it). Needs the server; returns null on
   * success, otherwise 'invalid' or 'offline'.
   */
  /** Change the own display name: a synced setting, so it also works offline. */
  async setDisplayName(name: string | null): Promise<void> {
    if (!this.#db || !this.me) return;
    await setSetting(this.#db, DISPLAY_NAME, name);
    this.me = { ...this.me, display_name: name };
    await setLastUser($state.snapshot(this.me)); // so the name also shows on an offline start
    void this.refresh();
  }

  /** Take account settings (the display name) from the merged local settings. */
  async #applyAccountSettings(db: UserDb): Promise<void> {
    const setting = (await localSettings(db))[DISPLAY_NAME];
    if (!setting || !this.me) return;
    const name = (setting.value as string | null) ?? null;
    if (name === (this.me.display_name ?? null)) return;
    this.me = { ...this.me, display_name: name };
    await setLastUser($state.snapshot(this.me));
  }


  async logout(): Promise<void> {
    // Upload pending answers first; otherwise they would wait on this device until
    // the same account signs in here again.
    await this.refresh();
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

  /**
   * Talk to the server: profile updates, then events and settings (SPEC 6, 9).
   * Keeps working with local data when offline. Only one refresh runs at a time.
   */
  refresh(): Promise<void> {
    this.#refreshing ??= this.#refresh().finally(() => (this.#refreshing = null));
    return this.#refreshing;
  }

  async #refresh(): Promise<void> {
    const db = this.#db;
    if (!db) return;
    this.syncing = true;
    try {
      await refreshProfiles(this.api, db);
      await syncAll(this.api, db);
      this.online = true;
    } catch (error) {
      this.online = false;
      if (error instanceof ApiError && error.status === 401) await this.#expired();
    } finally {
      this.syncing = false;
    }
    if (this.#db !== db) return; // signed out meanwhile
    this.#allPrefs = await this.#loadPrefs(db);
    await this.#applyAccountSettings(db);
    await this.#loadProfiles();
    await this.#loadSyncStatus(db);
  }

  async selectProfile(id: string): Promise<void> {
    this.profileId = id;
    this.prefs = { ...DEFAULT_PREFS, ...this.#allPrefs[id] };
    await this.#db?.setMeta('profile', id);
    const events = this.#db ? await eventsForProfile(this.#db, id) : [];
    this.states = computeStates(events, leitnerConfig());
  }

  /** Change learning choices; they are synced as the setting `prefs.<profile>`. */
  async setPrefs(change: Partial<Prefs>): Promise<void> {
    this.prefs = { ...this.prefs, ...change };
    if (!this.profileId || !this.#db) return;
    const snapshot = $state.snapshot(this.prefs) as Prefs;
    this.#allPrefs[this.profileId] = snapshot;
    await setSetting(this.#db, `prefs.${this.profileId}`, snapshot as unknown as Json);
    // Several quick changes, one sync.
    clearTimeout(this.#prefsTimer);
    this.#prefsTimer = setTimeout(() => void this.refresh(), 2000);
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
    this.unsynced++;
    this.session = answerCard(session, correct);
    if (isFinished(this.session)) {
      this.view = 'summary';
      void this.refresh();
    }
  }

  quitSession(): void {
    const answered = this.session !== null && this.session.results.length > 0;
    this.view = answered ? 'summary' : 'home';
    if (answered) void this.refresh();
  }

  openAdmin(): void {
    if (this.me?.role === 'admin') this.view = 'admin';
  }

  goHome(): void {
    this.session = null;
    this.view = 'home';
  }

  async #enter(me: Me): Promise<void> {
    this.me = me;
    void requestPersistentStorage();
    this.#db = new UserDb(me.id);
    await this.#applyAccountSettings(this.#db);
    this.#allPrefs = await this.#loadPrefs(this.#db);
    await this.#loadProfiles();
    await this.#loadSyncStatus(this.#db);
  }

  async #loadPrefs(db: UserDb): Promise<Record<string, Prefs>> {
    const prefs: Record<string, Prefs> = {};
    for (const [key, setting] of Object.entries(await localSettings(db))) {
      if (key.startsWith('prefs.')) prefs[key.slice(6)] = setting.value as unknown as Prefs;
    }
    return prefs;
  }

  async #loadSyncStatus(db: UserDb): Promise<void> {
    this.unsynced = await unsyncedCount(db);
    this.lastSyncAt = (await lastSync(db)) ?? null;
  }

  async #expired(): Promise<void> {
    this.notice = 'expired';
    await setLastUser(null);
    this.view = 'login';
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
        await this.#expired();
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
