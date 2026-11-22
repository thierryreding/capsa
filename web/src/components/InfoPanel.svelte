<script lang="ts">
  import type { Entry } from '../lib/api/client';
  import { langName, t } from '../lib/i18n';

  let { entry, sourceLang, onclose }: { entry: Entry; sourceLang: string; onclose: () => void } =
    $props();

  const otherLangs = (example: Record<string, string>) =>
    Object.entries(example).filter(([lang]) => lang !== sourceLang);
</script>

<div class="info" role="dialog" aria-label={t('info.open')}>
  <button class="close" onclick={onclose} aria-label={t('info.close')}>×</button>
  <p class="lemma">{entry.lemma} {#if entry.info}<small>{entry.info}</small>{/if}</p>

  {#if entry.notes?.length}
    <h3>{t('info.notes')}</h3>
    <ul>
      {#each entry.notes as note, i (i)}
        <li>{#if note.marker}<b>{note.marker}</b> {/if}{note.text}
          {#if note.refs?.length}<small>({note.refs.join(', ')})</small>{/if}</li>
      {/each}
    </ul>
  {/if}

  {#if entry.examples?.length}
    <h3>{t('info.examples')}</h3>
    <ul>
      {#each entry.examples as example, i (i)}
        <li>
          <i>{example[sourceLang]}</i>
          {#each otherLangs(example) as [lang, text] (lang)}<br /><small>{text}</small>{/each}
        </li>
      {/each}
    </ul>
  {/if}

  {#if entry.loanwords && Object.keys(entry.loanwords).length}
    <h3>{t('info.loanwords')}</h3>
    <ul>
      {#each Object.entries(entry.loanwords) as [lang, words] (lang)}
        <li>{langName(lang)}: {words.join(', ')}</li>
      {/each}
    </ul>
  {/if}

  {#if entry.refs?.length}
    <h3>{t('info.refs')}</h3>
    <p>{entry.refs.join(', ')}</p>
  {/if}
</div>
