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

  // Offline: the change is kept on the device and synced later.
  await page.evaluate(() => navigator.serviceWorker.ready);
  await context.setOffline(true);
  await page.getByRole('button', { name: 'Hallo Lena!' }).click();
  await page.getByLabel('Wie sollen wir dich nennen?').fill('Lenchen');
  await page.getByRole('button', { name: 'Speichern' }).click();
  await expect(page.getByRole('button', { name: 'Hallo Lenchen!' })).toBeVisible();
  await page.reload();
  await expect(page.getByRole('button', { name: 'Hallo Lenchen!' })).toBeVisible();
  await context.setOffline(false);
  await page.evaluate(() => window.dispatchEvent(new Event('online')));
  await expect(page.locator('footer.sync')).toContainText('Zuletzt synchronisiert');

  // Another device gets the new name.
  const other = await (await page.context().browser()!.newContext(test.info().project.use)).newPage();
  await login(other, kid, 'Lenchen');
  await other.context().close();
  await page.getByRole('button', { name: 'Hallo Lenchen!' }).click();
  await page.getByLabel('Wie sollen wir dich nennen?').fill('Lena');
  await page.getByRole('button', { name: 'Speichern' }).click();
  await expect(page.getByRole('button', { name: 'Hallo Lena!' })).toBeVisible();

  // Empty clears it: back to the username.
  await context.setOffline(false);
  await page.getByRole('button', { name: 'Hallo Lena!' }).click();
  await page.getByLabel('Wie sollen wir dich nennen?').fill('');
  await page.getByRole('button', { name: 'Speichern' }).click();
  await expect(page.getByRole('button', { name: `Hallo ${kid}!` })).toBeVisible();
});
