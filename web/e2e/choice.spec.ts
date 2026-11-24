import { expect, test } from '@playwright/test';
import { currentEntry, login, newLearner, next } from './helpers';

test('multiple choice: tap or press a number, right and wrong are shown', async ({ page, request }) => {
  await login(page, await newLearner(request));
  await page.getByLabel('Abfrage').selectOption('Multiple Choice');
  await page.getByRole('button', { name: /Los geht’s \(10 Karten\)/ }).click();

  const options = page.getByRole('list', { name: 'Antwortmöglichkeiten' }).getByRole('button');
  let wrongShown = false;
  let usedKeyboard = false;
  for (let i = 0; i < 20; i++) {
    if (await page.getByRole('heading', { name: 'Geschafft!' }).isVisible()) break;
    const entry = await currentEntry(page);
    const right = entry.tr.de.join(', ');
    await expect(options).toHaveCount(4);
    const texts = (await options.allInnerTexts()).map((x) => x.replace(/^\d\s*/, '').trim());
    expect(texts.filter((x) => x === right)).toHaveLength(1);

    if (!wrongShown) {
      // Pick a wrong option: it turns red, the right one green.
      const wrong = texts.findIndex((x) => x !== right);
      await options.nth(wrong).click();
      await expect(page.getByText('Leider falsch.')).toBeVisible();
      await expect(options.nth(wrong)).toHaveClass(/wrong/);
      await expect(options.nth(texts.indexOf(right))).toHaveClass(/right/);
      wrongShown = true;
    } else if (!usedKeyboard) {
      await page.keyboard.press(String(texts.indexOf(right) + 1));
      await expect(page.getByText('Richtig!')).toBeVisible();
      usedKeyboard = true;
    } else {
      await options.nth(texts.indexOf(right)).click();
      await expect(page.getByText('Richtig!')).toBeVisible();
    }
    await next(page, () => page.getByRole('button', { name: 'Weiter' }).click());
  }
  await expect(page.getByText('9 von 10 Karten auf Anhieb richtig.')).toBeVisible();
});
