import { expect, test } from '@playwright/test';
import { botView } from '../../backend/src/bot-routes.js';
import { newBotMatch } from '../../backend/src/bot-match.js';
import { seededRandom } from '../../backend/src/training/self-play.js';

test('recovers previous flashcards and preserves the newer match across reload', async ({
  page,
}, testInfo) => {
  const oldId = '11111111-1111-4111-8111-111111111111';
  const newId = '22222222-2222-4222-8222-222222222222';
  const finished = newBotMatch(4, 0, seededRandom(1));
  finished.state = { ...finished.state, phase: 'finished' };
  finished.settlement = {
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
  const previous = botView(oldId, finished, 8);
  previous.playtest = {
    opponent: 'sharp',
    championId: 'test',
    feedbackCount: 1,
    review: [],
  };
  const current = botView(newId, newBotMatch(4, 0, seededRandom(2)), 0);
  current.playtest = {
    opponent: null,
    championId: null,
    feedbackCount: 1,
    review: [],
    previousPlaytestId: oldId,
  };
  await page.addInitScript(
    (id) => localStorage.setItem('tractor-bot-match', id),
    newId,
  );
  const methods: string[] = [];
  await page.route(`**/api/bot-matches/${newId}`, (route) => {
    methods.push(route.request().method());
    return route.fulfill({ json: current });
  });
  await page.route(`**/api/bot-matches/${oldId}`, (route) => {
    methods.push(route.request().method());
    return route.fulfill({ json: previous });
  });
  await page.goto('/');
  await page
    .getByRole('button', { name: 'Resume bot match', exact: true })
    .click();
  await page
    .getByRole('button', { name: 'Back to previous flashcards' })
    .click();
  await expect(
    page.getByRole('button', { name: 'Start decision flashcards' }),
  ).toBeVisible();
  await page
    .getByText('Saved matches & flashcards (2)', { exact: true })
    .click();
  await page
    .getByRole('button', { name: /Saved match · Round 1 · 22222222/ })
    .click();
  await expect(
    page.getByRole('button', { name: 'Back to previous flashcards' }),
  ).toBeVisible();
  await page.reload();
  await page
    .getByRole('button', { name: 'Resume bot match', exact: true })
    .click();
  await page
    .getByText('Saved matches & flashcards (2)', { exact: true })
    .click();
  await page
    .getByRole('button', {
      name: /Completed match · Flashcards · Round 1 · 11111111/,
    })
    .click();
  await expect(
    page.getByRole('button', { name: 'Start decision flashcards' }),
  ).toBeVisible();
  expect(methods.every((method) => method === 'GET')).toBe(true);
  await page.screenshot({ path: testInfo.outputPath('saved-matches.png') });
});
