import { expect, test } from '@playwright/test';
import { botView } from '../../backend/src/bot-routes.js';
import { newBotMatch } from '../../backend/src/bot-match.js';
import { seededRandom } from '../../backend/src/training/self-play.js';

test('Sharp matches expose animated tricks without teaching samples', async ({
  page,
}, testInfo) => {
  const id = '11111111-1111-4111-8111-111111111111';
  const match = newBotMatch(4, 0, seededRandom(1));
  const view = botView(id, match, 1);
  view.playtest = {
    opponent: 'sharp',
    championId: 'test',
    feedbackCount: 0,
    review: [],
  };
  view.history = [
    {
      round: 1,
      number: 1,
      trump: { level: '2', suit: 'clubs' },
      points: 10,
      defenderPoints: 0,
      penalty: 0,
      winnerSeat: 1,
      plays: match.state.hands.map((hand, seat) => ({
        seat,
        cards: [hand[0]!],
        matchesLead: true,
      })),
    },
  ];
  await page.route('**/api/bot-matches', (route) =>
    route.fulfill({ json: view }),
  );
  await page.goto('/');
  await page
    .getByRole('button', { name: 'Start bot match', exact: true })
    .click();
  await page.getByRole('button', { name: 'Watch recorded tricks' }).click();
  await page
    .getByText('Round 1 · Trick 1 — Seat 2 won 10 points', { exact: true })
    .click();
  await page.getByText('Watch this trick', { exact: true }).click();
  const clip = page.getByRole('region', { name: 'Trick replay' });
  await clip.getByRole('button', { name: 'Replay trick', exact: true }).click();
  await expect(clip.getByRole('status')).toHaveText(
    'Winner: seat 2 · 10 points',
    { timeout: 7000 },
  );
  await expect(clip.locator('.clip-cards')).toHaveCount(4);
  await expect(clip.getByText('Bot’s hand before this decision')).toHaveCount(
    0,
  );
  await clip.screenshot({
    path: testInfo.outputPath('sharp-trick-replay.png'),
  });
});

