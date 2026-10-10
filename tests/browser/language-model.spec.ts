import { expect, test } from '@playwright/test';
test('does not expose the paid language-model match option', async ({
  page,
}) => {
  await page.goto('/');
  await expect(
    page.getByRole('checkbox', { name: 'Play against a language model' }),
  ).toHaveCount(0);
});
