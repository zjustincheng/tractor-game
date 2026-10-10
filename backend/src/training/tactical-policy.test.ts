import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { loadBotPolicy } from './load-policy.js';
import { describe, expect, it } from 'vitest';
import {
  decomposeLead,
  playCards,
  startTrick,
  validateFollow,
} from '@tractor/rules';
import type { Card } from '@tractor/rules';
import { botPlayContext } from '../bot-play-context.js';
import {
  INPUTS,
  leadOptions,
  newPolicy,
  parsePolicy,
  playOptions,
  policyProbabilities,
  choosePolicyPlay,
} from './learned-policy.js';
import type { PolicyExperience } from './learned-policy.js';
import { seededRandom } from './self-play.js';
import {
  newPolicyCheckpoint,
  parsePolicyCheckpoint,
} from './policy-training.js';
const trump = { level: '2', suit: 'spades' } as const;
const card = (
  rank: '5' | '10' | 'J' | 'K' | 'A',
  suit: 'clubs' | 'hearts' | 'spades' = 'clubs',
  copy = 0,
): Card => ({ id: `${copy}:${suit}:${rank}`, kind: 'suited', suit, rank });

describe('tactical policy context', () => {
  it('zero extends legacy weights and retires obsolete validation and replay caches', () => {
    const model = newPolicy(seededRandom(2));
    model.input = model.input.map((row) => row.slice(0, 22));
    const before = { cardIds: ['a'], prior: 0, features: Array(22).fill(0.5) };
    const other = { ...before, features: Array(22).fill(-0.5) };
    const migrated = parsePolicy(model);
    expect(migrated.input[0]).toHaveLength(INPUTS);
    expect(policyProbabilities(migrated, [before, other])).toEqual(
      policyProbabilities(model, [before, other]),
    );
    const checkpoint = newPolicyCheckpoint({
      seed: 1,
      playerCounts: [4],
      trainSeeds: 1,
      validationSeeds: 2,
      maxRounds: 1,
    });
    checkpoint.policyVersion = 'contextual-leads-v10-adaptive-prior';
    checkpoint.learnedMatchRounds = ['a'.repeat(64)];
    checkpoint.leadChampion = model;
    checkpoint.champion = model;
    const parsed = parsePolicyCheckpoint(checkpoint);
    expect(parsed.leadChampion).toBeNull();
    expect(parsed.learnedMatchRounds).toEqual([]);
    expect(parsed.championMarginSamples).toEqual([]);
  });
  it('serves a legacy champion without silently migrating its inference', () => {
    const checkpoint = newPolicyCheckpoint({
      seed: 1,
      playerCounts: [4],
      trainSeeds: 1,
      validationSeeds: 2,
      maxRounds: 1,
    });
    const model = {
      ...checkpoint.leadLearner,
      input: checkpoint.leadLearner.input.map((row) => row.slice(0, 22)),
    };
    checkpoint.policyVersion = 'contextual-leads-v10-adaptive-prior';
    checkpoint.champion =
      checkpoint.leadChampion =
      checkpoint.followChampion =
        model;
    const file = join(
      mkdtempSync(join(tmpdir(), 'tractor-legacy-policy-')),
      'checkpoint.json',
    );
    writeFileSync(file, JSON.stringify(checkpoint));
    const policy = loadBotPolicy(file);
    expect(policy.models!.lead.input[0]).toHaveLength(22);
    expect(policy.models!.follow.input[0]).toHaveLength(22);
    const opening = decomposeLead([card('10'), card('10', 'clubs', 1)], trump)!;
    const hand = [
      card('J'),
      card('J', 'clubs', 1),
      card('A'),
      card('A', 'clubs', 1),
    ];
    const context = {
      seat: 1,
      winnerSeat: 0,
      winning: opening,
      lastToPlay: false,
    };
    const options = playOptions(hand, opening, trump, context, false);
    expect(options).toHaveLength(1);
    expect(policy.follow(hand, opening, trump, context)).toEqual(
      options[0]!.cardIds,
    );
  });

  it('offers legal pair alternatives and identifies overtakes using suit and structure', () => {
    const lead = decomposeLead([card('10'), card('10', 'clubs', 1)], trump)!;
    const hand = [
      card('J'),
      card('J', 'clubs', 1),
      card('A'),
      card('A', 'clubs', 1),
    ];
    const options = playOptions(hand, lead, trump, {
      seat: 1,
      winnerSeat: 0,
      winning: lead,
      lastToPlay: false,
      trickPoints: 20,
      opponentsRemaining: 1,
    });
    expect(options).toHaveLength(2);
    expect(options.filter((option) => option.prior > 0)).toHaveLength(1);
    for (const option of options) {
      expect(
        validateFollow(
          hand,
          hand.filter((c) => option.cardIds.includes(c.id)),
          lead,
          trump,
        ).legal,
      ).toBe(true);
      expect(option.features[23]).toBe(1);
    }
    expect(
      options.find((option) => option.cardIds.includes('0:clubs:A'))!
        .features[17],
    ).toBeGreaterThan(0);
    const single = decomposeLead([card('10')], trump)!;
    const offSuit = playOptions(
      [card('A', 'hearts'), card('5', 'spades')],
      single,
      trump,
      { seat: 1, winnerSeat: 0, winning: single, lastToPlay: false },
    );
    expect(
      offSuit.find((o) => o.cardIds.includes('0:hearts:A'))!.features[23],
    ).toBe(0);
    expect(
      offSuit.find((o) => o.cardIds.includes('0:spades:5'))!.features[23],
    ).toBe(1);
  });
  it('counts all public trick points and only opponents still to act', () => {
    let trick = startTrick({
      playerCount: 4,
      hands: [[card('10')], [card('J')], [card('K')], [card('A')]],
      trump,
      attackingTeam: 'A',
      leaderSeat: 0,
    });
    for (const [seat, id] of [
      [0, '0:clubs:10'],
      [1, '0:clubs:J'],
    ] as const) {
      const result = playCards(trick, seat, [id]);
      if (!result.ok) throw new Error(result.message);
      trick = result.state;
    }
    const context = botPlayContext(trick, 0);
    expect(context.trickPoints).toBe(10);
    expect(context.opponentsRemaining).toBe(1);
    expect(context.winnerSeat).toBe(1);
  });
  it('protects a point trick with a legal ace while an opponent remains', () => {
    const lead = decomposeLead([card('10')], trump)!;
    const hand = [card('J'), card('A')];
    const model = newPolicy(seededRandom(8));
    const context = {
      seat: 1,
      winnerSeat: 0,
      winning: lead,
      lastToPlay: false,
      trickPoints: 10,
      opponentsRemaining: 1,
    };
    let recorded: PolicyExperience | undefined;
    expect(
      choosePolicyPlay(model, hand, lead, trump, context, undefined, (e) => {
        recorded = e;
      }),
    ).toEqual(['0:clubs:A']);
    expect(recorded?.teacherIndex).toBeGreaterThanOrEqual(0);
    expect(recorded?.teacherWeight).toBe(0.05);
  });
  it('separates dealer and ace opening features without changing the role coordinate', () => {
    const context = {
      seat: 0,
      dealerSeat: 0,
      role: 'attackers' as const,
      defenderScore: 0,
      swapThreshold: 80,
    };
    const options = leadOptions(
      [card('A'), card('5', 'hearts')],
      trump,
      context,
    );
    const ace = options.find((o) => o.cardIds.includes('0:clubs:A'))!;
    expect(ace.features[2]).toBe(1);
    expect(ace.features.slice(22, 26)).toEqual([1, 1, 1, 1]);
  });
});
