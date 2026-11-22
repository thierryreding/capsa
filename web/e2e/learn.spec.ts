import { expect, test } from '@playwright/test';
import {
  currentEntry,
  login,
  newLearner,
  next,
  typeAnswer,
} from './helpers';

test('sign in, learn a session with typed answers, see progress', async ({ page, request }) => {
  await login(page, await newLearner(request));
  await expect(page.getByRole('heading', { name: 'Demo: Latein am Meer' })).toBeVisible();
  await expect(page.getByText('10 neu')).toBeVisible(); // unit 1 has 10 entries

  await page.getByRole('button', { name: /Los geht’s \(10 Karten\)/ }).click();
  await expect(page.getByText('Karte 1 von 10')).toBeVisible();

  // First card: wrong on purpose; it must come back later in the session.
  const missed = await currentEntry(page);
  await typeAnswer(page, 'völlig falsch');
  await expect(page.getByText('Leider falsch.')).toBeVisible();
  await expect(page.locator('.solution')).toContainText(missed.tr.de[0]);
  await next(page, () => page.getByRole('button', { name: 'Weiter' }).click());

  let sawAlmost = false;
  let sawInfo = false;
  for (let i = 0; i < 12; i++) {
    if (await page.getByRole('heading', { name: 'Geschafft!' }).isVisible()) break;
    const entry = await currentEntry(page);
    const answer = entry.tr.de[0].replace(/^(der|die|das) /, '');
    if (!sawInfo && (await page.getByRole('button', { name: 'Mehr Informationen' }).isVisible())) {
      await page.getByRole('button', { name: 'Mehr Informationen' }).click();
      await expect(page.getByRole('dialog')).toContainText(entry.lemma);
      await page.getByRole('button', { name: 'Schließen' }).click();
      await expect(page.getByRole('dialog')).toBeHidden();
      await page.getByRole('button', { name: 'Mehr Informationen' }).click();
      await page.keyboard.press('Escape');
      await expect(page.getByRole('dialog')).toBeHidden();
      sawInfo = true;
    }
    if (!sawAlmost && answer.length >= 7 && !answer.includes(' ')) {
      await typeAnswer(page, answer.slice(0, -1)); // one letter missing
      await expect(page.getByText('Fast richtig – ein Tippfehler?')).toBeVisible();
      await next(page, () => page.getByRole('button', { name: 'Zählt als richtig' }).click());
      sawAlmost = true;
      continue;
    }
    await typeAnswer(page, answer);
    await expect(page.getByText('Richtig!')).toBeVisible();
    await next(page, () => page.keyboard.press('Enter')); // "Weiter" has the focus
  }

  await expect(page.getByRole('heading', { name: 'Geschafft!' })).toBeVisible();
  await expect(page.getByText('9 von 10 Karten auf Anhieb richtig.')).toBeVisible();
  expect(sawAlmost).toBe(true);
  expect(sawInfo).toBe(true);

  await page.getByRole('button', { name: 'Zur Übersicht' }).click();
  // All of unit 1 answered: nothing new left there; unit 2 untouched.
  await expect(page.getByText('0 neu')).toBeVisible();
  await expect(page.getByText('9 neu')).toBeVisible();
});

test('keeps working offline after the first load', async ({ page, context, request }) => {
  await login(page, await newLearner(request));
  await context.setOffline(true);
  await page.evaluate(() => document.dispatchEvent(new Event('visibilitychange')));
  await expect(page.getByText(/^Offline/)).toBeVisible();

  await page.getByRole('button', { name: /Los geht’s/ }).click();
  const entry = await currentEntry(page);
  await typeAnswer(page, entry.tr.de[0]);
  await expect(page.getByText('Richtig!')).toBeVisible();
  await page.getByRole('button', { name: 'Weiter' }).click();
  await expect(page.getByText('Karte 2 von 10')).toBeVisible();
});

test('a double tap on "Weiter" records only one answer', async ({ page, request }) => {
  await login(page, await newLearner(request));
  await page.getByRole('button', { name: /Los geht’s/ }).click();
  const entry = await currentEntry(page);
  await typeAnswer(page, entry.tr.de[0]);
  await page.getByRole('button', { name: 'Weiter' }).dblclick();
  await expect(page.getByText('Karte 2 von 10')).toBeVisible();
  await page.waitForTimeout(300);
  await expect(page.getByText('Karte 2 von 10')).toBeVisible(); // not skipped to 3
});
