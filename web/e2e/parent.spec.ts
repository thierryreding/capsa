import { expect, test } from '@playwright/test';
import { currentEntry, login, newLearner, next } from './helpers';

test('parent mode: the solution is shown at once, the parent judges', async ({ page, request }) => {
  await login(page, await newLearner(request));
  await page.getByLabel('Abfrage').selectOption('Abfragen lassen');
  await page.getByRole('button', { name: /Los geht’s \(10 Karten\)/ }).click();

  await expect(page.getByText(/Die Lösung siehst nur du/)).toBeVisible();
  await expect(page.getByRole('textbox')).toBeHidden();
  for (let i = 0; i < 10; i++) {
    const entry = await currentEntry(page);
    await expect(page.locator('.solution')).toContainText(entry.tr.de[0]);
    const right = i !== 0; // the first one is wrong, it comes back later
    await next(page, () => page.getByRole('button', { name: right ? 'Richtig' : 'Falsch' }).click());
  }
  // The card judged wrong comes back once more.
  await currentEntry(page);
  await next(page, () => page.getByRole('button', { name: 'Richtig' }).click());
  await expect(page.getByText('9 von 10 Karten auf Anhieb richtig.')).toBeVisible();
});