test('review animates to the decision, withholds outcome, and fits a scrolling checklist', async ({
  page,
}, testInfo) => {
  test.setTimeout(60000);
  const id = '11111111-1111-4111-8111-111111111111';
  const match = newBotMatch(4, 0, seededRandom(1));
  match.state = { ...match.state, phase: 'finished' };
  match.settlement = {
    defenderScore: 0,
    kittyBasePoints: 0,
    kittyMultiplier: 1,
    kittyPoints: 0,
    outcome: { advancingRole: 'attackers', levels: 1, swapRoles: false },
    levels: { A: 'A', B: '2' },
    attackingTeam: 'A',
    rolesSwapped: false,
    jackReset: false,
    winner: 'A',
  };
  const view = botView(id, match, 1);
  view.playtest = {
    opponent: 'sharp',
    championId: 'test-policy',
    feedbackCount: 0,
    review: Array.from({ length: 20 }, (_, i) => ({
      id: `22222222-2222-4222-8222-${String(i).padStart(12, '0')}`,
      seat: 3,
      kind: 'follow' as const,
      chosen: 0,
      preferredIndex: null,
      round: 1,
      trick: 1,
      options: [
        { cards: ['A clubs'], cardIds: ['ace'] },
        { cards: ['J clubs'], cardIds: ['jack'] },
      ],
      clip: {
        seatCorrected: true,
        seat: 3,
        decisionIndex: 3,
        hand: ['J clubs', 'A clubs'],
        trump: '2 hearts',
        points: 10,
        winnerSeat: 3,
        plays: [
          { seat: 0, cards: ['10 clubs'] },
          { seat: 1, cards: ['Q clubs'] },
          { seat: 2, cards: ['K clubs'] },
          { seat: 3, cards: ['A clubs'] },
        ],
      },
    })),
  };
  await page.addInitScript(
    (id) => localStorage.setItem('tractor-bot-match', id),
    id,
  );
  await page.route(`**/api/bot-matches/${id}`, (route) =>
    route.fulfill({
      json: {
        ...view,
        revision: 0,
        playtest: { ...view.playtest, review: [] },
      },
    }),
  );
  await page.route(`**/api/bot-matches/${id}/review`, (route) => {
    expect(route.request().postDataJSON()).toEqual({ revision: 0 });
    return route.fulfill({ json: view });
  });
  let submissions = 0;
  await page.route(`**/api/bot-matches/${id}/feedback`, async (route) => {
    submissions++;
    expect(route.request().postDataJSON()).toEqual({
      revision: 1,
      sampleId: view.playtest!.review[0]!.id,
      preferredIndex: 1,
    });
    if (submissions === 1)
      return route.fulfill({ status: 500, json: { message: 'Please retry' } });
    view.playtest!.review[0]!.preferredIndex = 1;
    view.revision = 2;
    await route.fulfill({ json: view });
  });
  await page.goto('/');
  await page
    .getByRole('button', { name: 'Resume bot match', exact: true })
    .click();
  const flashcards = page.getByRole('region', { name: 'Decision flashcards' });
  await page.getByRole('button', { name: 'Start decision flashcards' }).click();
  await expect(
    flashcards.getByText('Card 1 of 20', { exact: true }),
  ).toBeVisible();
  await expect(flashcards.getByRole('radio')).toHaveCount(2);
  await expect(
    flashcards.getByText('J clubs · A clubs', { exact: true }),
  ).toBeVisible();
  await expect(flashcards.locator('.clip-cards')).toHaveCount(3);
  await expect(
    flashcards.getByRole('button', { name: 'Show outcome' }),
  ).toHaveCount(0);
  await expect(
    flashcards.getByRole('button', { name: 'Submit answer' }),
  ).toBeDisabled();
  await flashcards.getByRole('radio', { name: 'J clubs', exact: true }).check();
  await flashcards.getByRole('button', { name: 'Submit answer' }).click();
  await expect(flashcards.getByRole('alert')).toContainText('wasn’t saved');
  await expect(
    flashcards.getByText('Card 1 of 20', { exact: true }),
  ).toBeVisible();
  await flashcards.getByRole('button', { name: 'Submit answer' }).click();
  await expect(
    flashcards.getByText('Correction saved.', { exact: false }),
  ).toBeVisible();
  await flashcards.getByRole('button', { name: 'Next flashcard' }).click();
  await expect(
    flashcards.getByRole('heading', { name: 'What should Bot 4 play?' }),
  ).toBeFocused();
  await expect(
    flashcards.getByText('Card 2 of 20', { exact: true }),
  ).toBeVisible();
  await expect(
    flashcards.getByRole('button', { name: 'Submit answer' }),
  ).toBeDisabled();
  await flashcards.getByRole('button', { name: 'Skip — not sure' }).click();
  await expect(
    flashcards.getByText('Card 3 of 20', { exact: true }),
  ).toBeVisible();
  await flashcards.getByRole('radio', { name: 'A clubs', exact: true }).check();
  await flashcards.getByRole('button', { name: 'Submit answer' }).click();
  await expect(
    flashcards.getByText('You chose the same play', { exact: false }),
  ).toBeVisible();
  expect(submissions).toBe(2);
  await flashcards.screenshot({
    path: testInfo.outputPath('decision-flashcard.png'),
  });
  await page.getByText('Teach from this match', { exact: false }).click();
  const rows = page.locator('.playtest-feedback-row');
  await rows.first().getByText('Watch this trick', { exact: true }).click();
  const clip = rows.first().getByRole('region', { name: 'Decision replay' });
  await expect(
    clip.getByText('This decision was previously labeled', { exact: false }),
  ).toBeVisible();
  await clip.getByRole('button', { name: 'Replay to decision' }).click();
  await expect(clip.getByRole('status')).toContainText(
    'Paused before the decision',
    { timeout: 6000 },
  );
  await expect(clip.locator('.clip-cards')).toHaveCount(3);
  await expect(clip.getByText('Winner:', { exact: false })).toHaveCount(0);
  await clip.getByRole('button', { name: 'Show outcome' }).click();
  await expect(clip.getByRole('status')).toHaveText(
    'Winner: seat 4 · 10 points',
  );
  await clip.getByText('Bot’s hand before this decision').click();
  await expect(
    clip.getByText('J clubs · A clubs', { exact: true }),
  ).toBeVisible();
  await clip.screenshot({ path: testInfo.outputPath('decision-clip.png') });
  const viewportWidth = page.viewportSize()!.width;
  const bounds = await clip.boundingBox();
  expect(bounds!.x + bounds!.width).toBeLessThanOrEqual(viewportWidth);
  await rows.last().getByText('Watch this trick', { exact: true }).click();
  await expect(
    rows.last().getByRole('button', { name: 'Replay to decision' }),
  ).toBeVisible();
});
