import { expect, test } from '@playwright/test';

test('pauses and skips paced bot turns without enabling human actions early', async ({
  page,
}) => {
  test.setTimeout(60000);
  await page.goto('/');
  const table = page.locator('#bot-match');
  await table
    .getByRole('button', { name: 'Start bot match', exact: true })
    .click();
  await table.getByRole('combobox', { name: 'Bot pace' }).selectOption('1000');
  await expect(
    table.getByRole('status').filter({ hasText: /^Dealing/ }),
  ).toBeVisible();
  await expect(
    table.getByRole('button', { name: 'Finalize trump' }),
  ).toBeDisabled();
  await page.waitForTimeout(1500);
  await expect(
    table.getByRole('status').filter({ hasText: /^Dealing/ }),
  ).toBeVisible();
  const progress = await table.locator('.hand-card').count();
  expect(progress).toBeGreaterThan(0);
  expect(progress).toBeLessThan(25);
  const finalize = table.getByRole('button', { name: 'Finalize trump' });
  await expect(finalize).toBeEnabled({ timeout: 25000 });
  await Promise.all([
    page.waitForResponse((response) => response.url().endsWith('/commands')),
    finalize.click(),
  ]);
  // With no human call, the rules use a fallback declaration and open one
  // additional overturn window before the kitty phase.
  const fallbackFinalize = table.getByRole('button', {
    name: 'Finalize trump',
  });
  for (
    let attempt = 0;
    attempt < 2 && (await fallbackFinalize.isVisible());
    attempt++
  ) {
    await expect(fallbackFinalize).toBeEnabled({ timeout: 12000 });
    await fallbackFinalize.click();
    if (attempt === 0) await page.waitForTimeout(8500);
  }
  const pause = table.getByRole('button', { name: 'Pause', exact: true });
  for (let step = 0; step < 5 && !(await pause.isVisible()); step++) {
    await table.getByRole('button', { name: 'Suggest cards' }).click();
    const bury = table.getByRole('button', { name: /^Bury selected cards/ });
    const action = (await bury.isVisible())
      ? bury
      : table.getByRole('button', { name: /^Play cards/ });
    await Promise.all([
      page.waitForResponse((response) => response.url().endsWith('/commands')),
      action.click(),
    ]);
  }
  await pause.click();
  const count = await table.locator('.table-play').count();
  await table.getByText('Match details & settings', { exact: true }).click();
  await expect(
    table.getByRole('button', { name: 'Refresh match' }),
  ).toBeDisabled();
  await page.waitForTimeout(1200);
  expect(await table.locator('.table-play').count()).toBe(count);
  await table.getByRole('button', { name: 'Show remaining plays' }).click();
  await expect(
    table.getByRole('button', { name: 'Refresh match' }),
  ).toBeEnabled();
  expect(await table.locator('.table-play').count()).toBeGreaterThan(count);
  await expect(table.getByRole('alert')).toHaveCount(0);
});

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
  await expect(table.locator('.table-seat')).toHaveCount(4);
  await table.getByRole('combobox', { name: 'Bot pace' }).selectOption('0');
  await expect(
    table.getByRole('button', { name: 'Finalize trump' }),
  ).toBeEnabled({ timeout: 25000 });
  await table.getByRole('button', { name: 'Finalize trump' }).click();
  // Resume uses the private session ID and server state, including a pending human decision.
  await page.reload();
  await table.getByRole('button', { name: 'Resume bot match' }).click();
  await table.getByRole('combobox', { name: 'Bot pace' }).selectOption('0');
  await table.getByText('Match details & settings', { exact: true }).click();
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
      await expect(finalize).toBeEnabled({ timeout: 25000 });
      await finalize.click();
    } else if (await next.isVisible()) await next.click();
    else {
      await table.getByRole('button', { name: 'Suggest cards' }).click();
      await expect(
        table.locator('.hand-card[aria-pressed="true"]').first(),
      ).toBeVisible();
      const bury = table.getByRole('button', { name: /^Bury selected cards/ });
      if (await bury.isVisible()) await bury.click();
      else await table.getByRole('button', { name: /^Play cards/ }).click();
    }
    await expect(
      table.getByRole('button', { name: 'Refresh match' }),
    ).toBeEnabled();
    await expect(table.getByRole('alert')).toHaveCount(0);
  }
  await expect(
    table.getByRole('heading', { name: 'Round 1 results' }),
  ).toBeVisible();
  await table.getByText(/^Trick history \(/).click();
  await expect(table.getByText(/Round 1 · Trick 1 — Seat/)).toBeVisible();
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

test('can declare during the deal without restarting the card reveal', async ({
  page,
}) => {
  const { newBotMatch, commandBotMatch } =
    await import('../../backend/src/bot-match.js');
  const { botView } = await import('../../backend/src/bot-routes.js');
  const id = '11111111-1111-4111-8111-111111111111';
  let match: ReturnType<typeof newBotMatch>;
  let option: ReturnType<typeof botView>['declarationOptions'][number];
  await page.route('**/api/bot-matches', async (route) => {
    for (let seed = 1; seed <= 1000; seed++) {
      let value = seed;
      match = newBotMatch(4, Date.now(), (max) => {
        value = (Math.imul(value, 1664525) + 1013904223) >>> 0;
        return value % max;
      });
      const view = botView(id, match, 0);
      const early = view.declarationOptions.find((candidate) =>
        candidate.cardIds.every(
          (cardId) => view.hand.findIndex((card) => card.id === cardId) < 12,
        ),
      );
      if (!early) continue;
      option = early;
      await route.fulfill({ json: view });
      return;
    }
    throw new Error('No early declaration fixture');
  });
  await page.route(`**/api/bot-matches/${id}/commands`, async (route) => {
    match = commandBotMatch(
      match,
      route.request().postDataJSON(),
      Date.now(),
      () => 0,
    );
    await route.fulfill({ json: botView(id, match, 1) });
  });
  await page.goto('/');
  const table = page.locator('#bot-match');
  await table
    .getByRole('button', { name: 'Start bot match', exact: true })
    .click();
  await expect(
    table.getByRole('status').filter({ hasText: /^Dealing/ }),
  ).toBeVisible();
  const call = table.getByRole('button', {
    name: `Declare ${option!.multiplicity} × ${option!.suit ?? `${option!.joker} jokers`}`,
    exact: true,
  });
  await expect(call).toBeEnabled({ timeout: 7000 });
  const before = await table.locator('.hand-card').count();
  await call.click();
  await expect(
    table.getByRole('status').filter({ hasText: /^Dealing/ }),
  ).toBeVisible();
  expect(await table.locator('.hand-card').count()).toBeGreaterThanOrEqual(
    before,
  );
  await expect(table.getByRole('alert')).toHaveCount(0);
});

test('human playtest keeps opponents hidden and disables assistance after resume', async ({
  page,
}, testInfo) => {
  test.skip(
    !process.env.BOT_POLICY_FILE,
    'Requires a saved champion loaded by the server.',
  );
  await page.goto('/');
  const table = page.locator('#bot-match');
  await table
    .getByRole('checkbox', {
      name: 'Human playtest (fixed partner, hidden opponents)',
    })
    .check();
  await expect(
    table.getByRole('combobox', { name: 'Bot difficulty', exact: true }),
  ).toBeDisabled();
  const created = page.waitForResponse(
    (response) =>
      response.url().endsWith('/api/bot-matches') &&
      response.request().method() === 'POST',
  );
  await table
    .getByRole('button', { name: 'Start bot match', exact: true })
    .click();
  const view = await (await created).json();
  expect(view.playtest).toMatchObject({
    opponent: null,
    championId: null,
    feedbackCount: 0,
    review: [],
  });
  expect(view.suggestion).toEqual([]);
  await expect(
    table.getByText(
      'Human playtest · Partner: Standard · Opponents: Hidden until match ends',
    ),
  ).toBeVisible();
  await expect(
    table.getByRole('button', { name: 'Watch bots play' }),
  ).toBeDisabled();
  await page.reload();
  await table.getByRole('button', { name: 'Resume bot match' }).click();
  await expect(
    table.getByText(
      'Human playtest · Partner: Standard · Opponents: Hidden until match ends',
    ),
  ).toBeVisible();
  await expect(
    table.getByRole('button', { name: 'Watch bots play' }),
  ).toBeDisabled();
  await table.getByText('Match details & settings', { exact: true }).click();
  for (const name of [
    'Export replay',
    'Export bot behavior CSV',
    'Export bot summary CSV',
  ])
    await expect(
      table.getByRole('button', { name, exact: true }),
    ).toBeDisabled();
  await page.route(`**/api/bot-matches/${view.id}`, async (route) => {
    const response = await route.fetch();
    const completed = await response.json();
    completed.settlement = {
      defenderScore: 0,
      kittyPoints: 0,
      kittyMultiplier: 1,
      levels: { A: 'A', B: '2' },
      attackingTeam: 'A',
      jackReset: false,
      winner: 'A',
    };
    completed.playtest.opponent = 'champion';
    completed.playtest.championId = 'fixture';
    completed.playtest.review = Array.from({ length: 100 }, (_, index) => ({
      id: `00000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`,
      seat: 1,
      kind: 'follow',
      options: [
        { cards: ['Chosen card'], cardIds: [`chosen-${index}`] },
        { cards: ['Alternative card'], cardIds: [`alternative-${index}`] },
      ],
      chosen: 0,
      preferredIndex: null,
    }));
    await route.fulfill({ response, json: completed });
  });
  await table.getByRole('button', { name: 'Refresh match' }).click();
  const resultPanel = page.locator('.felt-scene .bot-result');
  await expect(resultPanel).toContainText('Teach from this match (0/100');
  await resultPanel.getByText(/Teach from this match/).click();
  const teach = resultPanel.getByRole('button', { name: 'Teach' }).first();
  await expect(teach).toBeDisabled();
  await resultPanel.locator('select').first().selectOption('1');
  await expect(teach).toBeEnabled();
  const dimensions = await resultPanel.evaluate((element) => ({
    clientHeight: element.clientHeight,
    overflowY: getComputedStyle(element).overflowY,
    scrollHeight: element.scrollHeight,
  }));
  expect(dimensions.overflowY).toBe('auto');
  expect(dimensions.scrollHeight).toBeGreaterThan(dimensions.clientHeight);
  await resultPanel.evaluate((element) => {
    element.scrollTop = element.scrollHeight;
  });
  expect(
    await resultPanel.evaluate((element) => element.scrollTop),
  ).toBeGreaterThan(0);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
  await page.screenshot({
    path: testInfo.outputPath('human-playtest.png'),
    fullPage: true,
  });
});

test('shows a useful error when the game server returns an empty gateway response', async ({
  page,
}) => {
  await page.goto('/');
  await page.route('**/api/bot-matches', (route) =>
    route.fulfill({ status: 502, body: '' }),
  );
  const table = page.locator('#bot-match');
  await table
    .getByRole('button', { name: 'Start bot match', exact: true })
    .click();
  await expect(table.getByRole('alert')).toContainText(
    'Cannot reach the game server',
  );
  await expect(
    table.getByRole('button', { name: 'Start bot match', exact: true }),
  ).toBeEnabled();
});
