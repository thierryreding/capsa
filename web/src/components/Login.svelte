<script lang="ts">
  import { untrack } from 'svelte';
  import type { App } from '../lib/app.svelte';
  import { t } from '../lib/i18n';

  let { app }: { app: App } = $props();

  let username = $state('');
  let password = $state('');
  let busy = $state(false);
  // Shown once when the session expired; later changes of app.notice do not matter here.
  let error = $state<string | null>(
    untrack(() => (app.notice === 'expired' ? t('login.expired') : null)),
  );

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    busy = true;
    const problem = await app.login(username.trim(), password);
    busy = false;
    if (problem === null) return;
    if (problem.startsWith('rateLimited:')) {
      error = t('login.rateLimited', { minutes: problem.split(':')[1] });
    } else {
      error = t(problem === 'offline' ? 'login.offline' : 'login.failed');
    }
    password = '';
  }
</script>

<section class="card narrow">
  <h1>{t('app.title')}</h1>
  <form onsubmit={submit}>
    <label>
      {t('login.username')}
      <input bind:value={username} autocomplete="username" autocapitalize="none" required />
    </label>
    <label>
      {t('login.password')}
      <input type="password" bind:value={password} autocomplete="current-password" required />
    </label>
    {#if error}<p class="error" role="alert">{error}</p>{/if}
    <button class="primary" disabled={busy}>{t('login.submit')}</button>
  </form>
</section>
