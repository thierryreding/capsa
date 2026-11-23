<script lang="ts">
  import type { App, DirectionChoice, QuizMode } from '../lib/app.svelte';
  import { leitnerConfig } from '../lib/app.svelte';
  import { askable } from '../lib/learning/cards';
  import { progressByUnit, type Selection } from '../lib/learning/session';
  import { langName, t } from '../lib/i18n';
  import Greeting from './Greeting.svelte';
  import InstallHint from './InstallHint.svelte';
  import SyncStatus from './SyncStatus.svelte';
  import UnitProgress from './UnitProgress.svelte';

  let { app }: { app: App } = $props();

  const doc = $derived(app.index?.doc);
  const src = $derived(doc ? langName(doc.profile.source_lang) : '');
  const tr = $derived(langName(app.lang));

  const progress = $derived.by(() => {
    const index = app.index;
    if (!index) return new Map();
    return progressByUnit(app.states, {
      profileId: index.doc.profile.id,
      entries: index.refs.filter((r) => askable(index.entries.get(r.id)!, app.lang)),
      units: new Set(index.doc.units.map((u) => u.id)),
      directions: app.directions,
      now: Date.now(),
      config: leitnerConfig(),
    });
  });

  const planned = $derived(app.plannedCards().length);

  function toggleUnit(id: string, on: boolean) {
    const all = doc?.units.map((u) => u.id) ?? [];
    const current = new Set(app.prefs.units ?? all);
    if (on) current.add(id);
    else current.delete(id);
    const units = all.filter((u) => current.has(u));
    void app.setPrefs({ units: units.length === all.length ? null : units });
  }

  const modes: QuizMode[] = ['typed', 'choice', 'flashcard'];
  const selections: Selection[] = ['mixed', 'due', 'mistakes', 'all'];
  const directions: DirectionChoice[] = ['src_to_tr', 'tr_to_src', 'mixed'];
</script>

<header class="bar-top">
  <Greeting {app} />
  <span>
    {#if app.me?.role === 'admin'}
      <button class="link" onclick={() => app.openAdmin()}>{t('admin.link')}</button>
    {/if}
    <button class="link" onclick={() => app.logout()}>{t('home.logout')}</button>
  </span>
</header>

<InstallHint {app} />

{#if app.updateAvailable}
  <p class="notice" role="status">
    {t('update.available')}
    <button class="link" onclick={() => app.applyUpdate()}>{t('update.apply')}</button>
  </p>
{/if}

{#if !doc}
  <section class="card"><p>{t('home.noProfiles')}</p></section>
{:else}
  <section class="card">
    {#if app.profiles.length > 1}
      <label>
        {t('home.profile')}
        <select value={app.profileId} onchange={(e) => app.selectProfile(e.currentTarget.value)}>
          {#each app.profiles as p (p.id)}
            <option value={p.id}>{p.doc.profile.title}</option>
          {/each}
        </select>
      </label>
    {:else}
      <h2>{doc.profile.title}</h2>
    {/if}

    <fieldset>
      <legend>{t('home.units')}</legend>
      <div class="row">
        <button class="link" onclick={() => app.setPrefs({ units: null })}>{t('home.allUnits')}</button>
        <button class="link" onclick={() => app.setPrefs({ units: [] })}>{t('home.noUnits')}</button>
      </div>
      {#each doc.units as unit (unit.id)}
        <label class="unit">
          <input
            type="checkbox"
            checked={app.units.has(unit.id)}
            onchange={(e) => toggleUnit(unit.id, e.currentTarget.checked)}
          />
          <span class="unit-title">{unit.number}. {unit.title}</span>
          <UnitProgress progress={progress.get(unit.id)} />
        </label>
      {/each}
    </fieldset>

    <fieldset class="options">
      <legend>{t('home.mode')}</legend>
      {#each modes as mode (mode)}
        <label class="chip">
          <input type="radio" name="mode" checked={app.prefs.mode === mode}
            onchange={() => app.setPrefs({ mode })} />
          {t(`home.mode.${mode}`)}
        </label>
      {/each}
    </fieldset>

    <fieldset class="options">
      <legend>{t('home.direction')}</legend>
      {#each directions as direction (direction)}
        <label class="chip">
          <input type="radio" name="direction" checked={app.prefs.direction === direction}
            onchange={() => app.setPrefs({ direction })} />
          {direction === 'mixed' ? t('home.direction.mixed') : t(`direction.${direction}`, { src, tr })}
        </label>
      {/each}
    </fieldset>

    {#if doc.profile.translation_langs.length > 1}
      <fieldset class="options">
        <legend>{t('home.language')}</legend>
        {#each doc.profile.translation_langs as lang (lang)}
          <label class="chip">
            <input type="radio" name="lang" checked={app.lang === lang}
              onchange={() => app.setPrefs({ lang })} />
            {langName(lang)}
          </label>
        {/each}
      </fieldset>
    {/if}

    <fieldset class="options">
      <legend>{t('home.selection')}</legend>
      {#each selections as selection (selection)}
        <label class="chip">
          <input type="radio" name="selection" checked={app.prefs.selection === selection}
            onchange={() => app.setPrefs({ selection })} />
          {t(`home.selection.${selection}`)}
        </label>
      {/each}
    </fieldset>

    {#if planned > 0}
      <button class="primary big" onclick={() => app.beginSession()}>
        {t('home.start', { count: planned })}
      </button>
    {:else}
      <p class="hint">{t('home.nothing')}</p>
    {/if}
  </section>
{/if}

<SyncStatus {app} />
