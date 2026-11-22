<script lang="ts">
  import { onMount } from 'svelte';
  import { App } from './lib/app.svelte';
  import { t } from './lib/i18n';
  import Home from './components/Home.svelte';
  import Login from './components/Login.svelte';
  import Quiz from './components/Quiz.svelte';
  import Summary from './components/Summary.svelte';

  const app = new App();

  onMount(() => {
    void app.start();
    const refresh = () => {
      if (document.visibilityState === 'visible' && app.me) void app.refresh();
    };
    document.addEventListener('visibilitychange', refresh);
    return () => document.removeEventListener('visibilitychange', refresh);
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
  {/if}
</main>
