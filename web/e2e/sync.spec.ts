import { expect, test, type Browser, type Page } from '@playwright/test';
import {
  answerAllCorrectly,
  backToForeground,
  currentEntry,
  login,
  newLearner,
  next,
  typeAnswer,
} from './helpers';

/** A separate browser profile: its own IndexedDB and cookies, like a second device. */
async function device(browser: Browser): Promise<Page> {
  const context = await browser.newContext({ ...test.info().project.use });
  return context.newPage();
}

const unit = (page: Page, title: string) => page.locator('label.unit', { hasText: title });
const syncStatus = (page: Page) => page.locator('footer.sync');

test('two devices share progress and settings through the server', async ({ browser, request }) => {
  const kid = await newLearner(request);
  const phone = await device(browser);
  const tablet = await device(browser);

  // Phone: learn all ten new cards of unit 1; the end of the session syncs.
  await login(phone, kid);
  await expect(unit(phone, 'Am Hafen')).toContainText('10 neu');
  await phone.getByRole('button', { name: /Los geht’s/ }).click();
  await answerAllCorrectly(phone);
  await phone.getByRole('button', { name: 'Zur Übersicht' }).click();
  await expect(syncStatus(phone)).toContainText('Zuletzt synchronisiert');
  await expect(syncStatus(phone)).not.toContainText('noch nicht übertragen');

  // Phone: choose flashcards; the choice is a synced setting.
  await phone.getByText('Karteikarte').click();

  // Tablet: signs in and sees the phone's progress.
  await login(tablet, kid);
  await expect(unit(tablet, 'Am Hafen')).toContainText('0 neu');
  await expect(unit(tablet, 'Auf dem Meer')).toContainText('9 neu');

  // The setting arrives once the phone has synced it (debounced) and the tablet refreshes.
  await expect(async () => {
    await backToForeground(phone);
    await backToForeground(tablet);
    await expect(tablet.getByRole('radio', { name: 'Karteikarte' })).toBeChecked({ timeout: 1000 });
  }).toPass({ timeout: 15_000 });
});

test('answers given offline are uploaded when the network returns', async ({ browser, request }) => {
  const kid = await newLearner(request);
  const phone = await device(browser);
  const tablet = await device(browser);
  await login(phone, kid);
  await login(tablet, kid);

  // Tablet goes offline and gets one card wrong.
  await tablet.context().setOffline(true);
  await tablet.getByRole('button', { name: /Los geht’s/ }).click();
  await currentEntry(tablet);
  await typeAnswer(tablet, 'keine Ahnung');
  await next(tablet, () => tablet.getByRole('button', { name: 'Weiter' }).click());
  await tablet.getByRole('button', { name: 'Beenden' }).click();
  await tablet.getByRole('button', { name: 'Zur Übersicht' }).click();
  await expect(syncStatus(tablet)).toContainText('1 Antwort noch nicht übertragen');
  await expect(tablet.getByText(/^Offline/)).toBeVisible();

  // Back online: the app syncs by itself.
  await tablet.context().setOffline(false);
  await tablet.evaluate(() => window.dispatchEvent(new Event('online')));
  await expect(syncStatus(tablet)).not.toContainText('noch nicht übertragen');
  await expect(tablet.getByText(/^Offline/)).toBeHidden();

  // The phone sees the mistake after coming back to the foreground.
  await backToForeground(phone);
  await expect(phone.locator('label.unit').getByText(/1 Fehler/)).toBeVisible();
});

test('signing out uploads pending answers first', async ({ browser, request }) => {
  const kid = await newLearner(request);
  const tablet = await device(browser);
  await login(tablet, kid);

  // An answer stays pending while the server cannot be reached ...
  await tablet.route('**/api/v1/sync/**', (route) => route.abort());
  await tablet.getByRole('button', { name: /Los geht’s/ }).click();
  await currentEntry(tablet);
  await typeAnswer(tablet, 'keine Ahnung');
  await next(tablet, () => tablet.getByRole('button', { name: 'Weiter' }).click());
  await tablet.getByRole('button', { name: 'Beenden' }).click();
  await tablet.getByRole('button', { name: 'Zur Übersicht' }).click();
  await expect(syncStatus(tablet)).toContainText('1 Antwort noch nicht übertragen');

  // ... and is uploaded when signing out with the server reachable again.
  await tablet.unroute('**/api/v1/sync/**');
  await tablet.getByRole('button', { name: 'Abmelden' }).click();
  await expect(tablet.getByRole('button', { name: 'Anmelden' })).toBeVisible();

  const phone = await device(browser);
  await login(phone, kid);
  await expect(phone.locator('label.unit').getByText(/1 Fehler/)).toBeVisible();
});
