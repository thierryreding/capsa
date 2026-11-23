<script lang="ts">
  import type { App } from '../lib/app.svelte';
  import { displayNameInput, greetingName } from '../lib/account';
  import { t } from '../lib/i18n';

  let { app }: { app: App } = $props();

  let editing = $state(false);
  let value = $state('');
  let busy = $state(false);
  let error = $state<string | null>(null);
  let input: HTMLInputElement | undefined = $state();

  function edit() {
    value = app.me?.display_name ?? '';
    error = null;
    editing = true;
    queueMicrotask(() => input?.focus());
  }

  async function save(event: SubmitEvent) {
    event.preventDefault();
    const name = displayNameInput(value);
    if (name === 'invalid') {
      error = t('name.invalid');
      return;
    }
    busy = true;
    const problem = await app.setDisplayName(name);
    busy = false;
    if (problem === null) editing = false;
    else error = t(problem === 'offline' ? 'name.offline' : 'name.invalid');
  }
</script>

{#if editing}
  <form class="name-edit" onsubmit={save}>
    <label>
      {t('name.label')}
      <input bind:this={input} bind:value maxlength="64" autocomplete="nickname" />
    </label>
    <small class="hint">{t('name.hint')}</small>
    {#if error}<p class="error" role="alert">{error}</p>{/if}
    <div class="actions">
      <button class="primary" disabled={busy}>{t('name.save')}</button>
      <button type="button" onclick={() => (editing = false)}>{t('name.cancel')}</button>
    </div>
  </form>
{:else}
  <button class="link greeting" onclick={edit} title={t('name.edit')}>
    {t('home.hello', { name: app.me ? greetingName(app.me) : '' })}
  </button>
{/if}
