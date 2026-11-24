<script lang="ts">
  import type { App, DirectionChoice, QuizMode } from '../lib/app.svelte';
  import { leitnerConfig } from '../lib/app.svelte';
  import { askable } from '../lib/learning/cards';
  import { progressByUnit, type Selection } from '../lib/learning/session';
  import { langName, t } from '../lib/i18n';
  import Greeting from './Greeting.svelte';
  import InstallHint from './InstallHint.svelte';
  import SyncStatus from './SyncStatus.svelte';
  import TestPlanCard from './TestPlanCard.svelte';
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

  const modes: QuizMode[] = ['typed', 'choice', 'flashcard', 'parent'];
  // 'test' is started from the test card, not chosen here.
  const selections: Exclude<Selection, 'test'>[] = ['mixed', 'due', 'mistakes', 'all'];
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
  <TestPlanCard {app} />

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

    <label>
      {t('home.mode')}
      <select value={app.prefs.mode}
        onchange={(e) => app.setPrefs({ mode: e.currentTarget.value as QuizMode })}>
        {#each modes as mode (mode)}
          <option value={mode}>{t(`home.mode.${mode}`)}</option>
        {/each}
      </select>
    </label>

    <label>
      {t('home.direction')}
      <select value={app.prefs.direction}
        onchange={(e) => app.setPrefs({ direction: e.currentTarget.value as DirectionChoice })}>
        {#each directions as direction (direction)}
          <option value={direction}>
            {direction === 'mixed' ? t('home.direction.mixed') : t(`direction.${direction}`, { src, tr })}
          </option>
        {/each}
      </select>
    </label>

    {#if doc.profile.translation_langs.length > 1}
      <label>
        {t('home.language')}
        <select value={app.lang} onchange={(e) => app.setPrefs({ lang: e.currentTarget.value })}>
          {#each doc.profile.translation_langs as lang (lang)}
            <option value={lang}>{langName(lang)}</option>
          {/each}
        </select>
      </label>
    {/if}

    <label>
      {t('home.selection')}
      <select value={app.prefs.selection}
        onchange={(e) => app.setPrefs({ selection: e.currentTarget.value as Exclude<Selection, 'test'> })}>
        {#each selections as selection (selection)}
          <option value={selection}>{t(`home.selection.${selection}`)}</option>
        {/each}
      </select>
    </label>

    <button class="link stats-link" onclick={() => app.openStats()}>{t('stats.link')}</button>

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
