import { expect, test } from '@playwright/test';
import { login, newLearner, PASSWORD } from './helpers';

const ADMIN_PASSWORD = 'e2e-admin-123';

async function loginAdmin(page: import('@playwright/test').Page) {
  await page.goto('/');
  await page.getByLabel('Benutzername').fill('admin');
  await page.getByLabel('Passwort').fill(ADMIN_PASSWORD);
  await page.getByRole('button', { name: 'Anmelden' }).click();
  await page.getByRole('button', { name: 'Verwaltung' }).click();
  await expect(page.getByRole('heading', { name: 'Konten' })).toBeVisible();
}

test('parents manage accounts from the app', async ({ page, browser }) => {
  const kid = `kid${Date.now().toString(36)}`;
  await loginAdmin(page);

  // Create a learner with a book and a display name.
  await page.getByRole('button', { name: 'Neues Konto' }).click();
  const form = page.locator('section', { has: page.getByRole('heading', { name: 'Neues Konto' }) });
  await form.getByLabel('Benutzername', { exact: true }).fill(kid);
  await form.getByLabel('Passwort', { exact: true }).fill('kurz');
  await form.getByRole('button', { name: 'Konto anlegen' }).click();
  await expect(form.getByRole('alert')).toContainText('mindestens 8');
  await form.getByLabel('Passwort', { exact: true }).fill(PASSWORD);
  await form.getByLabel('Name zur Begrüßung').fill('Ida');
  await form.getByLabel('Demo: Latein am Meer').check();
  await form.getByRole('button', { name: 'Konto anlegen' }).click();
  await expect(page.getByText('Konto Ida angelegt.')).toBeVisible();
  const row = page.locator('li.user', { hasText: kid });
  await expect(row).toContainText('Demo: Latein am Meer');

  // The child signs in and is greeted by name.
  const child = await (await browser.newContext(test.info().project.use)).newPage();
  await login(child, kid, 'Ida');
  await expect(child.getByRole('heading', { name: 'Demo: Latein am Meer' })).toBeVisible();
  await expect(child.getByRole('button', { name: 'Verwaltung' })).toBeHidden();

  // Reset the password: the child's sessions end, the new password works.
  await row.getByRole('button', { name: 'Bearbeiten' }).click();
  await row.getByLabel('Neues Passwort').fill('neues-passwort');
  await row.getByRole('button', { name: 'Passwort setzen' }).click();
  await expect(row.getByRole('status')).toContainText('überall abgemeldet');

  // Disable: the child cannot sign in any more.
  await row.getByRole('button', { name: 'Sperren' }).click();
  await expect(row).toContainText('gesperrt');
  const again = await (await browser.newContext(test.info().project.use)).newPage();
  await again.goto('/');
  await again.getByLabel('Benutzername').fill(kid);
  await again.getByLabel('Passwort').fill('neues-passwort');
  await again.getByRole('button', { name: 'Anmelden' }).click();
  await expect(again.getByRole('alert')).toContainText('falsch');

  // Admins cannot disable themselves; the button is not offered.
  const me = page.locator('li.user', { hasText: '– du' });
  await me.getByRole('button', { name: 'Bearbeiten' }).click();
  await expect(me.getByRole('button', { name: 'Sperren' })).toBeHidden();
});

test('learners do not see the admin page', async ({ page, request }) => {
  await login(page, await newLearner(request));
  await expect(page.getByRole('button', { name: 'Verwaltung' })).toBeHidden();
});
