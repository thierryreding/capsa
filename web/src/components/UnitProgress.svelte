<script lang="ts">
  import type { Progress } from '../lib/learning/session';
  import { t } from '../lib/i18n';

  let { progress }: { progress: Progress | undefined } = $props();
</script>

{#if progress}
  <span class="progress" title={t('progress.boxes')}>
    <span class="bar" aria-hidden="true">
      {#each progress.boxes as count, i (i)}
        <span class="seg box{i + 1}" style:flex-grow={count}></span>
      {/each}
      <span class="seg fresh" style:flex-grow={progress.fresh}></span>
    </span>
    <small>
      {#if progress.mistakes}{t('progress.mistakes', { count: progress.mistakes })} · {/if}
      {#if progress.due}{t('progress.due', { count: progress.due })} · {/if}
      {t('progress.new', { count: progress.fresh })}
    </small>
  </span>
{/if}
