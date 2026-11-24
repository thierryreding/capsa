# Capsa: Specification (Draft 1)

Capsa is the project name (Latin for a container for scrolls, fitting for a Leitner box). CLI name: `capsa`, repository: `capsa`.

Status: M0 to M5 done. This document is meant as the working basis for Claude Code.
Attached: `profiles/private/latein-lehrbuch.yaml` (first profile: Latin, "Salve" + units 1-4, 139 entries).

## 1. Goal

A self-hosted vocabulary trainer that parents and children use to quiz vocabulary from textbooks, unit by unit.
Children should also be able to use it on their own, including offline (school, holidays).
Languages and textbooks are modelled as interchangeable **profiles**; nothing is hard-wired to Latin or German.

### Non-goals (v1)
- No public operation, no self-registration.
- No speech recognition, no OCR (profiles are created by hand or via import).
- No native app. The web app is installed as a PWA.
- No multi-tenancy. Nothing should be built that rules it out later, though (see 11).

## 2. Requirements

**Content**
- F1: Profiles with units and entries, a near-complete copy of the textbook pages (loanwords, example sentences, notes, review lists, tables).
- F2: Extra information is secondary and sits behind an info icon (ⓘ), not in the main layout.
- F3: Exactly one translation language is mandatory per profile (`required_translation_lang`); further ones are optional per entry.
- F4: Arbitrary language pairs, e.g. Latin-German or Latin-French.

**Learning**
- F5: Quiz modes: flashcard, typed answer, multiple choice, parent mode (the parent sees the solution and marks right/wrong).
- F6: Directions: source language→translation, translation→source language, mixed.
- F7: Selection by unit, by "due", by "mistakes only".
- F8: Review schedule with Leitner boxes. Optionally a test date the app plans towards.
- F9: Progress visible per unit and user.

**Operation**
- F10: Works offline after the first load. Progress is synced when a connection is available.
- F11: Accounts with login (parents create accounts), progress per account.
- F12: Runs on the home server, HTTPS with a subdomain and a Let's Encrypt certificate.

## 3. Architecture

```
 Browser/PWA (TypeScript)                  Home server
┌───────────────────────────┐        ┌─────────────────────────┐
│ UI + quiz logic           │        │ Traefik (HTTPS)         │
│ Service worker (cache)    │◄─────► │ API (Python/FastAPI)    │
│ IndexedDB:                │  HTTPS │ SQLite (accounts,events)│
│  - profiles (copy)        │        │ Profiles as YAML files  │
│  - events + learning state│        └─────────────────────────┘
└───────────────────────────┘
```

- **API:** serves profiles (read-only), manages accounts and accepts learning events. The contract is an OpenAPI schema from which the TypeScript client is generated.
- **Frontend:** PWA, offline-first. The source of truth for progress is local; the server is the sync target and backup.
- **Stack:** frontend **Svelte** (decided) with TypeScript and Vite as a single-page app, Dexie (IndexedDB), vite-plugin-pwa (Workbox). SvelteKit only with `adapter-static`, no server-side rendering, so the app stays fully offline-first. Backend suggestion: Python 3.12 + FastAPI + Pydantic + SQLite (WAL). A move to PostgreSQL is planned at some point (see 13), so database access stays behind a small storage layer with portable SQL and migrations, and nothing relies on SQLite-only features. Tests: pytest, Vitest, Playwright for the offline path.
- **Target platforms:** iOS (Safari, as a home-screen app) and Android (Chrome). Both are equally important and covered by tests.
- **Why PWA instead of Flutter:** no app store or TestFlight distribution, one codebase for all devices. The API is shaped so that a native client remains possible later.

## 4. Profile format

The reference is the file `profiles/private/latein-lehrbuch.yaml`. A JSON Schema (`schemas/profile.schema.json`) is derived from it and is the authoritative definition.

```
Profile
  id, title, source_lang, required_translation_lang, translation_langs[], note_langs[],
  revision (int, increase on every change), book{title,publisher,isbn,pages},
  rights{content, distribution}, matching{ignore_diacritics, strip_prefixes{lang:[..]}, optional_articles{lang:[..]}, optional_words{lang:[..]}}
Unit            id, number, title, book_ref, review[entry-id], notes[], tables[], entries[]
Entry           id (stable!), lemma, info, tr{lang:[meaning..]}, loanwords{lang:[..]},
                examples[{la,de,..}], notes[], refs[], pos?, gender?
Note            kind (usage|grammar|culture), text, refs[], marker?
Table           id, title, intro?, columns[], rows[][]
```

