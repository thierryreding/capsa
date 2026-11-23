import { readFileSync } from 'node:fs';
import { expect, type APIRequestContext, type Page } from '@playwright/test';
import { parse } from 'yaml';

export const PASSWORD = 'e2e-pass-123';
const CSRF = { 'X-Capsa-CSRF': '1' };

export interface Entry {
  id: string;
  lemma: string;
  tr: Record<string, string[]>;
}
const demo = parse(
  readFileSync(new URL('../../profiles/demo/demo-latin.yaml', import.meta.url), 'utf-8'),
);
export const byLemma = new Map<string, Entry>(
  demo.units.flatMap((u: { entries: Entry[] }) => u.entries).map((e: Entry) => [e.lemma, e]),
);

/** A fresh learner with the demo profile released, so tests do not share progress. */
export async function newLearner(request: APIRequestContext): Promise<string> {
  const login = await request.post('/api/v1/auth/login', {
    headers: CSRF,
    data: { username: 'admin', password: 'e2e-admin-123' },
  });
  expect(login.ok()).toBe(true);
  const username = `kid-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
  const created = await request.post('/api/v1/admin/users', {
    headers: CSRF,
    data: { username, password: PASSWORD, profiles: ['demo-latin'] },
  });
  expect(created.status()).toBe(201);
  return username;
}

export async function login(page: Page, username: string, greeting: string = username) {
  await page.goto('/');
  await page.getByLabel('Benutzername').fill(username);
  await page.getByLabel('Passwort').fill(PASSWORD);
  await page.getByRole('button', { name: 'Anmelden' }).click();
  await expect(page.getByText(`Hallo ${greeting}!`)).toBeVisible();
}

export async function currentEntry(page: Page): Promise<Entry> {
  const word = (await page.locator('.quiz .word .term').innerText()).trim();
  const entry = byLemma.get(word);
  expect(entry, `prompt ${word} is a demo lemma`).toBeDefined();
  return entry!;
}

/** Card number shown in "Karte N von M". */
export async function position(page: Page): Promise<number> {
  return Number((await page.getByText(/^Karte \d+ von/).innerText()).split(' ')[1]);
}

/** Continue to the next card and wait until it is shown (answers are stored async). */
export async function next(page: Page, press: () => Promise<void>) {
  const n = await position(page);
  await press();
  await expect(
    page.getByText(`Karte ${n + 1} von`).or(page.getByRole('heading', { name: 'Geschafft!' })),
  ).toBeVisible();
}

export async function typeAnswer(page: Page, text: string) {
  await page.getByRole('textbox', { name: 'Deine Antwort' }).fill(text);
  await page.getByRole('button', { name: 'Prüfen' }).click();
}

/** Answer every card of the running session correctly. */
export async function answerAllCorrectly(page: Page) {
  for (let i = 0; i < 40; i++) {
    if (await page.getByRole('heading', { name: 'Geschafft!' }).isVisible()) return;
    const entry = await currentEntry(page);
    await typeAnswer(page, entry.tr.de[0]);
    await expect(page.getByText('Richtig!')).toBeVisible();
    await next(page, () => page.getByRole('button', { name: 'Weiter' }).click());
  }
  throw new Error('session did not end');
}

/** What the app does when it comes back to the foreground. */
export async function backToForeground(page: Page) {
  await page.evaluate(() => document.dispatchEvent(new Event('visibilitychange')));
}
