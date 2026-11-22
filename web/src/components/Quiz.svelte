<script lang="ts">
  import type { App } from '../lib/app.svelte';
  import { hasExtras, matchContext, prompt, solution } from '../lib/learning/cards';
  import { checkAnswer, type Verdict } from '../lib/learning/match';
  import { t } from '../lib/i18n';
  import InfoPanel from './InfoPanel.svelte';

  let { app }: { app: App } = $props();

  const card = $derived(app.session?.queue[0]);
  const entry = $derived(card ? app.index?.entries.get(card.entryId) : undefined);
  const doc = $derived(app.index?.doc);
  const position = $derived((app.session?.results.length ?? 0) + 1);
  const total = $derived((app.session?.results.length ?? 0) + (app.session?.queue.length ?? 0));
  const repeated = $derived(
    card ? (app.session?.results.some((r) => r.card.entryId === card.entryId && r.card.direction === card.direction) ?? false) : false,
  );

  let typed = $state('');
  let verdict = $state<Verdict | null>(null);
  let revealed = $state(false);
  let showInfo = $state(false);
  let shownAt = Date.now();
  let responseMs: number | null = null;
  let input: HTMLInputElement | undefined = $state();
  let next: HTMLButtonElement | undefined = $state();

  // Reset for every new card.
  $effect(() => {
    void position;
    typed = '';
    verdict = null;
    revealed = false;
    showInfo = false;
    shownAt = Date.now();
    responseMs = null;
    queueMicrotask(() => input?.focus());
  });

  $effect(() => {
    if (verdict === 'correct' || verdict === 'wrong') queueMicrotask(() => next?.focus());
  });

  function check(event: SubmitEvent) {
    event.preventDefault();
    if (!entry || !card || !doc || verdict) return;
    responseMs = Date.now() - shownAt;
    verdict = checkAnswer(entry, typed, matchContext(doc, card.direction, app.lang)).verdict;
  }

  function reveal() {
    responseMs = Date.now() - shownAt;
    revealed = true;
  }

  function done(correct: boolean) {
    void app.answer(correct, responseMs);
  }
</script>

{#if card && entry && doc}
  <header class="bar-top">
    <span>{t('quiz.of', { n: position, total })}</span>
    <button class="link" onclick={() => app.quitSession()}>{t('quiz.quit')}</button>
  </header>

  <section class="card quiz">
    <div class="prompt">
      <p class="word" lang={card.direction === 'src_to_tr' ? doc.profile.source_lang : app.lang}>
        {prompt(entry, card.direction, app.lang)}
        {#if card.direction === 'src_to_tr' && entry.info && (verdict !== null || revealed)}
          <small>{entry.info}</small>
        {/if}
      </p>
      {#if hasExtras(entry) || entry.info}
        <button class="info-button" onclick={() => (showInfo = true)} aria-label={t('info.open')}>i</button>
      {/if}
    </div>
    {#if repeated}<p class="hint">{t('quiz.again')}</p>{/if}

    {#if app.prefs.mode === 'typed'}
      <form onsubmit={check}>
        <input
          bind:this={input}
          bind:value={typed}
          aria-label={t('quiz.answer')}
          placeholder={t('quiz.answer')}
          autocomplete="off"
          autocapitalize="none"
          spellcheck="false"
          readonly={verdict !== null}
          lang={card.direction === 'src_to_tr' ? app.lang : doc.profile.source_lang}
        />
        {#if verdict === null}
          <button class="primary">{t('quiz.check')}</button>
        {/if}
      </form>
    {:else if !revealed}
      <button class="primary big" onclick={reveal}>{t('quiz.reveal')}</button>
    {/if}

    {#if verdict !== null || revealed}
      <div class="result {verdict ?? 'revealed'}" role="status">
        {#if verdict === 'correct'}<p class="verdict">{t('quiz.correct')}</p>{/if}
        {#if verdict === 'almost'}<p class="verdict">{t('quiz.almost')}</p>{/if}
        {#if verdict === 'wrong'}<p class="verdict">{t('quiz.wrong')}</p>{/if}
        <p class="solution">
          {solution(entry, card.direction, app.lang)}
          {#if card.direction === 'tr_to_src' && entry.info}<small>{entry.info}</small>{/if}
        </p>
      </div>

      <div class="actions">
        {#if verdict === 'almost'}
          <button class="primary" onclick={() => done(true)}>{t('quiz.countAsRight')}</button>
          <button onclick={() => done(false)}>{t('quiz.countAsWrong')}</button>
        {:else if verdict !== null}
          <button class="primary" bind:this={next} onclick={() => done(verdict === 'correct')}>
            {t('quiz.next')}
          </button>
        {:else}
          <button class="primary" onclick={() => done(true)}>{t('quiz.knew')}</button>
          <button onclick={() => done(false)}>{t('quiz.didntKnow')}</button>
        {/if}
      </div>
    {/if}
  </section>

  {#if showInfo}
    <InfoPanel {entry} sourceLang={doc.profile.source_lang} onclose={() => (showInfo = false)} />
  {/if}
{/if}