Rules:
- **Entry IDs are stable.** They never change, not even for corrections, because learning events point to them. Deleted entries are marked `deprecated: true`, not removed.
- `info` is the second book column, unchanged (gender, accusative, 3rd person singular, etc.). `pos` and `gender` are optional and can later be derived from `info` by a script.
- `tr[lang]` is a list of individual meanings. For display, join them with ", ".
- `review` only references entries from earlier units.
- Exercises and reading texts from the book pages are deliberately not part of the profile.
- Example sentences carry one translation per language under the language code (`de`, `fr`, ...).

**Tooling (CLI `capsa`)**
- `capsa validate <profile>`: schema, unique IDs, review references, mandatory translation present, review entries come from earlier units. A prototype of these checks is included as `tools/check_profile.py`.
- `import-csv`: simple import (columns `unit;lemma;info;translation`) for quickly creating new profiles.
- `lint`: warnings, e.g. missing macron variant, duplicate lemmata.

## 5. API draft (v1, everything under `/api/v1`)

| Method | Path | Purpose |
|---|---|---|
| POST | `/auth/login`, `/auth/logout` | Sign in with username and password |
| GET | `/health` | Liveness check (no login) |
| GET | `/me` | Own account |
| PUT | `/me/password` | Change own password (signs out other sessions) |
| GET | `/profiles` | List of profiles released to me, with `revision` and ETag |
| GET | `/profiles/{id}` | Full profile as JSON, with ETag / `If-None-Match` |
| POST | `/sync/events` | Upload a batch of learning events (idempotent) |
| GET | `/sync/events?since={seq}` | Fetch events from other devices |
| GET | `/settings` | All own settings |
| GET/PUT | `/settings/{key}` | Settings, last-write-wins (e.g. test date, selected units) |
| POST/GET | `/admin/users` | Create and list accounts (admin only) |
| PATCH | `/admin/users/{id}` | Release profiles, reset password, disable (admin only) |

The authoritative description is `schemas/openapi.json` (generated by `capsa openapi`). All state-changing requests need the header `X-Capsa-CSRF: 1`. Profiles are released to learner accounts by an admin; admins see all profiles.

## 6. Sync protocol

Goal: no merge conflicts, full offline functionality.

- Every answer is an **immutable event**: `{id (UUIDv7, generated by the client), device_id, profile_id, entry_id, direction, mode, correct, response_ms, ts}`.
- The server stores events idempotently (primary key `id`) and assigns an ascending `server_seq`.
- The client fetches events from other devices with `since=<last seq>` and merges them into its local store.
- The **learning state** (box, next due date) is computed deterministically from the events, ordered by `(ts, id)`. The same pure function runs in the client and (for statistics) on the server. This makes all devices converge.
- Settings are simple key-value pairs with `updated_at` (last-write-wins). They are not events; a device changes them offline and uploads them at the next sync. Keys the server understands are validated; so far only `display_name` (1-64 characters). An admin's change of such a setting is written at server time (or just after the stored change) so it wins over what is stored; later device changes win again. If the server refuses a value, the device takes the server's value instead of retrying.
- Profiles are refreshed via ETag/`revision` and stored completely in IndexedDB. A profile update never changes IDs, so progress stays valid.
- Clock skew: the client does not correct `ts`; the server additionally stores `received_at`. The Leitner computation uses `ts`, but if it lies clearly in the future (> 1 day), `received_at` is used instead.
- Client implementation (M3): upload in batches of 500; accepted and duplicate events are marked synced, rejected ones are marked with their reason and not retried. Download pages by `server_seq` and stores the server copies (which gives own events their `received_at`). Every step is idempotent, an interrupted sync is simply repeated. The learner's choices in the overview (units, mode, direction, language, selection) are the setting `prefs.<profile id>`. Sync runs at start, on returning to the foreground, after a session, on the `online` event and before signing out.

## 7. Learning logic

**Leitner with 5 boxes.** Correct: one box up. Wrong: back to box 1.
Initial intervals: box 1 = same session, 2 = 1 day, 3 = 3 days, 4 = 7 days, 5 = 21 days. The values are configurable.
State is kept separately per user, entry and direction.
Decided details: a card never answered is "new" and starts in box 1. Intervals count local calendar days, not 24-hour periods (an evening answer is due the next morning). Test vectors: `vectors/leitner.json`.

**Session:** default 10 cards, mixes due entries and mistakes. Decided details: the default selection takes mistakes first, then due cards (lower box and older first), then new cards, and shuffles them; "due only", "mistakes only" and "all" are alternatives. A wrong card comes back three cards later in the same session, at most twice. Each direction is a separate card. Locally, every account has its own IndexedDB database, so several children can share a device.
**Test date:** if a date is set, the selected units are distributed so that every entry has been answered correctly at least twice by then (simple heuristic, refine later).

