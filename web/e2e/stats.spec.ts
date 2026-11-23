import { expect, test } from '@playwright/test';
import { answerAllCorrectly, currentEntry, login, newLearner, next, typeAnswer } from './helpers';

test('statistics: the child on the device and the parent from the server agree', async ({ page, browser, request }) => {
  const kid = await newLearner(request);
  await login(page, kid);
  await page.getByRole('button', { name: /Los geht’s/ }).click();
  const missed = await currentEntry(page);
  await typeAnswer(page, 'keine Ahnung');
  await next(page, () => page.getByRole('button', { name: 'Weiter' }).click());
  await answerAllCorrectly(page); // incl. the missed card when it comes back
  await page.getByRole('button', { name: 'Zur Übersicht' }).click();
  await expect(page.locator('footer.sync')).toContainText('Zuletzt synchronisiert');

  // The child's statistics, computed on the device.
  await page.getByRole('button', { name: 'Statistik' }).click();
  const mine = page.locator('.stats');
  await expect(mine).toContainText('11 Antworten insgesamt');
  await expect(mine.locator('.hardest')).toContainText(missed.lemma);
  await expect(mine.locator('.hardest')).toContainText('1× falsch, 1× richtig');
  await mine.getByText('Als Tabelle').click();
  await expect(mine.locator('tbody tr').last()).toContainText('10');
  await mine.locator('.chart .day').last().focus();
  await expect(mine.locator('.readout')).toContainText('10 richtig, 1 falsch');
  const childView = (await mine.locator('.stat-units').innerText()).replace(/\s+/g, ' ');

  // The parent's view of the same child, computed by the server.
  const parent = await (await browser.newContext(test.info().project.use)).newPage();
  await parent.goto('/');
  await parent.getByLabel('Benutzername').fill('admin');
  await parent.getByLabel('Passwort').fill('e2e-admin-123');
  await parent.getByRole('button', { name: 'Anmelden' }).click();
  await parent.getByRole('button', { name: 'Verwaltung' }).click();
  const row = parent.locator('li.user', { hasText: kid });
  await row.getByRole('button', { name: 'Fortschritt' }).click();
  const theirs = row.locator('.stats');
  await expect(theirs).toContainText('11 Antworten insgesamt');
  await expect(theirs.locator('.hardest')).toContainText(missed.lemma);
  expect((await theirs.locator('.stat-units').innerText()).replace(/\s+/g, ' ')).toBe(childView);
});
