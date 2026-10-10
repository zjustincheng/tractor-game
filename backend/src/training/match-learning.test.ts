import { describe, expect, it, vi } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { buildApp } from '../app.js';
import { MatchStore } from '../match-store.js';
import { chooseBotBurial, chooseBotPlay } from '@tractor/rules';
import { commandBotMatch, newBotMatch } from '../bot-match.js';
import { botView } from '../bot-routes.js';
import type { BotCommand } from '../bot-match.js';
import { seededRandom } from './self-play.js';
import { learnedBotPolicy } from './bot-policy.js';
import * as counterfactual from './counterfactual.js';
import type { PolicyExperience } from './learned-policy.js';
import { learnRecordedRounds, reconstructMatch } from './match-learning.js';
import {
  newPolicyCheckpoint,
  parsePolicyCheckpoint,
} from './policy-training.js';

function savedGame(roundCount = 1) {
  const pick = seededRandom(51);
  let match = newBotMatch(4, 0, pick);
  let now = 0;
  for (
    let step = 0;
    step < roundCount * 500 && match.rounds.length < roundCount;
    step++
  ) {
    const s = match.state;
    let command: BotCommand;
    if (s.phase === 'finished') command = { action: 'next-round' };
    else if (s.phase === 'declaration' || s.trick?.status === 'complete')
      command = { action: 'advance' };
    else if (s.phase === 'kitty')
      command = {
        action: 'bury',
        cardIds: chooseBotBurial(
          [...s.hands[0]!, ...s.kitty],
          s.kitty.length,
          s.trump!,
        ),
      };
    else
      command = {
        action: 'play',
        cardIds: chooseBotPlay(
          s.hands[0]!,
          s.trick!.plays[0]?.components ?? null,
          s.trump!,
        ),
      };
    now = Math.max(now + 1, s.declarationDeadline);
    match = commandBotMatch(match, command, now, pick);
  }
  expect(match.rounds).toHaveLength(roundCount);
  return match;
}

