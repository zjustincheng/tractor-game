import { expect, test } from '@playwright/test';

test('creates a private room and shows the lobby', async ({ page }) => {
  await page.goto('/');
  const room = page.locator('#play-room');
  await expect(
    room.getByRole('heading', { name: 'Join a live room.' }),
  ).toBeVisible();
  await room.getByLabel('Name').first().fill('Browser Host');
  await room.getByRole('button', { name: 'Create room' }).click();
  await expect(
    room.getByRole('heading', { name: /Room [A-Z2-9]{6}/ }),
  ).toBeVisible();
  await expect(room.getByText('Browser Host')).toBeVisible();
  await expect(room.getByRole('button', { name: 'Ready up' })).toBeVisible();
});
