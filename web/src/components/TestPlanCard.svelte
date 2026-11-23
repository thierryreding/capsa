<script lang="ts">
  import { leitnerConfig, type App } from '../lib/app.svelte';
  import { localDate, planStatus } from '../lib/learning/plan';
  import { t } from '../lib/i18n';

  let { app }: { app: App } = $props();

  let editing = $state(false);
  let date = $state('');
  let error = $state<string | null>(null);

  const config = leitnerConfig();
  const today = localDate(Date.now(), config.utcOffsetMinutes);

  const plan = $derived(app.testPlan);
  const doc = $derived(app.index?.doc);
  const status = $derived.by(() => {
    if (!plan || !doc) return null;
    return planStatus(
      plan,
      { profileId: doc.profile.id, entries: app.askableEntries(), directions: app.directions },
      app.states,
      app.events,
      Date.now(),
      config,
    );
  });

  const unitNames = (ids: Iterable<string>) => {
    const wanted = new Set(ids);
    return (doc?.units ?? [])
      .filter((u) => wanted.has(u.id))
      .map((u) => u.number)
      .join(', ');
  };

  const weekday = (iso: string) =>
    new Intl.DateTimeFormat('de', { weekday: 'long', day: 'numeric', month: 'long' }).format(
      new Date(`${iso}T12:00:00`),
    );

  const when = (days: number) =>
    days === 0 ? t('test.today') : days === 1 ? t('test.tomorrow') : t('test.inDays', { days });

  function edit() {
    date = plan?.date ?? '';
    error = null;
    editing = true;
  }

  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (!date || date < today) {
      error = t('test.error.date');
      return;
    }
    const units = [...app.units];
    if (units.length === 0) {
      error = t('test.error.units');
      return;
    }
    await app.setTestPlan({ date, units });
    editing = false;
  }
</script>

<section class="card test-plan">
  {#if editing}
    <form onsubmit={save}>
      <label>
        {t('test.date')}
        <input type="date" bind:value={date} min={today} required />
      </label>
      <p class="hint">{t('test.unitsFromSelection', { units: unitNames(app.units) || '–' })}</p>
      {#if error}<p class="error" role="alert">{error}</p>{/if}
      <div class="actions">
        <button class="primary">{t('test.save')}</button>
        <button type="button" onclick={() => (editing = false)}>{t('test.cancel')}</button>
      </div>
    </form>
  {:else if plan && status && status.daysLeft < 0}
    <p>{t('test.over', { date: weekday(plan.date) })}</p>
    <button class="link" onclick={() => app.setTestPlan(null)}>{t('test.remove')}</button>
  {:else if plan && status}
    <h2>{t('test.title', { when: when(status.daysLeft) })}</h2>
    <p class="hint">
      {weekday(plan.date)} · {t('test.units', { units: unitNames(plan.units) })}
    </p>
    <span class="progress" title={t('test.secureTitle')}>
      <span class="bar" aria-hidden="true">
        <span class="seg box5" style:flex-grow={status.secure}></span>
        <span class="seg fresh" style:flex-grow={status.cards - status.secure}></span>
      </span>
      <small>{t('test.secure', { secure: status.secure, cards: status.cards })}</small>
    </span>
    {#if status.needed === 0}
      <p class="ok-text">{t('test.ready')}</p>
    {:else if status.doneToday >= status.goalToday}
      <p class="ok-text">{t('test.doneToday', { done: status.doneToday })}</p>
    {:else}
      <p>{t('test.goalToday', { left: status.goalToday - status.doneToday })}</p>
    {/if}
    {#if status.needed > 0}
      <button class="primary big" onclick={() => app.beginSession('test')}>{t('test.practise')}</button>
    {/if}
    <div class="row">
      <button class="link" onclick={edit}>{t('test.change')}</button>
      <button class="link" onclick={() => app.setTestPlan(null)}>{t('test.remove')}</button>
    </div>
  {:else}
    <button class="link" onclick={edit}>{t('test.plan')}</button>
  {/if}
</section>
