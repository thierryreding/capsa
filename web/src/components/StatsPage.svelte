<script lang="ts">
  import { leitnerConfig, type App } from '../lib/app.svelte';
  import { learningStats } from '../lib/learning/stats';
  import { t } from '../lib/i18n';
  import StatsView from './StatsView.svelte';

  let { app }: { app: App } = $props();

  // Computed on the device from the local events, so it works offline.
  const stats = $derived(
    app.index ? learningStats(app.index.doc, app.events, Date.now(), leitnerConfig()) : null,
  );
</script>

<header class="bar-top">
  <span>{t('stats.title')}</span>
  <button class="link" onclick={() => app.goHome()}>{t('admin.back')}</button>
</header>

{#if stats && app.index}
  <section class="card">
    <h2>{app.index.doc.profile.title}</h2>
    <StatsView {stats} />
  </section>
{/if}
