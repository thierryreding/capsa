import { expect, test } from '@playwright/test';
import { answerAllCorrectly, backToForeground, login, newLearner } from './helpers';

test('plan a test, practise for it, see the progress on another device', async ({ page, browser, request }) => {
  const kid = await newLearner(request);
  await login(page, kid);

  // Only unit 1 for the test.
  await page.locator('label.unit', { hasText: 'Auf dem Meer' }).getByRole('checkbox').uncheck();
  await page.getByRole('button', { name: 'Test planen' }).click();
  const tomorrow = await page.evaluate(() => {
    const d = new Date(Date.now() + 86_400_000);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  });
  await page.getByLabel('Wann ist der Test?').fill('2000-01-01');
  await page.getByRole('button', { name: 'Test planen' }).click();
  // The date picker refuses past dates (min); nothing is saved.
  await expect(page.getByLabel('Wann ist der Test?')).toBeVisible();
  await expect(page.locator('section.test-plan h2')).toHaveCount(0);
  await page.getByLabel('Wann ist der Test?').fill(tomorrow);
  await page.getByRole('button', { name: 'Test planen' }).click();

  const card = page.locator('section.test-plan');
  await expect(card.getByRole('heading')).toHaveText('Test morgen');
  await expect(card).toContainText('Lektionen 1');
  await expect(card).toContainText('0 von 10 Karten sicher');
  await expect(card).toContainText('Heute noch 20 richtige Antworten.'); // 10 new cards x 2

  await card.getByRole('button', { name: 'Für den Test üben' }).click();
  await answerAllCorrectly(page);
  await page.getByRole('button', { name: 'Zur Übersicht' }).click();
  await expect(card).toContainText('Heute noch 10 richtige Antworten.');

  // Another device: the plan is a synced setting.
  const other = await (await browser.newContext(test.info().project.use)).newPage();
  await expect(async () => {
    await backToForeground(page);
    await login(other, kid);
    await expect(other.locator('section.test-plan').getByRole('heading')).toHaveText('Test morgen', { timeout: 1000 });
  }).toPass({ timeout: 20_000 });
  await expect(other.locator('section.test-plan')).toContainText('Heute noch 10 richtige Antworten.');

  // A second round finishes today's goal: every card reaches box 3.
  await card.getByRole('button', { name: 'Für den Test üben' }).click();
  await answerAllCorrectly(page);
  await page.getByRole('button', { name: 'Zur Übersicht' }).click();
  await expect(card).toContainText('10 von 10 Karten sicher');
  await expect(card).toContainText('Alles sicher');

  await card.getByRole('button', { name: 'Test entfernen' }).click();
  await expect(card.getByRole('button', { name: 'Test planen' })).toBeVisible();
});