**Answer checking (typed answers)**
1. Normalise: Unicode NFD, strip combining marks (macron, breve) if `ignore_diacritics`, `casefold`, trim, collapse repeated whitespace.
2. Accepted answers come from the entries in `tr[lang]`. Parenthetical additions are optional ("da (zeitlich)" also accepts "da", "sieh(e)" accepts "sieh" and "siehe"). Ellipses and sentence punctuation at either end are ignored.
3. Prefixes from `strip_prefixes` are optional ("erwartet" instead of "er/sie/es erwartet"). Articles from `optional_articles` are optional. Both are written without a trailing space and match only at a word boundary ("die" never strips "dieser"; a prefix ending in an apostrophe such as French "l'" needs no space). Words from `optional_words` (placeholders such as "etw.", "jdn.") may be left out anywhere.
3a. Slash alternatives within a word: each part or the whole is accepted ("ich/mich" accepts "ich", "mich", "ich/mich"; "er/sie/es ist" also accepts "sie ist"). Same for the lemma ("ego/mē").
3b. Several meanings typed with "," or ";" must all be acceptable; the weakest verdict counts.
4. One correct meaning is enough (default). An "name all meanings" switch can follow later.
5. Almost correct (Levenshtein distance 1, only for words of 6 characters or more) is flagged as "almost"; the user decides.
6. Direction translation→Latin: macrons are optional, the form in `lemma` is compared. For verbs the form in `info` is accepted as well. As long as `pos` is not filled in, `info` counts as a (comma-separated) list of forms if it contains no "." and no "+" (so "m.", "Adv.", "+ Akk.", "canem m." are excluded). An explicit `pos` overrides this heuristic.

These rules must be secured with **tests drawn from the real profile** (table cases, German translations as in the profile: `er/sie/es ist; es gibt`, `sieh(e)!`, `nicht dürfen`).

## 8. Authentication and accounts

- Local accounts, created by the admin, no registration. Roles: `admin` (parents), `learner`.
- Passwords with argon2id. Login via a server-side session with an httpOnly cookie (`SameSite=Strict`, `Secure`), 90 days sliding, because the session has to survive offline periods. Additionally a custom header against CSRF.
- Rate limiting on `/auth/login`.
- The auth layer sits behind an interface so that OIDC (e.g. school SSO) is possible later.
- Profile content is only retrievable by signed-in users (rights, see 10).

## 9. Deployment (home server)

- Compose (decided: `podman compose`, a move to Quadlet/systemd is possible later): `api` (Uvicorn) and `web` (static files, nginx) containers behind the existing **Traefik** reverse proxy on the home server, discovered via container labels; no published ports. `/api` goes to the API, everything else to the web app. TLS uses the existing wildcard certificate (routers set `tls=true`; an ACME resolver can be added by label). Domain (e.g. `capsa.example.org`), Traefik entrypoint and network, profile folder and an instance name are configuration (`deploy/production/.env`), so the project can be deployed elsewhere.
- HTTPS is mandatory (service workers). The subdomain resolves to the internal address on the home network (split DNS).
- Data: SQLite file in a named volume, profile folder as a read-only bind mount. Nightly backup with `capsa db backup` (SQLite online backup API, keeps 14 copies), run by a systemd user timer.
- **Versions:** calendar based: `YYYY.MM` for the first release of a month (e.g. `2026.11`), then `YYYY.MM.1`, `YYYY.MM.2` and so on. The single source is the file `VERSION` at the repository root: the Python package reads it as its version (hatchling), the web app at build time (Vite), so both images are built from the repository root. The API reports the version in `/api/v1/health`, the app in its footer. A release is a commit tagged `vYYYY.MM[.N]`; `CAPSA_VERSION` in `.env` tags the built images.
- **Local test environment:** containers are managed with **podman**. `deploy/local/` defines a pod (`podman kube play`) with Traefik in front of the API, so the proxy setup can be tested on a development machine. It is not the production configuration.
- **Offline use:** the app is opened once on the home network (or via VPN) and added to the home screen. After that it runs without a network; sync happens the next time a connection is available.
- iOS: use only as an installed home-screen app, because Safari deletes data of non-installed websites after long periods of inactivity. On start the app shows a warning if it is not running installed and the last sync is more than 5 days ago.
- A VPN is optional. Sync also works at home only.
- **Platform differences:**
  - Safari on iOS has no Background Sync API. Sync therefore runs at app start, when returning to the foreground (`visibilitychange`) and after a learning session, not in the background.
  - Android/Chrome: request `navigator.storage.persist()` so the browser does not evict the data. On iOS, home-screen mode is what matters.
  - Install help in the app: on iOS instructions for "Share → Add to Home Screen", on Android the install prompt (`beforeinstallprompt`).
  - Test matrix: iOS Safari (installed, airplane mode), Android Chrome (installed, airplane mode), desktop Chrome/Firefox for development.