describe('learning from saved matches', () => {
  it('prepares and teaches replay-backed Sharp flashcards without training on preparation', async () => {
    const directory = mkdtempSync(join(tmpdir(), 'tractor-flashcards-'));
    const checkpoint = newPolicyCheckpoint({
      seed: 44,
      playerCounts: [4],
      trainSeeds: 1,
      validationSeeds: 2,
      maxRounds: 1,
    });
    const match = savedGame(2);
    match.settlement = { ...match.settlement!, winner: 'A' };
    match.playtest = {
      opponent: 'sharp',
      championId: 'fixture',
      models: {
        lead: checkpoint.leadLearner,
        follow: checkpoint.followLearner,
      },
      feedbackCount: 0,
      observed: { lead: 0, follow: 0, declaration: 0, burial: 0 },
      samples: [],
    };
    const models = structuredClone(match.playtest.models);
    const id = '11111111-1111-4111-8111-111111111111';
    const sealedId = '22222222-2222-4222-8222-222222222222';
    const store = new MatchStore(directory);
    store.set(id, { match, revision: 0, touched: Date.now() });
    const sealed = structuredClone(match);
    sealed.settlement = { ...sealed.settlement!, winner: null };
    store.set(sealedId, { match: sealed, revision: 0, touched: Date.now() });
    const app = buildApp({ saveDirectory: directory });
    try {
      expect(
        (
          await app.inject({
            method: 'POST',
            url: `/api/bot-matches/${sealedId}/review`,
            payload: { revision: 0 },
          })
        ).statusCode,
      ).toBe(403);
      const failedWrite = vi
        .spyOn(MatchStore.prototype, 'set')
        .mockImplementationOnce(() => {
          throw new Error('simulated disk failure');
        });
      const failed = await app.inject({
        method: 'POST',
        url: `/api/bot-matches/${id}/review`,
        payload: { revision: 0 },
      });
      failedWrite.mockRestore();
      expect(failed.statusCode).toBe(500);
      const unchanged = await app.inject({
        method: 'GET',
        url: `/api/bot-matches/${id}`,
      });
      expect(unchanged.json().revision).toBe(0);
      expect(unchanged.json().playtest.review).toEqual([]);
      const concurrent = await Promise.all(
        [0, 1].map(() =>
          app.inject({
            method: 'POST',
            url: `/api/bot-matches/${id}/review`,
            payload: { revision: 0 },
          }),
        ),
      );
      expect(concurrent.map((r) => r.statusCode).sort()).toEqual([200, 409]);
      const prepared = concurrent.find((r) => r.statusCode === 200)!;
      expect(prepared.statusCode).toBe(200);
      const view = prepared.json();
      expect(view.revision).toBe(1);
      expect(view.playtest.review.length).toBeGreaterThan(0);
      expect(view.playtest.review.length).toBeLessThanOrEqual(96);
      expect(
        view.playtest.review.every(
          (s: { seat: number; clip: unknown }) =>
            s.seat % 2 === 1 && s.clip !== null,
        ),
      ).toBe(true);
      expect(new MatchStore(directory).get(id)!.match.playtest!.models).toEqual(
        models,
      );
      const repeated = await app.inject({
        method: 'POST',
        url: `/api/bot-matches/${id}/review`,
        payload: { revision: 1 },
      });
      expect(repeated.json()).toEqual(view);
      expect(
        (
          await app.inject({
            method: 'POST',
            url: `/api/bot-matches/${id}/review`,
            payload: { revision: 0 },
          })
        ).statusCode,
      ).toBe(409);
      const sample = view.playtest.review[0];
      const preferredIndex = sample.chosen === 0 ? 1 : 0;
      const failedFeedbackWrite = vi
        .spyOn(MatchStore.prototype, 'set')
        .mockImplementationOnce(() => {
          throw new Error('simulated disk failure');
        });
      const failedFeedback = await app.inject({
        method: 'POST',
        url: `/api/bot-matches/${id}/feedback`,
        payload: { revision: 1, sampleId: sample.id, preferredIndex },
      });
      failedFeedbackWrite.mockRestore();
      expect(failedFeedback.statusCode).toBe(500);
      const afterFailure = (
        await app.inject({ method: 'GET', url: `/api/bot-matches/${id}` })
      ).json();
      expect(afterFailure.revision).toBe(1);
      expect(afterFailure.playtest.review[0].preferredIndex).toBeNull();
      expect(afterFailure.playtest.feedbackCount).toBe(0);
      expect(new MatchStore(directory).get(id)!.match.playtest!.models).toEqual(
        models,
      );
      const taught = await app.inject({
        method: 'POST',
        url: `/api/bot-matches/${id}/feedback`,
        payload: { revision: 1, sampleId: sample.id, preferredIndex },
      });
      expect(taught.statusCode).toBe(200);
      expect(taught.json().revision).toBe(2);
      expect(taught.json().playtest.feedbackCount).toBe(1);
      expect(
        new MatchStore(directory).get(id)!.match.playtest!.samples[0]!
          .preferredIndex,
      ).toBe(preferredIndex);
      expect(
        (
          await app.inject({
            method: 'POST',
            url: `/api/bot-matches/${id}/feedback`,
            payload: { revision: 1, sampleId: sample.id, preferredIndex },
          })
        ).statusCode,
      ).toBe(409);
    } finally {
      await app.close();
      rmSync(directory, { recursive: true, force: true });
    }
  });
  it('uses the live learned adapter’s endgame action distribution', () => {
    const checkpoint = newPolicyCheckpoint({
      seed: 44,
      playerCounts: [4],
      trainSeeds: 1,
      validationSeeds: 2,
      maxRounds: 1,
    });
    const round = reconstructMatch(savedGame()).rounds[0]!;
    const position = round.positions.find(
      (p) =>
        p.trick.plays.length === 0 &&
        p.trick.hands[p.trick.nextSeat!]!.length <= 4,
    )!;
    const { trick } = position;
    const seat = trick.nextSeat!;
    let expected: PolicyExperience | undefined;
    const policy = learnedBotPolicy(
      checkpoint.leadLearner,
      checkpoint.followLearner,
      {
        lead: (e) => {
          expected = e;
        },
      },
    );
    policy.lead(
      trick.hands[seat]!,
      trick.trump,
      {
        seat,
        playerCount: trick.playerCount,
        cardsRemaining: trick.hands[seat]!.length,
        role:
          (seat % 2 === 0 ? 'A' : 'B') === trick.attackingTeam
            ? 'attackers'
            : 'defenders',
        defenderScore: position.captured,
        swapThreshold: trick.playerCount * 20,
        seenCards: position.seenCards,
        knownVoids: position.knownVoids,
      },
      [],
    );
    const spy = vi
      .spyOn(counterfactual, 'compareAlternatives')
      .mockImplementation((_position, experience) => {
        expect(experience).toEqual(expected);
        return {
          positions: 1,
          rollouts: 0,
          informativePairs: 0,
          betterThanBaseline: 0,
        };
      });
    try {
      learnRecordedRounds(checkpoint, [{ ...round, positions: [position] }]);
      expect(spy).toHaveBeenCalledOnce();
    } finally {
      spy.mockRestore();
    }
  });
  it('reconstructs all actual legal positions and keeps the source unchanged', () => {
    const match = savedGame();
    const before = JSON.stringify(match);
    const recovered = reconstructMatch(match);
    expect(recovered.skipped).toEqual([]);
    expect(recovered.rounds).toHaveLength(1);
    const positions = recovered.rounds[0]!.positions;
    expect(match.replay!.deals[0]!.exposedCards?.length).toBeGreaterThan(0);
    expect(positions[0]!.exposedCards).toEqual(
      match.replay!.deals[0]!.exposedCards!.map((e) => ({
        ...e,
        mayBeBuried: e.seat === positions[0]!.dealerSeat,
      })),
    );
    expect(positions).toHaveLength(match.history.length * 4);
    expect(positions[0]!.trick.hands.every((h) => h.length === 25)).toBe(true);
    expect(positions[0]!.kitty).toHaveLength(8);
    for (const [seat, hand] of positions[0]!.trick.hands.entries()) {
      const ids = new Set(hand.map((c) => c.id));
      const deal = match.replay!.deals[0]!;
      expect(hand).toEqual(
        [
          ...deal.hands[seat]!,
          ...(seat === positions[0]!.trick.leaderSeat ? deal.kitty : []),
        ].filter((c) => ids.has(c.id)),
      );
    }
    expect(positions[0]!.seenCards).toEqual([]);
    expect(positions[4]!.seenCards.length).toBeGreaterThan(0);
    expect(JSON.stringify(match)).toBe(before);
  });

  it('rejects incomplete and inconsistent rounds rather than manufacturing examples', () => {
    const match = savedGame();
    match.history.shift();
    expect(reconstructMatch(match).rounds).toEqual([]);
    const corrupt = savedGame();
    corrupt.history[0]!.winnerSeat = (corrupt.history[0]!.winnerSeat + 1) % 4;
    expect(reconstructMatch(corrupt).skipped[0]!.reason).toMatch(
      /outcome differs/,
    );
  });

  it('updates a candidate using comparisons, preserves the champion, and deduplicates after reload', () => {
    const checkpoint = newPolicyCheckpoint({
      seed: 44,
      playerCounts: [4],
      trainSeeds: 1,
      validationSeeds: 2,
      maxRounds: 1,
    });
    checkpoint.champion = checkpoint.leadChampion = structuredClone(
      checkpoint.leadLearner,
    );
    checkpoint.followChampion = structuredClone(checkpoint.followLearner);
    const before = JSON.stringify(checkpoint);
    const rounds = reconstructMatch(savedGame()).rounds;
    const result = learnRecordedRounds(checkpoint, [...rounds, ...rounds]);
    expect(result.report.rounds).toBe(1);
    expect(result.report.alreadyLearned).toBe(1);
    expect(result.report.comparisons).toBeGreaterThan(0);
    expect(result.checkpoint.leadLearner).not.toEqual(checkpoint.leadLearner);
    expect(result.checkpoint.leadChampion).toEqual(checkpoint.leadChampion);
    expect(result.checkpoint.followChampion).toEqual(checkpoint.followChampion);
    expect(JSON.stringify(checkpoint)).toBe(before);
    const reloaded = parsePolicyCheckpoint(
      JSON.parse(JSON.stringify(result.checkpoint)),
    );
    const repeated = learnRecordedRounds(reloaded, rounds);
    expect(repeated.report.rounds).toBe(0);
    expect(repeated.checkpoint).toEqual(reloaded);
  }, 20000);

  it('retains more than 100 completed tricks for future learning', () => {
    const match = savedGame(7);
    expect(match.history.length).toBeGreaterThan(100);
    expect(match.history[0]!.round).toBe(1);
    expect(reconstructMatch(match).rounds.length).toBe(7);
    expect(
      botView('00000000-0000-4000-8000-000000000001', match, 1).history,
    ).toHaveLength(100);
  });
});
