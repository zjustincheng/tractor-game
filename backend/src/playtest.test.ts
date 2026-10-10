import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { buildApp } from './app.js';
import { MatchStore } from './match-store.js';
import { heuristicPolicy } from './bot-policy.js';
import {
  newBotMatch,
  policyForSeat,
  commandBotMatch,
  botLeadContext,
} from './bot-match.js';
import { botView } from './bot-routes.js';
import { startTrick } from '@tractor/rules';
import type { Card } from '@tractor/rules';
import { newPolicy } from './training/learned-policy.js';
import { learnedBotPolicy } from './training/bot-policy.js';
import { seededRandom } from './training/self-play.js';

function champion() {
  const models = {
    lead: newPolicy(seededRandom(1)),
    follow: newPolicy(seededRandom(2)),
  };
  return { ...learnedBotPolicy(models.lead, models.follow), models };
}
const settlement = {
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
} as const;

describe('human playtest', () => {
  it('offers fair suggestions from the human seat without exposing other hands', () => {
    const match = newBotMatch(4, 0, seededRandom(2));
    match.playtest = {
      opponent: 'champion',
      models: champion().models,
      championId: 'frozen',
      feedbackCount: 0,
      observed: { lead: 0, follow: 0, declaration: 0, burial: 0 },
      samples: [],
    };
    const card = (id: string, suit: 'clubs' | 'spades'): Card => ({
      id,
      kind: 'suited',
      rank: '3',
      suit,
    });
    const trump = { level: '2', suit: 'spades' } as const;
    const hands = [
      [card('s0', 'spades'), card('c0', 'clubs')],
      [card('c1', 'clubs'), card('c1b', 'clubs')],
      [card('s2', 'spades'), card('s2b', 'spades')],
      [card('c3', 'clubs'), card('c3b', 'clubs')],
    ];
    match.state = {
      ...match.state,
      phase: 'tricks',
      trump,
      hands,
      trick: startTrick({
        playerCount: 4,
        hands,
        trump,
        attackingTeam: 'A',
        leaderSeat: 0,
      }),
    };

    const view = botView('11111111-1111-4111-8111-111111111111', match, 0);
    expect(view.suggestion).toHaveLength(1);
    expect(hands[0]).toContainEqual(
      expect.objectContaining({ id: view.suggestion[0] }),
    );
  });

  it('keeps the partner fixed and preserves assignment between rounds', () => {
    const loaded = champion();
    const match = newBotMatch(4, 0, seededRandom(10));
    match.playtest = {
      opponent: 'champion',
      models: loaded.models,
      championId: 'frozen',
      feedbackCount: 0,
      observed: { lead: 0, follow: 0, declaration: 0, burial: 0 },
      samples: [],
    };
    expect(policyForSeat(match, 2, loaded)?.declare).toBe(
      heuristicPolicy('standard').declare,
    );
    expect(policyForSeat(match, 1, loaded)?.declare).not.toBe(
      heuristicPolicy('standard').declare,
    );
    const copied = {
      ...match,
      playtest: {
        ...match.playtest!,
        samples: [],
        observed: { lead: 0, follow: 0, declaration: 0, burial: 0 },
        currentDecision: { round: 2, trick: 3 },
      },
    };
    for (const seat of [1, 3]) {
      policyForSeat(copied, seat, loaded)!.lead(
        copied.state.hands[seat]!,
        {
          level: '2',
          suit: 'clubs',
        },
        botLeadContext(copied, seat),
        [],
      );
    }
    expect(copied.playtest.samples).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ seat: 1, round: 2, trick: 3 }),
        expect.objectContaining({ seat: 3, round: 2, trick: 3 }),
      ]),
    );
    expect(match.playtest!.samples).toHaveLength(0);
    match.settlement = { ...settlement, winner: null };
    const next = commandBotMatch(
      match,
      { action: 'next-round' },
      1,
      seededRandom(11),
      loaded,
    );
    expect(next.playtest).toEqual(match.playtest);
    next.playtest!.previousId = '11111111-1111-4111-8111-111111111111';
    const nextView = botView(
      '22222222-2222-4222-8222-222222222222',
      next,
      0,
      loaded,
    );
    expect(nextView.playtest?.previousPlaytestId).toBe(
      next.playtest!.previousId,
    );
    expect(nextView.playtest?.opponent).toBeNull();
    expect(nextView.playtest?.review).toEqual([]);
  });
  it('rejects feedback that repeats the bot action', async () => {
    const directory = mkdtempSync(join(tmpdir(), 'tractor-feedback-'));
    let app = buildApp({
      saveDirectory: directory,
      botPolicy: champion(),
      now: () => 0,
      pickIndex: () => 1,
    });
    try {
      const created = await app.inject({
        method: 'POST',
        url: '/api/bot-matches',
        payload: { playerCount: 4, playtest: true },
      });
      const id = created.json().id as string;
      await app.close();

      const store = new MatchStore(directory);
      const saved = store.get(id)!;
      saved.match.state = { ...saved.match.state, phase: 'finished' };
      saved.match.settlement = settlement;
      saved.match.playtest!.samples = [
        {
          id: '22222222-2222-4222-8222-222222222222',
          seat: 1,
          kind: 'follow',
          experience: {
            chosen: 0,
            options: [
              { cardIds: ['card-a'], features: [], prior: 0 },
              { cardIds: ['card-b'], features: [], prior: 0 },
            ],
          },
        },
      ];
      store.set(id, saved);
      app = buildApp({
        saveDirectory: directory,
        botPolicy: champion(),
        now: () => 0,
      });

      const response = await app.inject({
        method: 'POST',
        url: `/api/bot-matches/${id}/feedback`,
        payload: {
          revision: saved.revision,
          sampleId: '22222222-2222-4222-8222-222222222222',
          preferredIndex: 0,
        },
      });
      expect(response.statusCode).toBe(400);
      expect(response.json().message).toContain('different action');
      expect(
        (
          await app.inject({
            method: 'GET',
            url: `/api/bot-matches/${id}`,
          })
        ).json().playtest.feedbackCount,
      ).toBe(0);
    } finally {
      await app.close();
      rmSync(directory, { recursive: true, force: true });
    }
  });
  it('requires a frozen champion and four seats', async () => {
    const app = buildApp();
    try {
      expect(
        (
          await app.inject({
            method: 'POST',
            url: '/api/bot-matches',
            payload: { playerCount: 4, playtest: true },
          })
        ).statusCode,
      ).toBe(400);
    } finally {
      await app.close();
    }
    const loaded = buildApp({ botPolicy: champion() });
    try {
      expect(
        (
          await loaded.inject({
            method: 'POST',
            url: '/api/bot-matches',
            payload: { playerCount: 6, playtest: true },
          })
        ).statusCode,
      ).toBe(400);
    } finally {
      await loaded.close();
    }
  });
  it('hides assignment, freezes models across restart, reveals at completion and alternates once on concurrent continuation', async () => {
    const directory = mkdtempSync(join(tmpdir(), 'tractor-playtest-'));
    let app = buildApp({
      saveDirectory: directory,
      botPolicy: champion(),
      now: () => 0,
      pickIndex: () => 0,
    });
    try {
      const created = await app.inject({
        method: 'POST',
        url: '/api/bot-matches',
        payload: { playerCount: 4, playtest: true },
      });
      expect(created.statusCode).toBe(200);
      const view = created.json();
      expect(view.playtest).toMatchObject({
        opponent: null,
        championId: null,
        feedbackCount: 0,
        review: [],
      });
      expect(view.suggestion).toEqual([]);
      expect(created.body).not.toContain('priorScale');
      // Every export of bot decisions stays sealed, not just the replay: a
      // decision trace identifies the opponent the playtest is hiding.
      for (const path of ['replay', 'behavior.csv', 'behavior-summary.csv'])
        expect(
          (
            await app.inject({
              method: 'GET',
              url: `/api/bot-matches/${view.id}/${path}`,
            })
          ).statusCode,
        ).toBe(403);
      const playerActions = await app.inject({
        method: 'GET',
        url: `/api/bot-matches/${view.id}/player-actions.csv`,
      });
      expect(playerActions.statusCode).toBe(200);
      expect(playerActions.body).toBe(
        'revision,timestamp,action,round,trick,card_ids',
      );
      expect(playerActions.body).not.toContain('bot');
      expect(
        (
          await app.inject({
            method: 'POST',
            url: '/api/bot-matches',
            payload: {
              playerCount: 4,
              playtest: true,
              previousPlaytestId: view.id,
            },
          })
        ).statusCode,
      ).toBe(400);
      await app.close();
      const store = new MatchStore(directory);
      const saved = store.get(view.id)!;
      const frozen = structuredClone(saved.match.playtest!);
      expect(frozen.opponent).toBe('sharp');
      app = buildApp({ saveDirectory: directory, now: () => 0 });
      expect(
        (
          await app.inject({
            method: 'GET',
            url: `/api/bot-matches/${view.id}`,
          })
        ).json().playtest.opponent,
      ).toBeNull();
      await app.close();
      saved.match.settlement = settlement;
      saved.match.state = { ...saved.match.state, phase: 'finished' };
      store.set(view.id, saved);
      app = buildApp({ saveDirectory: directory, now: () => 0 });
      const completed = (
        await app.inject({ method: 'GET', url: `/api/bot-matches/${view.id}` })
      ).json();
      expect(completed.playtest.opponent).toBe('sharp');
      const exported = await app.inject({
        method: 'GET',
        url: `/api/bot-matches/${view.id}/replay`,
      });
      expect(exported.json().playtest.winner).toBe('A');
      for (const path of ['behavior.csv', 'behavior-summary.csv'])
        expect(
          (
            await app.inject({
              method: 'GET',
              url: `/api/bot-matches/${view.id}/${path}`,
            })
          ).statusCode,
        ).toBe(200);
      expect(exported.body).not.toContain('priorScale');
      const responses = await Promise.all(
        [0, 1].map(() =>
          app.inject({
            method: 'POST',
            url: '/api/bot-matches',
            payload: {
              playerCount: 4,
              playtest: true,
              previousPlaytestId: view.id,
            },
          }),
        ),
      );
      expect(responses[0]!.statusCode).toBe(200);
      expect(responses[0]!.json().id).toBe(responses[1]!.json().id);
      expect(responses[0]!.json().playtest.opponent).toBeNull();
      const resumed = new MatchStore(directory).get(
        responses[0]!.json().id,
      )!.match;
      expect(resumed.playtest?.opponent).toBe('champion');
      expect(resumed.playtest?.models).toEqual(frozen.models);
      expect(resumed.playtest?.championId).toBe(frozen.championId);
    } finally {
      await app.close();
      rmSync(directory, { recursive: true, force: true });
    }
  });
});
