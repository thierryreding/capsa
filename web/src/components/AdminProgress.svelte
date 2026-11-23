<script lang="ts">
  import type { App } from '../lib/app.svelte';
  import { leitnerConfig } from '../lib/app.svelte';
  import { userProgress, type LearningStats, type ProfileSummary, type UserInfo } from '../lib/admin';
  import { t } from '../lib/i18n';
  import StatsView from './StatsView.svelte';

  let {
    app,
    user,
    profiles,
  }: { app: App; user: UserInfo; profiles: ProfileSummary[] } = $props();

  // Learners: their released books; admins see (and may learn) all books.
  const books = $derived(
    user.role === 'admin' ? profiles : profiles.filter((p) => user.profiles.includes(p.id)),
  );
  let profileId = $state<string | null>(null);
  let stats = $state<LearningStats | null>(null);
  let error = $state<string | null>(null);

  $effect(() => {
    const id = profileId ?? books[0]?.id;
    if (!id) return;
    stats = null;
    error = null;
    void userProgress(app.api, user.id, id, leitnerConfig().utcOffsetMinutes).then((r) => {
      if (r.ok) stats = r.value;
      else error = r.error;
    });
  });
</script>

<div class="admin-progress">
  {#if books.length === 0}
    <p class="hint">{t('admin.noProfiles')}</p>
  {:else}
    {#if books.length > 1}
      <label>
        {t('home.profile')}
        <select value={profileId ?? books[0].id} onchange={(e) => (profileId = e.currentTarget.value)}>
          {#each books as p (p.id)}<option value={p.id}>{p.title}</option>{/each}
        </select>
      </label>
    {/if}
    {#if error}
      <p class="error" role="alert">{error}</p>
    {:else if stats}
      <StatsView {stats} />
    {:else}
      <p class="hint">{t('stats.loading')}</p>
    {/if}
  {/if}
</div>
