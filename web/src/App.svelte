<script lang="ts">
  import { onMount } from 'svelte';
  import { registerSW } from 'virtual:pwa-register';
  import { App } from './lib/app.svelte';
  import { t } from './lib/i18n';
  import AdminPage from './components/AdminPage.svelte';
  import Home from './components/Home.svelte';
  import Login from './components/Login.svelte';
  import Quiz from './components/Quiz.svelte';
  import StatsPage from './components/StatsPage.svelte';
  import Summary from './components/Summary.svelte';

  const app = new App();

  onMount(() => {
    // Service worker: the app loads without a network after the first visit (SPEC 9).
    const updateSW = registerSW({
      onNeedRefresh: () => (app.updateAvailable = true),
      onRegisteredSW: (_url, registration) => {
        // Look for a new version whenever the app comes back to the foreground.
        document.addEventListener('visibilitychange', () => {
          if (document.visibilityState === 'visible') void registration?.update();
        });
      },
    });
    app.applyUpdate = () => void updateSW(true);
    void app.start();
    const refresh = () => {
      if (document.visibilityState === 'visible' && app.me) void app.refresh();
    };
    const back = () => app.me && void app.refresh();
    document.addEventListener('visibilitychange', refresh);
    window.addEventListener('online', back);
    return () => {
      document.removeEventListener('visibilitychange', refresh);
      window.removeEventListener('online', back);
    };
  });
</script>

<main>
  {#if !app.online && app.me}<p class="offline" role="status">{t('app.offline')}</p>{/if}
  {#if app.view === 'login'}
    <Login {app} />
  {:else if app.view === 'home'}
    <Home {app} />
  {:else if app.view === 'quiz'}
    <Quiz {app} />
  {:else if app.view === 'summary'}
    <Summary {app} />
  {:else if app.view === 'admin'}
    <AdminPage {app} />
  {:else if app.view === 'stats'}
    <StatsPage {app} />
  {/if}
</main>
