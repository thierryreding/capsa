<script lang="ts">
  import type { App } from '../lib/app.svelte';
  import { checkPassword, updateUser, type ProfileSummary, type UserInfo } from '../lib/admin';
  import { t } from '../lib/i18n';
  import ProfileChoice from './ProfileChoice.svelte';

  let {
    app,
    user,
    profiles,
    onchange,
  }: { app: App; user: UserInfo; profiles: ProfileSummary[]; onchange: (u: UserInfo) => void } =
    $props();

  let editing = $state(false);
  let displayName = $state('');
  let selected = $state<string[]>([]);
  let password = $state('');
  let message = $state<string | null>(null);
  let error = $state<string | null>(null);
  let busy = $state(false);

  const self = $derived(user.id === app.me?.id);
  const titles = $derived(
    user.profiles.map((id) => profiles.find((p) => p.id === id)?.title ?? id).join(', '),
  );

  function open() {
    displayName = user.display_name ?? '';
    selected = [...user.profiles];
    password = '';
    message = error = null;
    editing = true;
  }

  async function change(body: Parameters<typeof updateUser>[2], done: string) {
    busy = true;
    error = message = null;
    const r = await updateUser(app.api, user.id, body);
    busy = false;
    if (!r.ok) {
      error = r.error;
      return false;
    }
    onchange(r.value);
    message = done;
    return true;
  }

  async function save(event: SubmitEvent) {
    event.preventDefault();
    const body: Parameters<typeof updateUser>[2] = { display_name: displayName.trim() || null };
    if (user.role === 'learner') body.profiles = selected;
    if (await change(body, t('admin.saved'))) editing = false;
  }

  async function resetPassword() {
    const problem = checkPassword(password);
    if (problem) {
      error = problem;
      return;
    }
    const name = user.display_name ?? user.username;
    if (await change({ password }, t('admin.passwordReset', { name }))) password = '';
  }
</script>

<li class="user" class:disabled={user.disabled}>
  <div class="user-head">
    <span>
      <b>{user.display_name ?? user.username}</b>
      {#if user.display_name}<small>({user.username})</small>{/if}
      {#if self}<small>– {t('admin.you')}</small>{/if}
      {#if user.disabled}<small class="error">– {t('admin.disabled')}</small>{/if}
      <br />
      <small>
        {t(`admin.role.${user.role}`)} ·
        {user.role === 'admin' ? t('admin.allProfiles') : titles || t('admin.noProfiles')}
      </small>
    </span>
    {#if !editing}
      <button class="link" onclick={open}>{t('admin.edit')}</button>
    {/if}
  </div>

  {#if message && !editing}<p class="hint" role="status">{message}</p>{/if}

  {#if editing}
    <form onsubmit={save}>
      <label>
        {t('admin.displayName')}
        <input bind:value={displayName} maxlength="64" />
      </label>
      {#if user.role === 'learner'}
        <ProfileChoice {profiles} bind:selected />
      {/if}
      <div class="actions">
        <button class="primary" disabled={busy}>{t('admin.save')}</button>
        <button type="button" onclick={() => (editing = false)}>{t('admin.cancel')}</button>
      </div>
    </form>

    <div class="row-form">
      <label>
        {t('admin.newPassword')}
        <input type="password" bind:value={password} autocomplete="new-password" />
      </label>
      <button disabled={busy || !password} onclick={resetPassword}>{t('admin.resetPassword')}</button>
    </div>

    {#if !self}
      <button disabled={busy}
        onclick={() => change({ disabled: !user.disabled }, t('admin.saved'))}>
        {user.disabled ? t('admin.enable') : t('admin.disable')}
      </button>
    {/if}
    {#if message}<p class="hint" role="status">{message}</p>{/if}
    {#if error}<p class="error" role="alert">{error}</p>{/if}
  {/if}
</li>
