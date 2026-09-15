import { expect, test } from '@playwright/test';

test('plays a bot round, resumes it, and advances to the next round', async ({
  page,
}) => {
  test.setTimeout(90000);
  await page.goto('/');
  const table = page.locator('#bot-match');
  await table
    .getByRole('button', { name: 'Start bot match', exact: true })
    .click();
  await expect(
    table.getByText('Round 1 · Trick 1', { exact: true }),
  ).toBeVisible();
  await expect(
    table.getByRole('button', { name: 'Finalize trump' }),
  ).toBeEnabled({ timeout: 12000 });
  await table.getByRole('button', { name: 'Finalize trump' }).click();
  await expect(table.locator('.bot-score-detail')).toContainText('captured +');
  // Resume uses the private session ID and server state, including a pending human decision.
  await page.reload();
  await table.getByRole('button', { name: 'Resume bot match' }).click();
  await expect(
    table.getByText('Round 1 · Trick 1', { exact: true }),
  ).toBeVisible();
  for (let step = 0; step < 80; step++) {
    if (
      await table.getByRole('heading', { name: 'Round 1 results' }).isVisible()
    )
      break;
    const next = table.getByRole('button', { name: 'Next trick', exact: true });
    const finalize = table.getByRole('button', { name: 'Finalize trump' });
    if (await finalize.isVisible()) {
      await expect(finalize).toBeEnabled({ timeout: 12000 });
      await finalize.click();
    } else if (await next.isVisible()) await next.click();
    else {
      await table.getByRole('button', { name: 'Suggest cards' }).click();
      await expect(table.getByText(/selected · \d+ points/)).toBeVisible();
      const bury = table.getByRole('button', { name: 'Bury selected cards' });
      if (await bury.isVisible()) await bury.click();
      else
        await table
          .getByRole('button', { name: 'Play cards', exact: true })
          .click();
    }
    await expect(
      table.getByRole('button', { name: 'Refresh match' }),
    ).toBeEnabled();
    await expect(table.getByRole('alert')).toHaveCount(0);
  }
  await expect(
    table.getByRole('heading', { name: 'Round 1 results' }),
  ).toBeVisible();
  await table.getByRole('button', { name: 'Start next round' }).click();
  await expect(
    table.getByText('Round 2 · Trick 1', { exact: true }),
  ).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
});
