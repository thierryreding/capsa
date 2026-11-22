<script lang="ts">
  import type { App } from '../lib/app.svelte';
  import { summary } from '../lib/learning/session';
  import { t } from '../lib/i18n';

  let { app }: { app: App } = $props();
  const result = $derived(app.session ? summary(app.session) : { cards: 0, firstTry: 0, answers: 0 });
  const more = $derived(app.plannedCards().length > 0);
</script>

<section class="card narrow">
  <h1>{t('summary.title')}</h1>
  <p>{t('summary.result', { firstTry: result.firstTry, cards: result.cards })}</p>
  <div class="actions">
    {#if more}<button class="primary" onclick={() => app.beginSession()}>{t('summary.more')}</button>{/if}
    <button onclick={() => app.goHome()}>{t('summary.home')}</button>
  </div>
</section>
