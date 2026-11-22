import { readFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import { parse } from 'yaml';

interface Entry {
  id: string;
  lemma: string;
  tr: Record<string, string[]>;
}
const demo = parse(readFileSync(new URL('../../profiles/demo/demo-latin.yaml', import.meta.url), 'utf-8'));
const byLemma = new Map<string, Entry>(
  demo.units.flatMap((u: { entries: Entry[] }) => u.entries).map((e: Entry) => [e.lemma, e]),
);

async function login(page: Page) {
  await page.goto('/');
  await page.getByLabel('Benutzername').fill('lena');
  await page.getByLabel('Passwort').fill('e2e-pass-123');
  await page.getByRole('button', { name: 'Anmelden' }).click();
  await expect(page.getByText('Hallo lena!')).toBeVisible();
}

async function currentEntry(page: Page): Promise<Entry> {
  const word = (await page.locator('.quiz .word').innerText()).trim();
  const entry = byLemma.get(word);
  expect(entry, `prompt ${word} is a demo lemma`).toBeDefined();
  return entry!;
}

/** Card number shown in "Karte N von M". */
async function position(page: Page): Promise<number> {
  return Number((await page.getByText(/^Karte \d+ von/).innerText()).split(' ')[1]);
}

/** Continue to the next card and wait until it is shown (answers are stored async). */
async function next(page: Page, press: () => Promise<void>) {
  const n = await position(page);
  await press();
  await expect(
    page.getByText(`Karte ${n + 1} von`).or(page.getByRole('heading', { name: 'Geschafft!' })),
  ).toBeVisible();
}

async function typeAnswer(page: Page, text: string) {
  await page.getByRole('textbox', { name: 'Deine Antwort' }).fill(text);
  await page.getByRole('button', { name: 'Prüfen' }).click();
}

test('sign in, learn a session with typed answers, see progress', async ({ page }) => {
  await login(page);
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

test('keeps working offline after the first load', async ({ page, context }) => {
  await login(page);
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

test('a double tap on "Weiter" records only one answer', async ({ page }) => {
  await login(page);
  await page.getByRole('button', { name: /Los geht’s/ }).click();
  const entry = await currentEntry(page);
  await typeAnswer(page, entry.tr.de[0]);
  await page.getByRole('button', { name: 'Weiter' }).dblclick();
  await expect(page.getByText('Karte 2 von 10')).toBeVisible();
  await page.waitForTimeout(300);
  await expect(page.getByText('Karte 2 von 10')).toBeVisible(); // not skipped to 3
});
