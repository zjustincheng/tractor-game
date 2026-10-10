import { expect, test } from '@playwright/test';

test('quick match is discoverable from setup and the active table', async ({
  page,
}, testInfo) => {
  await page.goto('/');
  await expect(
    page.getByRole('heading', { name: 'Take a seat.' }),
  ).toBeVisible();
  const quick = page.getByRole('checkbox', { name: /One-round quick match/ });
  await quick.check();
  await expect(quick).toBeChecked();
  await page.screenshot({
    path: testInfo.outputPath('setup.png'),
    fullPage: true,
  });
  await page
    .getByRole('button', { name: 'Start bot match', exact: true })
    .click();
  await expect(
    page.getByText(/One-round match · starting level/),
  ).toBeVisible();
  const restart = page.getByRole('button', {
    name: 'New one-round quick match',
  });
  await expect(restart).toBeVisible();
  expect(await restart.evaluate((el) => Boolean(el.closest('details')))).toBe(
    false,
  );
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
  await page.screenshot({
    path: testInfo.outputPath('table.png'),
    fullPage: true,
  });
  await page.getByRole('link', { name: 'Play with friends' }).click();
  await expect(page).toHaveURL(/#play-room$/);
  await expect(
    page.getByRole('button', { name: 'Create room' }),
  ).toBeInViewport();
});
