import { expect, test } from '@playwright/test';

test('deals each table size, selects cards, and clears the hand selection', async ({
  page,
}, testInfo) => {
  await page.goto('/');
  await expect(
    page.getByRole('heading', { name: '25 cards. A little possibility.' }),
  ).toBeVisible();
  for (const count of [6, 8, 10, 4]) {
    await page.getByRole('radio', { name: String(count), exact: true }).check();
    await page.getByRole('button', { name: 'Deal a sample hand' }).click();
    await expect(page.locator('.seat')).toHaveCount(count);
    await expect(page.locator('.playing-card')).toHaveCount(
      count === 4 ? 25 : 26,
    );
    if (count === 10) {
      await page.screenshot({
        path: testInfo.outputPath('ten-player-table.png'),
        fullPage: true,
      });
      expect(
        await page.evaluate(
          () => document.documentElement.scrollWidth <= window.innerWidth,
        ),
      ).toBe(true);
    }
  }
  const card = page.locator('.playing-card').first();
  await card.focus();
  await page.keyboard.press('Space');
  await expect(card).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByText('1 selected', { exact: true })).toBeVisible();
  await expect(page.getByText('Single', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Clear selection' }).click();
  await expect(card).toHaveAttribute('aria-pressed', 'false');
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
});

test('uses no-suit trump and deck-scaled scoring', async ({ page }) => {
  await page.goto('/');
  await expect(
    page.getByRole('button', { name: 'Deal a sample hand' }),
  ).toBeEnabled();
  await page.getByRole('radio', { name: '6', exact: true }).check();
  await page
    .getByRole('combobox', { name: 'Trump', exact: true })
    .selectOption('none');
  await page
    .getByRole('combobox', { name: 'Level', exact: true })
    .selectOption('5');
  await page.getByRole('button', { name: 'Deal a sample hand' }).click();
  await expect(page.locator('.trump-tag')).toContainText('No-suit trump');
  await expect(page.locator('.seat')).toHaveCount(6);
  const score = page.getByRole('slider', { name: 'Defender points' });
  await score.focus();
  await page.keyboard.press('Home');
  for (let step = 0; step < 28; step++) await page.keyboard.press('ArrowRight');
  await expect(
    page.getByText('Defenders take over', { exact: true }),
  ).toBeVisible();
  for (let step = 0; step < 48; step++) await page.keyboard.press('ArrowRight');
  await expect(
    page.getByText('Defenders +4 levels', { exact: true }),
  ).toBeVisible();
});

test('shows an actionable connection failure and retries', async ({ page }) => {
  await page.route('**/api/practice-preview', (route) =>
    route.fulfill({ status: 503, body: '{}' }),
  );
  await page.goto('/');
  await expect(page.getByRole('alert')).toContainText(
    'Could not reach the table',
  );
  await page.unroute('**/api/practice-preview');
  await page.getByRole('button', { name: 'Deal a sample hand' }).click();
  await expect(page.locator('.playing-card')).toHaveCount(25);
  await expect(page.getByRole('alert')).toHaveCount(0);
});

test('opens a server-judged trick drill and explains an illegal selection', async ({
  page,
}) => {
  await page.goto('/');
  await expect(
    page.getByRole('heading', { name: 'Play the tricky parts.' }),
  ).toBeVisible();
  await page.getByRole('button', { name: /Keep the pair together/ }).click();
  await expect(
    page.getByRole('heading', { name: 'Keep the pair together' }),
  ).toBeVisible();
  const cards = page.locator('#trick-drills .playing-card');
  await cards.first().click();
  await page.getByRole('button', { name: 'Play selected cards' }).click();
  await expect(
    page.getByText('Play exactly 4 cards.', { exact: true }),
  ).toBeVisible();
  await page.getByRole('button', { name: 'All drills' }).click();
  await expect(
    page.getByRole('button', { name: /Two pairs still matter/ }),
  ).toBeVisible();
});
