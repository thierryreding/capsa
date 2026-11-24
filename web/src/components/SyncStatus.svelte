<script lang="ts">
  import type { App } from '../lib/app.svelte';
  import { relativeTime, t } from '../lib/i18n';

  let { app }: { app: App } = $props();

  // Re-render the relative time every minute.
  let now = $state(Date.now());
  $effect(() => {
    const timer = setInterval(() => (now = Date.now()), 60_000);
    return () => clearInterval(timer);
  });
</script>

<footer class="sync" aria-live="polite">
  {#if app.syncing}
    <span>{t('sync.running')}</span>
  {:else}
    <span>
      {#if app.unsynced > 0}
        {app.unsynced === 1 ? t('sync.pendingOne') : t('sync.pending', { count: app.unsynced })} ·
      {/if}
      {app.lastSyncAt ? t('sync.last', { when: relativeTime(app.lastSyncAt, now) }) : t('sync.never')}
    </span>
    <button class="link" onclick={() => app.refresh()}>{t('sync.now')}</button>
  {/if}
  <span class="version">Capsa {__APP_VERSION__}</span>
</footer>
