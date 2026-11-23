<script lang="ts">
  import type { App } from '../lib/app.svelte';
  import { t } from '../lib/i18n';
  import { installAdvice, isIOS, isStandalone, type InstallPromptEvent } from '../lib/platform';

  let { app }: { app: App } = $props();

  let promptEvent = $state<InstallPromptEvent | null>(null);
  let dismissed = $state(sessionStorage.getItem('capsa.install-hint') === 'dismissed');

  $effect(() => {
    const capture = (e: Event) => {
      e.preventDefault(); // show our own button instead of the browser's mini-infobar
      promptEvent = e as InstallPromptEvent;
    };
    window.addEventListener('beforeinstallprompt', capture);
    return () => window.removeEventListener('beforeinstallprompt', capture);
  });

  const advice = $derived(
    installAdvice({
      ios: isIOS(),
      standalone: isStandalone(),
      canPrompt: promptEvent !== null,
      lastSyncAt: app.lastSyncAt,
      now: Date.now(),
    }),
  );

  async function install() {
    await promptEvent?.prompt();
    promptEvent = null;
  }

  function dismiss() {
    sessionStorage.setItem('capsa.install-hint', 'dismissed');
    dismissed = true;
  }
</script>

{#if advice === 'ios-warning'}
  <p class="offline" role="alert">{t('install.iosWarning')} {t('install.iosSteps')}</p>
{:else if advice === 'ios-hint' && !dismissed}
  <p class="notice" role="note">
    {t('install.iosHint')} {t('install.iosSteps')}
    <button class="link" onclick={dismiss}>{t('install.later')}</button>
  </p>
{:else if advice === 'prompt' && !dismissed}
  <p class="notice" role="note">
    {t('install.promptHint')}
    <button class="link" onclick={install}>{t('install.button')}</button>
    <button class="link" onclick={dismiss}>{t('install.later')}</button>
  </p>
{/if}
