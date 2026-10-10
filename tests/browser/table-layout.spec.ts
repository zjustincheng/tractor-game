import { expect, test } from '@playwright/test';
import { newBotMatch, commandBotMatch } from '../../backend/src/bot-match.js';
import { botView } from '../../backend/src/bot-routes.js';
import { startTrick } from '@tractor/rules';

for (const playerCount of [4, 10] as const) {
  test(`felt table supports manual and watch play with ${playerCount} seats`, async ({
    page,
  }, testInfo) => {
    let seed = 42;
    const pick = (max: number) =>
      (seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) % max;
    let match = newBotMatch(playerCount, 0, pick);
    const trump = { level: '2', suit: 'spades' } as const;
    match = {
      ...match,
      state: {
        ...match.state,
        phase: 'tricks',
        trump,
        trick: startTrick({
          playerCount,
          hands: match.state.hands,
          trump,
          attackingTeam: 'A',
          leaderSeat: 0,
        }),
      },
    };
    const id = '11111111-1111-4111-8111-111111111111';
    let revision = 0;
    await page.route('**/api/bot-matches**', async (route) => {
      if (route.request().url().endsWith('/commands')) {
        match = commandBotMatch(
          match,
          route.request().postDataJSON(),
          50000,
          pick,
        );
        revision++;
      }
      await route.fulfill({ json: botView(id, match, revision) });
    });
    await page.goto('/');
    await page
      .getByRole('button', { name: 'Start bot match', exact: true })
      .click();
    const table = page.locator('#bot-match');
    await expect(table.locator('.table-seat')).toHaveCount(playerCount);
    await expect(table.locator('.hand-card')).toHaveCount(
      match.state.hands[0]!.length,
    );
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await table
      .getByRole('button', { name: 'Suggest cards', exact: true })
      .click();
    await expect(
      table.locator('.hand-card[aria-pressed="true"]').first(),
    ).toBeVisible();
    await table.getByRole('button', { name: /^Play cards/ }).click();
    await expect(table.locator('.table-play')).toHaveCount(playerCount, {
      timeout: 15000,
    });
    await expect(
      table.getByRole('button', { name: 'Next trick', exact: true }),
    ).toBeVisible();
    await table.screenshot({ path: testInfo.outputPath('felt-table.png') });
    await table.getByRole('button', { name: 'Watch bots play' }).click();
    await expect(
      table.getByText('Round 1 · Trick 2', { exact: true }),
    ).toBeVisible({ timeout: 10000 });
    await table.getByRole('button', { name: 'Pause', exact: true }).click();
    await expect(table.getByRole('status')).toHaveText('Paused');
    await expect(table.locator('.hand-card').first()).toBeDisabled();
    await table.getByRole('button', { name: 'Stop watching' }).click();
    await expect(
      table.getByRole('button', { name: /^(Next trick|Play cards)/ }),
    ).toBeVisible({ timeout: 15000 });
    await expect(table.getByRole('alert')).toHaveCount(0);
  });
}
