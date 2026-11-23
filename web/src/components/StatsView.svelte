<script lang="ts">
  import type { LearningStats } from '../lib/learning/stats';
  import { relativeTime, t } from '../lib/i18n';
  import UnitProgress from './UnitProgress.svelte';

  let { stats }: { stats: LearningStats } = $props();

  let focused = $state<number | null>(null);

  const max = $derived(Math.max(1, ...stats.days.map((d) => d.correct + d.wrong)));
  const dayLabel = (iso: string, style: 'short' | 'long') =>
    new Intl.DateTimeFormat('de', style === 'short'
      ? { weekday: 'narrow' }
      : { weekday: 'short', day: 'numeric', month: 'numeric' },
    ).format(new Date(`${iso}T12:00:00`));
  const describe = (i: number) => {
    const d = stats.days[i];
    return t('stats.day', { day: dayLabel(d.date, 'long'), right: d.correct, wrong: d.wrong });
  };
  const percent = (part: number, whole: number) => Math.round((100 * part) / whole);
</script>

<div class="stats">
  <p class="hint">
    {t('stats.total', { count: stats.total_answers })}
    {#if stats.last_answer_at}· {t('stats.last', { when: relativeTime(stats.last_answer_at) })}{/if}
  </p>

  <section aria-labelledby="stats-days">
    <h3 id="stats-days">{t('stats.daysTitle')}</h3>
    <div class="legend" aria-hidden="true">
      <span><i class="swatch right"></i>{t('stats.right')}</span>
      <span><i class="swatch wrong"></i>{t('stats.wrong')}</span>
    </div>
    <p class="readout" aria-live="polite">
      {focused === null ? t('stats.pickDay') : describe(focused)}
    </p>
    <div class="chart" role="group" aria-label={t('stats.daysTitle')}>
      {#each stats.days as day, i (day.date)}
        <button
          type="button"
          class="day"
          class:active={focused === i}
          aria-label={describe(i)}
          onmouseenter={() => (focused = i)}
          onfocus={() => (focused = i)}
          onclick={() => (focused = i)}
        >
          <div class="stack" style:height="{(100 * (day.correct + day.wrong)) / max}%">
            {#if day.wrong > 0}<span class="part wrong" style:flex-grow={day.wrong}></span>{/if}
            {#if day.correct > 0}<span class="part right" style:flex-grow={day.correct}></span>{/if}
          </div>
          <small aria-hidden="true">{dayLabel(day.date, 'short')}</small>
        </button>
      {/each}
    </div>
    <details>
      <summary>{t('stats.table')}</summary>
      <table>
        <thead><tr><th>{t('stats.dayColumn')}</th><th>{t('stats.right')}</th><th>{t('stats.wrong')}</th></tr></thead>
        <tbody>
          {#each stats.days as day (day.date)}
            <tr><td>{dayLabel(day.date, 'long')}</td><td>{day.correct}</td><td>{day.wrong}</td></tr>
          {/each}
        </tbody>
      </table>
    </details>
  </section>

  <section aria-labelledby="stats-units">
    <h3 id="stats-units">{t('stats.unitsTitle')}</h3>
    <ul class="stat-units">
      {#each stats.units as unit (unit.unit_id)}
        <li>
          <span class="unit-title">{unit.number}. {unit.title}</span>
          <UnitProgress progress={{ total: unit.cards, fresh: unit.fresh, due: 0, mistakes: unit.mistakes, boxes: unit.boxes }} />
          <small class="hint">
            {t('stats.secure', { secure: unit.secure, cards: unit.cards })}
            {#if unit.answers_recent > 0}
              · {t('stats.accuracy', { percent: percent(unit.correct_recent, unit.answers_recent) })}
            {/if}
          </small>
        </li>
      {/each}
    </ul>
  </section>

  <section aria-labelledby="stats-hardest">
    <h3 id="stats-hardest">{t('stats.hardestTitle')}</h3>
    {#if stats.hardest.length === 0}
      <p class="hint">{t('stats.noMistakes')}</p>
    {:else}
      <ol class="hardest">
        {#each stats.hardest as word (word.entry_id)}
          <li>
            <b>{word.lemma}</b> – {word.meaning}
            <small class="hint">
              {t('stats.wrongTimes', { wrong: word.wrong, right: word.correct })}
              {#if word.last_correct}· {t('stats.lastRight')}{/if}
            </small>
          </li>
        {/each}
      </ol>
    {/if}
  </section>
</div>
