import { expect, test } from '@playwright/test';

const archive = {
  format: 1,
  id: '11111111-1111-4111-8111-111111111111',
  replay: {
    rulesVersion: '2.1',
    createdAt: 0,
    deals: [
      {
        round: 1,
        dealerSeat: 0,
        attackingTeam: 'A',
        hands: [[{ id: 'card-1', kind: 'suited', suit: 'hearts', rank: 'A' }]],
      },
    ],
  },
  events: [
    {
      revision: 1,
      actor: 'bot',
      action: 'play',
      seat: 1,
      round: 1,
      trick: 1,
      detail: 'follow',
      rating: 'necessary_ruff',
      cardIds: ['card-1'],
      at: 1000,
    },
    {
      revision: 2,
      actor: 'bot',
      action: 'play',
      detail: 'follow',
      rating: 'protected_partner',
      cardIds: [],
      at: 2000,
    },
  ],
};

test('replay viewer plays and marks strategy decisions', async ({ page }) => {
  await page.goto('/replay');
  await page.locator('input[type="file"]').setInputFiles({
    name: 'sample-replay.json',
    mimeType: 'application/json',
    buffer: Buffer.from(JSON.stringify(archive)),
  });
  const panel = page.getByRole('region', { name: 'Replay timeline' });
  await expect(panel.getByText('necessary ruff')).toBeVisible();
  await expect(panel.getByText('protected partner')).toBeVisible();
  await expect(
    panel
      .getByRole('region', { name: 'Animated replay table' })
      .getByText('A hearts'),
  ).toBeVisible();
  await panel.getByRole('button', { name: 'Beginning' }).click();
  await panel.getByRole('button', { name: 'Play replay' }).click();
  await expect(panel.getByText('1 / 2')).toBeVisible({ timeout: 3000 });
  await panel.getByRole('button', { name: 'Pause replay' }).click();
  await expect(
    panel.getByRole('button', { name: 'Play replay' }),
  ).toBeVisible();
});