## 10. Legal and licensing

(Not legal advice.)
- The profile contains book content (selection, arrangement, example sentences) and is protected. It is for private use within the family.
- The folder `profiles/private/` is not part of the Git repository (`.gitignore`) or lives in a separate private repository. The server only delivers profiles to signed-in users.
- The software can be open. Suggestion: **AGPL-3.0**, because network use also triggers the obligation to publish modifications.
- Tests and examples use a demo profile of our own with self-written words and sentences, no book content.
- The profile format is self-contained and can also be used without book content (own lists, other languages, domain vocabulary).

## 11. Possible later opening for schools

Use in a school requires clarification with the publishers (licence for the content) and data protection (children's data, GDPR). Cheap preparations to make now:
- User IDs as UUIDs, accounts without a real-name requirement (pseudonyms possible).
- Profiles carry rights metadata (`rights`) and an access rule per profile. The access check runs centrally, not scattered across endpoints.
- Data-model reserve: nullable `tenant_id` on accounts and events. Do not build it out until needed.
- Auth through an OIDC-capable interface (see 8).
- Later: `teacher` role, classes, test date per class, deletion concept, data processing agreements, hosting in the EU, parental consent.

## 12. Milestones

1. **M0 Foundations:** repository, licence, JSON Schema, `capsa validate`, demo profile, tests from the real profile for answer checking.
2. **M1 API:** accounts and login, serve profiles, accept events. Generate the OpenAPI client.
3. **M2 Local frontend:** login, load profile, flashcards and typed answers, Leitner state in IndexedDB, info icon.
4. **M3 Sync:** event upload and download, settings, tests with two simulated devices.
5. **M4 Offline and deployment:** service worker, installability, Docker Compose, HTTPS, iOS hint, backup.
6. **M5 Comfort** (done): parent mode ('Abfragen lassen': the parent sees the solution at once and judges the spoken answer), multiple choice (options from the same word class and nearby units, never a second right answer; a right choice counts like any answer), test-date planning (secure = box 3 or higher, i.e. two right answers in a row; today's goal spreads the remaining right answers over the days before the test; the plan is the synced setting test.<profile>), statistics per unit (14-day history, per unit box distribution, secure cards and recent accuracy, hardest words; computed on the device for the learner and by the server for parents, both pinned by vectors/stats.json; colours colour-blind safe), user profile with a display name that the app greets with (done: a synced setting, set by the user, changeable by admins), admin page in the web app (done: create accounts, release profiles, set display names, reset passwords, disable accounts from a phone or browser, using the `/admin/users` API; the CLI stays for bootstrapping the first admin).

## 13. Open points

- Title and publisher of the textbook for `profile.book` (to be supplied).
- Check domain and GitHub name for `capsa` (up to the project owner). Note: "Capsa" also exists as construction document management software (UK) and as a card game; no conflict found in the learning space.
- Check the word class of `etiam` in the book (the photo shows "Konj."), and check macrons overall against the book.
- Meaning of the abbreviation "SP" in the book (stored in the profile as `marker: SP`, assumption: factual information).
- Whether "name all meanings" should become an option.
- UI language: German first, with all strings kept i18n-ready (assumption, to be confirmed).
- Event growth and snapshots. Measured: about 300 bytes per event in SQLite and 330 bytes as JSON in a sync download; a diligent learner produces about 18,000 events (5-6 MB) a year. Not a concern for a family. When an account passes about 100,000 events, or before any use by schools, add learning-state snapshots: the server keeps the per-card state as of a cutoff date (with a grace period of e.g. 90 days for late offline answers, which are otherwise applied on top of the snapshot), new devices download snapshot plus newer events, and old events can be archived (daily aggregates are enough for charts); then `VACUUM` the SQLite file. `capsa stats` reports accounts over the threshold.
- Move from SQLite to PostgreSQL at some point (e.g. before any opening for schools, see 11). When: to be decided; until then keep the storage layer portable (see 3).

## 14. Notes for Claude Code

- Implement M0 first, with tests as the foundation. Answer checking is pure logic and easy to test.
- Repository layout (decided): `schemas/` (JSON Schema), `api/` (Python: FastAPI server, `capsa` CLI, profile validation), `web/` (Svelte PWA), `vectors/` (shared JSON test vectors), `profiles/demo/` (own demo profile).
- The API is storage and sync: accounts, profiles, events, settings. It does not check answers.
- Answer matching and Leitner logic live in TypeScript under `web/src/lib/learning/`, pure and free of I/O. If the server ever needs the Leitner state (e.g. statistics for parents), a Python port must pass the same `vectors/*.json`.
- No book content in commits, logs or test data.
