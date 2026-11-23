<script lang="ts">
  import type { App } from '../lib/app.svelte';
  import {
    checkNewUser,
    createUser,
    listProfiles,
    listUsers,
    type ProfileSummary,
    type UserInfo,
  } from '../lib/admin';
  import { t } from '../lib/i18n';
  import AdminUser from './AdminUser.svelte';
  import ProfileChoice from './ProfileChoice.svelte';

  let { app }: { app: App } = $props();

  let users = $state<UserInfo[] | null>(null);
  let profiles = $state<ProfileSummary[]>([]);
  let loadError = $state<string | null>(null);

  let creating = $state(false);
  let username = $state('');
  let password = $state('');
  let displayName = $state('');
  let role = $state<'learner' | 'admin'>('learner');
  let selected = $state<string[]>([]);
  let error = $state<string | null>(null);
  let message = $state<string | null>(null);
  let busy = $state(false);

  async function load() {
    const [u, p] = await Promise.all([listUsers(app.api), listProfiles(app.api)]);
    if (!u.ok || !p.ok) {
      loadError = !u.ok ? u.error : !p.ok ? p.error : null;
      return;
    }
    loadError = null;
    users = u.value;
    profiles = p.value;
  }

  $effect(() => {
    void load();
  });

  function replace(updated: UserInfo) {
    users = users?.map((u) => (u.id === updated.id ? updated : u)) ?? null;
  }

  async function create(event: SubmitEvent) {
    event.preventDefault();
    error = message = null;
    const problem = checkNewUser({ username: username.trim(), password });
    if (problem) {
      error = problem;
      return;
    }
    busy = true;
    const r = await createUser(app.api, {
      username: username.trim(),
      password,
      role,
      display_name: displayName.trim() || null,
      profiles: role === 'learner' ? selected : [],
    });
    busy = false;
    if (!r.ok) {
      error = r.error;
      return;
    }
    users = [...(users ?? []), r.value].sort((a, b) =>
      a.username.localeCompare(b.username, undefined, { sensitivity: 'base' }),
    );
    message = t('admin.created', { name: r.value.display_name ?? r.value.username });
    username = password = displayName = '';
    selected = [];
    role = 'learner';
    creating = false;
  }
</script>

<header class="bar-top">
  <span>{t('admin.title')}</span>
  <button class="link" onclick={() => app.goHome()}>{t('admin.back')}</button>
</header>

{#if loadError}
  <section class="card">
    <p class="error" role="alert">{loadError}</p>
    <button onclick={load}>{t('sync.now')}</button>
  </section>
{:else if users === null}
  <p class="hint">{t('admin.loading')}</p>
{:else}
  <section class="card">
    <h2>{t('admin.users')}</h2>
    <ul class="users">
      {#each users as user (user.id)}
        <AdminUser {app} {user} {profiles} onchange={replace} />
      {/each}
    </ul>
    {#if message}<p class="hint" role="status">{message}</p>{/if}
  </section>

  <section class="card">
    {#if !creating}
      <button class="primary big" onclick={() => (creating = true)}>{t('admin.new')}</button>
    {:else}
      <h2>{t('admin.new')}</h2>
      <form onsubmit={create}>
        <label>
          {t('admin.username')}
          <input bind:value={username} autocapitalize="none" autocomplete="off" required />
        </label>
        <label>
          {t('admin.password')}
          <input type="password" bind:value={password} autocomplete="new-password" required
            aria-describedby="new-password-hint" />
        </label>
        <small class="hint field-hint" id="new-password-hint">{t('admin.passwordHint')}</small>
        <label>
          {t('admin.displayName')}
          <input bind:value={displayName} maxlength="64" aria-describedby="new-name-hint" />
        </label>
        <small class="hint field-hint" id="new-name-hint">{t('admin.displayNameHint')}</small>
        <fieldset class="options">
          <legend>{t('admin.role')}</legend>
          {#each ['learner', 'admin'] as const as r (r)}
            <label class="chip">
              <input type="radio" name="role" checked={role === r} onchange={() => (role = r)} />
              {t(`admin.role.${r}`)}
            </label>
          {/each}
        </fieldset>
        {#if role === 'learner'}
          <ProfileChoice {profiles} bind:selected />
        {/if}
        {#if error}<p class="error" role="alert">{error}</p>{/if}
        <div class="actions">
          <button class="primary" disabled={busy}>{t('admin.create')}</button>
          <button type="button" onclick={() => (creating = false)}>{t('admin.cancel')}</button>
        </div>
      </form>
    {/if}
  </section>
{/if}
