<script lang="ts">
  import type { ProfileSummary } from '../lib/admin';
  import { t } from '../lib/i18n';

  let {
    profiles,
    selected = $bindable(),
  }: { profiles: ProfileSummary[]; selected: string[] } = $props();

  function toggle(id: string, on: boolean) {
    selected = on ? [...selected, id] : selected.filter((p) => p !== id);
  }
</script>

<fieldset>
  <legend>{t('admin.profiles')}</legend>
  {#each profiles as p (p.id)}
    <label class="check">
      <input type="checkbox" checked={selected.includes(p.id)}
        onchange={(e) => toggle(p.id, e.currentTarget.checked)} />
      {p.title}
    </label>
  {/each}
</fieldset>
