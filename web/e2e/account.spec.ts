import { expect, test } from '@playwright/test';
import { login, newLearner } from './helpers';

test('learners choose the name the app greets them with', async ({ page, context, request }) => {
  const kid = await newLearner(request);
  await login(page, kid);

  await page.getByRole('button', { name: `Hallo ${kid}!` }).click();
  await page.getByLabel('Wie sollen wir dich nennen?').fill('  Lena  ');
  await page.getByRole('button', { name: 'Speichern' }).click();
  await expect(page.getByRole('button', { name: 'Hallo Lena!' })).toBeVisible();

  await page.reload();
  await expect(page.getByRole('button', { name: 'Hallo Lena!' })).toBeVisible();

  // Too long: refused before sending, the form stays open.
  await page.getByRole('button', { name: 'Hallo Lena!' }).click();
  await page.getByLabel('Wie sollen wir dich nennen?').evaluate((el: HTMLInputElement) => {
    el.removeAttribute('maxlength');
  });
  await page.getByLabel('Wie sollen wir dich nennen?').fill('x'.repeat(65));
  await page.getByRole('button', { name: 'Speichern' }).click();
  await expect(page.getByRole('alert')).toContainText('höchstens 64 Zeichen');
  await page.getByRole('button', { name: 'Abbrechen' }).click();

  // Offline: a clear message; the cached name still shows on an offline start.
  await page.evaluate(() => navigator.serviceWorker.ready);
  await context.setOffline(true);
  await page.getByRole('button', { name: 'Hallo Lena!' }).click();
  await page.getByLabel('Wie sollen wir dich nennen?').fill('Lenchen');
  await page.getByRole('button', { name: 'Speichern' }).click();
  await expect(page.getByRole('alert')).toContainText('nur mit Internetverbindung');
  await page.reload();
  await expect(page.getByRole('button', { name: 'Hallo Lena!' })).toBeVisible();

  // Empty clears it: back to the username.
  await context.setOffline(false);
  await page.getByRole('button', { name: 'Hallo Lena!' }).click();
  await page.getByLabel('Wie sollen wir dich nennen?').fill('');
  await page.getByRole('button', { name: 'Speichern' }).click();
  await expect(page.getByRole('button', { name: `Hallo ${kid}!` })).toBeVisible();
});
