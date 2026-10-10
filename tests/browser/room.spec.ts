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
  await room.getByRole('button', { name: 'Ready up' }).click();
  await expect(room.getByRole('button', { name: 'Not ready' })).toBeVisible();
});

test('four players finish a round, reconnect, and deal the next round', async ({
  page,
  browser,
}) => {
  test.setTimeout(120000);
  const { category } = await import('../../packages/rules/src/cards.js');
  const { roomGameViewSchema } =
    await import('../../packages/protocol/src/index.js');
  const origin = new URL(test.info().project.use.baseURL!).origin;
  const contexts = await Promise.all(
    Array.from({ length: 3 }, () =>
      browser.newContext({ baseURL: origin, viewport: page.viewportSize()! }),
    ),
  );
  const pages = [
    page,
    ...(await Promise.all(contexts.map((context) => context.newPage()))),
  ];
  try {
    await page.goto('/');
    const hostRoom = page.locator('#play-room');
    await hostRoom.getByLabel('Name').fill('Host');
    await hostRoom.getByRole('button', { name: 'Create room' }).click();
    await expect(
      hostRoom.getByRole('heading', { name: /Room [A-Z2-9]{6}/ }),
    ).toBeVisible();
    const code = await page.evaluate(() =>
      localStorage.getItem('tractor-room-code'),
    );
    for (const [index, guest] of pages.slice(1).entries()) {
      await guest.goto('/');
      const lobby = guest.locator('#play-room');
      await lobby.getByLabel('Name').fill(`Guest ${index + 1}`);
      await lobby.getByLabel('Room code').fill(code!);
      await lobby.getByRole('button', { name: 'Join room' }).click();
      await expect(
        lobby.getByRole('button', { name: 'Ready up' }),
      ).toBeVisible();
    }
    const tokens = await Promise.all(
      pages.map((player) =>
        player.evaluate(() => localStorage.getItem('tractor-room-token')),
      ),
    );
    const view = async (seat: number) => {
      const response = await pages[seat]!.request.get(
        `/api/rooms/${code}/game?token=${tokens[seat]}`,
      );
      expect(response.ok()).toBe(true);
      return roomGameViewSchema.parse(await response.json());
    };
    const command = async (
      seat: number,
      action: string,
      cardIds?: string[],
    ) => {
      const current = await view(seat);
      const response = await pages[seat]!.request.post(
        `/api/rooms/${code}/game/commands`,
        {
          data: {
            action,
            token: tokens[seat],
            revision: current.revision,
            cardIds,
          },
        },
      );
      expect(response.ok(), await response.text()).toBe(true);
      return roomGameViewSchema.parse(await response.json());
    };
    for (const player of pages)
      await player
        .locator('#play-room')
        .getByRole('button', { name: 'Ready up' })
        .click();
    await expect(
      hostRoom.getByText('Trump declaration', { exact: true }),
    ).toBeVisible();
    // Exercise the fallback windows through the visible host control.
    for (let attempt = 0; attempt < 2; attempt++) {
      await expect(hostRoom.locator('.room-countdown')).toHaveText('0s left', {
        timeout: 15000,
      });
      await hostRoom.getByRole('button', { name: 'Pass', exact: true }).click();
      if ((await view(0)).phase === 'kitty') break;
      await expect(hostRoom.locator('.room-countdown')).not.toHaveText(
        '0s left',
      );
    }
    let game = await view(0);
    expect(game.phase).toBe('kitty');
    const dealer = pages[game.dealerSeat]!;
    await expect(dealer.locator('.room-card')).toHaveCount(
      (await view(game.dealerSeat)).hand.length,
    );
    for (let i = 0; i < game.kittyCount; i++)
      await dealer.locator('.room-card').nth(i).click();
    await dealer
      .getByRole('button', { name: 'Bury selected', exact: true })
      .click();
    await expect(
      dealer.getByRole('button', { name: 'Bury selected', exact: true }),
    ).toBeHidden();
    game = await view(0);
    let played = 0;
    while (game.phase === 'tricks') {
      if (game.trickComplete) {
        if (game.hand.length === 0) break;
        game = await command(0, 'next-trick');
        if (played === 4) {
          await pages[1]!.reload();
          await expect(
            pages[1]!
              .locator('#play-room')
              .getByRole('heading', { name: `Room ${code}` }),
          ).toBeVisible();
          await expect(pages[1]!.locator('.room-card')).toHaveCount(24);
        }
        continue;
      }
      const seat = game.nextSeat!;
      const own = await view(seat);
      const lead = own.plays[0]?.cards[0];
      const card =
        (lead
          ? own.hand.find(
              (card) =>
                category(card, own.trump!) === category(lead, own.trump!),
            )
          : undefined) ?? own.hand[0]!;
      if (played < 4) {
        const player = pages[seat]!;
        await expect(
          player.getByRole('button', { name: 'Play selected', exact: true }),
        ).toBeVisible();
        await player.locator(`[data-card-id="${card.id}"]`).click();
        await player
          .getByRole('button', { name: 'Play selected', exact: true })
          .click();
        await expect
          .poll(async () => (await view(seat)).revision)
          .toBe(own.revision + 1);
      } else await command(seat, 'play', [card.id]);
      played++;
      game = await view(0);
    }
    expect(played).toBe(100);
    await expect(
      hostRoom.getByRole('button', { name: 'Finish round', exact: true }),
    ).toBeVisible();
    await hostRoom
      .getByRole('button', { name: 'Finish round', exact: true })
      .click();
    for (const player of pages)
      await expect(player.getByLabel('Round settlement')).toBeVisible();
    const settled = await view(0);
    await page.reload();
    await expect(hostRoom.getByLabel('Round settlement')).toBeVisible();
    await hostRoom
      .getByRole('button', { name: 'Start next round', exact: true })
      .click();
    await expect(
      hostRoom.getByText('Trump declaration', { exact: true }),
    ).toBeVisible();
    const next = await view(0);
    expect(next.levels).toEqual(settled.settlement!.levels);
    expect(next.dealingStartedAt).toBeGreaterThan(settled.dealingStartedAt);
    // The new dealer must be able to bury after rotation as well.
    await expect(hostRoom.locator('.room-countdown')).toHaveText('0s left', {
      timeout: 15000,
    });
    await command(0, 'advance');
    await expect(hostRoom.locator('.room-countdown')).not.toHaveText('0s left');
    await expect(hostRoom.locator('.room-countdown')).toHaveText('0s left', {
      timeout: 15000,
    });
    game = await command(0, 'advance');
    expect(game.phase).toBe('kitty');
    await expect(
      pages[game.dealerSeat]!.getByRole('button', {
        name: 'Bury selected',
        exact: true,
      }),
    ).toBeVisible();
    for (const [seat, player] of pages.entries()) {
      if (seat !== game.dealerSeat)
        await expect(
          player.getByRole('button', { name: 'Bury selected', exact: true }),
        ).toBeHidden();
    }
  } finally {
    await Promise.all(contexts.map((context) => context.close()));
  }
});
